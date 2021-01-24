#!/bin/bash

# Usage: ./runTests.sh <Command> <Option>
# <Command> is one of:
#   suites -- where <Option> is one of:
#       all -- run all of the following suites.
#       basic -- tests needing no account
#       google -- run tests for Google specific accounts
#       dropbox -- run tests for Dropbox specific accounts
#       facebook -- run tests for Facebook specific accounts
#       owning -- run tests that depend only on owning account parameter
#       sharing-create -- run sharing tests-- these depend on several parameters
#       sharing-redeem
#       sharing-file
#   filter -- pass along the <Option> argument to swift tests as the --filter
#   run -- the <Option> is the complete swift test run command
# Output in each case is in two parts:
#   1) A series of lines of the format
#       Passed | N Failures ([out of] K tests): <Test suite name>[, <Parameters if any>]
#           where N in Failures are the number of individual test case failures.
#           where K is the numbe rof individual tests conducted.
#   2) After the above series of lines, a single line summary:
#       Suites passed: X; Suite failures: Y (Z test cases)
#           where 
#               X is the number of lines above that were marked as Passed; 
#               Y is the number of lines that had non-zero failures
#               Z is the cummulative sum of N in the failure cases.

# Assumption: This assumes it's run from the root of the repo.

# Examples
#   ./Tools/runTests.sh filter ServerTests.DatabaseModelTests
#   ./Tools/runTests.sh suites google
#   ./Tools/runTests.sh suites sharing
#   ./Tools/runTests.sh suites owning

TEST_JSON="Tools/TestSuites.json"
COMMAND=$1
OPTION=$2
ALL_COUNT=`jq -r '.all | length' < ${TEST_JSON}`
BUILD_PATH=".build.linux"

# See https://oleb.net/2020/swift-test-discovery/
# For --build-path, see https://stackoverflow.com/questions/62805684/server-side-swift-development-on-macos-with-xcode-testing-on-docker-ubuntu-how
BASIC_SWIFT_TEST_CMD="swift test --build-path ${BUILD_PATH} --enable-test-discovery -Xswiftc -DDEBUG -Xswiftc -DSERVER"

SWIFT_DEFINE="-Xswiftc -D"
# SYNCSERVER_TEST_MODULE="ServerTests"
TEST_OUT_DIR=".testing"

# Final stats
TOTAL_SUITES_PASSED=0
TOTAL_SUITES_FAILED=0
TOTAL_FAILED_TEST_CASES=0

# Create TEST_OUT_DIR if it's not there.
mkdir -p "$TEST_OUT_DIR"

# See https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

generateFinalOutput () {
    if [ $TOTAL_SUITES_FAILED == "0" ]; then
        printf "${GREEN}Every test suite passed.${NC} There were $TOTAL_SUITES_PASSED of them.\n"
    else
        printf "Suites passed: $TOTAL_SUITES_PASSED; ${RED}Suite failed: $TOTAL_SUITES_FAILED ($TOTAL_FAILED_TEST_CASES test cases)${NC}\n"
    fi
}

generateOutput () {
    # Parameters:
    local resultsFileName=$1
    local outputPrefix=$2
    local compilerResult=$3

    # The following depends on the assumption:
    # As of 8/26/20, with Swift 5.3 beta, the filtered testing results have a summary line:
    #   Executed 12 tests, with 54 failures (6 unexpected) in 270.938 (270.938) seconds
    # The number in parentheses "(N unexpected)" is the number of test cases that failed.

    # https://linuxize.com/post/regular-expressions-in-grep/
    # The following pulls out a single line, such as:
    #   Executed 12 tests, with 54 failures (6 unexpected)

    local executedText=`cat "$resultsFileName" | grep -Eo 'Executed [0-9]* test[s]?, with [0-9]* failure[s]? \([0-9]* unexpected\)' | head -n 1`

    # 2nd item -- number tests
    # 5th item -- number of failures
    # 7th item -- number unexpected-- not sure what this is.
    
    local totalTests=`echo "$executedText" | awk '{print $2}'`
    local failures=`echo "$executedText" | awk '{print substr($7,2); }'`
        
    if [ "empty${failures}" == "empty" ] || [ "$failures" == 0 ]; then
        # sometimes `unexpected` is 0, but `failures` are non-zero.
        
        if [ "empty${executedText}" == "empty" ]; then
            printf "${outputPrefix}${RED}Unknown failure${NC}\n"
            
            # Just to give failures a value because otherwise getting script failures. e.g., "expr: syntax error"
            failures=1
        else
            failures=`echo "$executedText" | awk '{print $5}'`
        fi
    fi

    TOTAL_FAILED_TEST_CASES=`expr $TOTAL_FAILED_TEST_CASES + $failures`

    local possibleCompileFailure="false"

    if [ "${compilerResult}empty" != "empty" ] && [ $compilerResult -ne 0 ]; then
        possibleCompileFailure="true"
    fi
    
#    printf "possibleCompileFailure: $possibleCompileFailure\n"
#    printf "failures: $failures\n"
#    printf "totalTests: $totalTests\n"

    if [ $possibleCompileFailure == "false" ] && [ "$failures" == 0 ]; then
        printf "${outputPrefix}${GREEN}Passed${NC} ($totalTests/$totalTests tests): $resultsFileName\n"
        TOTAL_SUITES_PASSED=`expr $TOTAL_SUITES_PASSED + 1`
    else
        TOTAL_SUITES_FAILED=`expr $TOTAL_SUITES_FAILED + 1`

        if [ $possibleCompileFailure == "true" ] && [ "$failures" == 0 ]; then
             printf "${outputPrefix}${RED}Compile failure${NC}: $resultsFileName\n"
        else
            printf "${outputPrefix}${RED}$failures FAILURES${NC} (out of $totalTests tests): $resultsFileName\n"
        fi
    fi
}

