#!/bin/bash

# Build and run the server from the command line
# Usage:
#	1) ./run.sh test [Optional-Specific-Test] -- run server tests
#		Optional-Specific-Test Format: 
#			<test-module>.<test-case> or <test-module>.<test-case>/<test>
#		./run.sh test ServerTests.SharingAccountsController_CreateSharingInvitation
#
#	2) ./run.sh [local | aws] <PathToJsonConfigFile> -- start up the server
#		In this case, the server is built before running.
#		e.g., 
#			./run.sh local ../Private/Server/Server.json
#			./run.sh aws ../../Private/Server/SharedImagesServer.json

#		When running on AWS, you first need to do :
#		cd ~/SyncServerII/Server; sudo bash; source ~/.bashrc

buildLocation=~/builds/.build-server

ARG1=$1
ARG2=$2

if [ "empty${ARG1}" == "empty" ] ; then
	echo "See usage instructions!"
	exit 1
elif [ "${ARG1}" == "test" ] ; then
	# Some test cases expect `Cat.jpg` in /tmp
	cp Resources/Cat.jpg /tmp
	CMD="test"
	
	if [ "empty${ARG2}" != "empty" ] ; then
		# -s command line option to `swift` indicates a specific test
		SPECIFIC_TEST="-s ${ARG2}"
	fi
elif [ "${ARG1}" == "local" ] || [ "${ARG1}" == "aws" ] ; then
	if [ "empty${ARG2}" == "empty" ] ; then
		echo "See usage instructions!"
		exit 1	
	fi
	
	if [ "${ARG1}" == "aws" ] ; then
		RUNCHECK=`ps -A | grep Main`
		if [ "empty${RUNCHECK}" != "empty" ] ; then	
			echo "The server is already running: "
			ps -A | grep Main
			exit 1
		fi
	fi
	
	CMD="build"
	JSONCONFIG="${ARG2}"
else
	echo "See usage instructions!"
	exit 1
fi

# use --verbose flag on `swift` to show more output

if [ "${ARG1}" == "test" ] ; then
	echo "Building server and then running tests ..."
	swift "${CMD}" ${SPECIFIC_TEST} -Xswiftc -DDEBUG -Xswiftc -DSERVER --build-path "${buildLocation}"
else
	echo "Building server ..."
	swift "${CMD}" -Xswiftc -DDEBUG -Xswiftc -DSERVER --build-path "${buildLocation}"
fi

if [ $? == 0 ] && [ "${CMD}" == "build" ] ; then
	if [ "${ARG1}" == "local" ] ; then
		echo "Starting server locally..."
		${buildLocation}/debug/Main "${JSONCONFIG}"
	else 
		echo "Starting server on AWS ..."	
		# `stdbuf` gets rid of buffering; see also https://serverfault.com/questions/294218/is-there-a-way-to-redirect-output-to-a-file-without-buffering-on-unix-linux
		( stdbuf -o0 ${buildLocation}/debug/Main "${JSONCONFIG}" > ~/output.log 2>&1 & ) 
	fi
fi

exit 0

# Installing next version:
git reset --hard
git pull origin master
# Until I get this changed, need to change to using port 443 and change the run.sh


