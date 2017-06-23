#!/bin/bash

# Build and run the server from the command line
# Usage:
#	1) run test -- run server tests
#	2) run server <PathToJsonConfigFile> -- start up the server
#		In this case, the server is built before running.
#		e.g., 
#			./run.sh server ../../Private/Server/SharedImagesServer.json
#			./run.sh server ../../Private/Server/Server.json

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
elif [ "${ARG1}" == "server" ] ; then
	if [ "empty${ARG2}" == "empty" ] ; then
		echo "See usage instructions!"
		exit 1	
	fi
	
	CMD="build"
	JSONCONFIG="${ARG2}"
else
	echo "See usage instructions!"
	exit 1
fi

# use --verbose flag to show more output
swift "${CMD}" -Xswiftc -DDEBUG -Xswiftc -DSERVER --build-path "${buildLocation}"

if [ $? == 0 ] && [ "${CMD}" == "build" ] ; then
	${buildLocation}/debug/Main "${JSONCONFIG}"
fi

exit 0

# For running SharedImages server on AWS

# `stdbuf` gets rid of buffering; see also https://serverfault.com/questions/294218/is-there-a-way-to-redirect-output-to-a-file-without-buffering-on-unix-linux
cd
sudo bash
source ~/.bashrc
cd SyncServerII/Server/
RUNCHECK=`ps -A | grep Main`
if [ "empty${RUNCHECK}" == "empty" ] ; then
	( stdbuf -o0 ./run.sh server ../../Private/Server/SharedImagesServer.json > ~/output.log 2>&1 & ) 
elif
	echo "The server is already running: "
	ps -A | grep Main
fi

# Installing next version:
git reset --hard
git pull origin master
# Until I get this changed, need to change to using port 443 and change the run.sh