runSpecificSuite () {
    # Parameters:
    local suiteName=$1
    local runOrPrint=$2 # "run" or "print"

    local suiteTestCount=`jq .$suiteName' | length' < ${TEST_JSON}`

    if [ $runOrPrint == "run" ]; then
        echo Running $suiteName containing $suiteTestCount test suites
    fi
    
    # To ensure the output filename (in /tmp) is unique
    local fileNameCounter=0

    for suiteIndex in $(seq 0 `expr $suiteTestCount - 1`); do 
        local testCase=`jq -r .$suiteName[$suiteIndex] < ${TEST_JSON}`
        local testCaseName=`echo $testCase | jq -r .name`
        local hasParameters=`echo $testCase | jq 'has("parameters")'`
        local commandParams=""
        local outputPrefix=""

        if [ $hasParameters == "true" ]; then
            # Generate command line parameter "defines"
            local parameters=`echo $testCase | jq .parameters`
            local parametersLength=`echo $parameters | jq length`
            
            for paramIndex in $(seq 0 `expr $parametersLength - 1`); do
                local parameter=`echo $parameters | jq -r .[$paramIndex]`
                commandParams="$commandParams ${SWIFT_DEFINE}$parameter"
            done

            if [ $runOrPrint == "run" ]; then
                printf "\trunning $testCaseName with command:\n"
                outputPrefix="\t\t"
            
                # I'm having problems running successive builds with parameters, back-to-back. Getting build failures. This seems to fix it. The problem stems from having to rebuild on each test run-- since these are build-time parameters. Somehow the build system seems to get confused otherwise.
                # 8/15/20; Try again now with current swift version to not use this
                # swift package --build-path ${BUILD_PATH} clean
            fi
        else
            outputPrefix="\t"
        fi

        local outputFileName="$TEST_OUT_DIR"/$testCaseName.$fileNameCounter
        # local command="$BASIC_SWIFT_TEST_CMD $commandParams --filter $SYNCSERVER_TEST_MODULE.$testCaseName"
        local command="$BASIC_SWIFT_TEST_CMD $commandParams --filter $testCaseName"

        printf "$outputPrefix$command\n"

        if [ $runOrPrint == "run" ]; then
            $command > $outputFileName
        fi

        # For testing to see if the compiler failed.
        local compilerResult=$?

        if [ $runOrPrint == "run" ]; then
            generateOutput $outputFileName $outputPrefix $compilerResult
        fi

        fileNameCounter=`expr $fileNameCounter + 1`
    done
}

if [ "${COMMAND}" != "suites" ] && [ "${COMMAND}" != "print-suites" ] && [ "${COMMAND}" != "filter" ] && [ "${COMMAND}" != "run" ]; then
    echo "Command was not 'suites', 'print-suites', 'filter', or 'run' -- see Usage at the top of this script file."
    exit 1
fi

if  [ "${COMMAND}" == "suites" ] || [ "${COMMAND}" == "print-suites" ] ; then
    # option must be 'all' or from the all list.

    if  [ "${COMMAND}" == "suites" ] ; then
        runOrPrint="run"
    else
        runOrPrint="print"
    fi

    if  [ "${OPTION}" != "all" ] ; then
        FOUND=0
        for i in $(seq 0 `expr $ALL_COUNT - 1`); do 
            SUITE=`jq -r .all[$i] < ${TEST_JSON}`
            if [ "$SUITE" == "${OPTION}" ]; then
                FOUND=1
                break
            fi
        done
        if [ $FOUND == "0" ]; then
            echo "suites option not found! See usage."
            exit 1
        fi
    fi

    if [ "${OPTION}" == "all" ] ; then
        # iterate over all suites
        for i in $(seq 0 `expr $ALL_COUNT - 1`); do 
            SUITE=`jq -r .all[$i] < ${TEST_JSON}`
            runSpecificSuite $SUITE $runOrPrint
        done
    else 
        runSpecificSuite ${OPTION} $runOrPrint
    fi
elif [ "${COMMAND}" == "filter" ] ; then
    OUTPUT_FILE_NAME="$TEST_OUT_DIR"/filter.txt
    
    command="$BASIC_SWIFT_TEST_CMD --filter ${OPTION}"
    printf "$command\n"
    $command > $OUTPUT_FILE_NAME

    # For testing to see if the compiler failed.
    compilerResult=$?

    generateOutput $OUTPUT_FILE_NAME "\t" $compilerResult
else
    # run command

    # See https://stackoverflow.com/questions/9057387/process-all-arguments-except-the-first-one-in-a-bash-script
    COMMAND=${@:2}

    TMPFILE=`mktemp $TEST_OUT_DIR/tmp.XXXXXXXX`

    echo "Running: $COMMAND"
    $COMMAND > $TMPFILE

    # For testing to see if the compiler failed.
    compilerResult=$?

    generateOutput $TMPFILE "\t" $compilerResult
fi

generateFinalOutput
