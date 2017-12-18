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
#
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
#   ./runTests.sh filter ServerTests.DatabaseModelTests
#   ./runTests.sh suites google
#   ./runTests.sh suites sharing
#   ./runTests.sh suites owning

TEST_JSON="Tools/TestSuites.json"
COMMAND=$1
OPTION=$2
ALL_COUNT=`jq -r '.all | length' < ${TEST_JSON}`
BASIC_SWIFT_TEST_CMD="swift test -Xswiftc -DDEBUG -Xswiftc -DSERVER"
SWIFT_DEFINE="-Xswiftc -D"
SYNCSERVER_TEST_MODULE="ServerTests"
TEST_OUT_DIR="/tmp/SyncServer/"

# Final stats
TOTAL_SUITES_PASSED=0
TOTAL_SUITES_FAILED=0
TOTAL_FAILED_TEST_CASES=0

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
    local testDescription=$2
    local outputPrefix=$3
    local compilerResult=$4

    # The following depends on the assumption: That when a Swift test passes, there is a line containing the text " 0 failure", and that each test, pass or fail has lines "failure" in them (e.g., 0 failures or N failures). And further, that there are two of these lines per test. Of course, changes in the Swift testing output could change this and break this assumption.

    # The number of lines of output, divided by 2, is the total number of tests.
    local totalLines=`cat "$resultsFileName" | grep  ' failure' | grep -Ev ERROR | wc -l`
    local totalTests=`expr $totalLines / 2`

    # This gives failures-- the number of lines divided by 2 is N, the number of failures.
    local failures=`cat "$resultsFileName" | grep  ' failure' | grep -Ev ' 0 failure' | grep -Ev ERROR | wc -l`
    failures=`expr $failures / 2`

    if [ $compilerResult -ne 0 ]; then
        printf "${outputPrefix}${RED}Compiler failure${NC}: $testDescription\n"
        TOTAL_SUITES_FAILED=`expr $TOTAL_SUITES_FAILED + 1`
    elif [ "$failures" == "0" ]; then
        printf "${outputPrefix}${GREEN}Passed${NC} ($totalTests tests): $testDescription\n"
        TOTAL_SUITES_PASSED=`expr $TOTAL_SUITES_PASSED + 1`
    else
        printf "${outputPrefix}${RED}$failures FAILURES${NC} (out of $totalTests tests): $testDescription\n"
        TOTAL_FAILED_TEST_CASES=`expr $TOTAL_FAILED_TEST_CASES + $failures`
        TOTAL_SUITES_FAILED=`expr $TOTAL_SUITES_FAILED + 1`
    fi
}

runSpecificSuite () {
    # Parameters:
    local suiteName=$1
    local suiteTestCount=`jq .$suiteName' | length' < ${TEST_JSON}`

    echo Running $suiteName containing $suiteTestCount test suites

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

            printf "\trunning $testCaseName with parameters:\n\t\t$commandParams\n"
            outputPrefix="\t\t"
        else
            outputPrefix="\t"
        fi

        local outputFileName="$TEST_OUT_DIR"/$testCaseName.$fileNameCounter
        $BASIC_SWIFT_TEST_CMD $commandParams --filter $SYNCSERVER_TEST_MODULE.$testCaseName > $outputFileName

        # For testing to see if the compiler failed.
        local compilerResult=$?

        generateOutput $outputFileName "$testCaseName.$fileNameCounter" $outputPrefix $compilerResult

        fileNameCounter=`expr $fileNameCounter + 1`
    done
}

if [ "${COMMAND}" != "suites" ] && [ "${COMMAND}" != "filter" ]; then
    echo "Command was not 'suites' or 'filter'-- see Usage at the top of this script file."
    exit 1
fi

mkdir "$TEST_OUT_DIR" >& /dev/null

if  [ "${COMMAND}" == "suites" ] ; then
    # option must be 'all' or from the all list.
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
            runSpecificSuite $SUITE
        done
    else 
        runSpecificSuite ${OPTION}
    fi
else
    # filter command
    OUTPUT_FILE_NAME="$TEST_OUT_DIR"/filter.txt
    $BASIC_SWIFT_TEST_CMD --filter ${OPTION} > $OUTPUT_FILE_NAME
    generateOutput $OUTPUT_FILE_NAME "${OPTION}"
fi

generateFinalOutput