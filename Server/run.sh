#!/bin/bash

# Build and run the server from the command line
# Optionally, you can give a single argument: build or test. The default is build, which will also run the server after building.

buildLocation=/tmp/.build-server

CMD=$1
if [ "empty${CMD}" == "empty" ] ; then
	CMD="build"
fi

if [ $? == 0 ] && [ "${CMD}" == "test" ] ; then
	# Some test cases expect `Cat.jpg` in /tmp
	cp Resources/Cat.jpg /tmp
fi


# use --verbose flag to show more output
swift "${CMD}" -Xswiftc -DDEBUG -Xswiftc -DSERVER --build-path "${buildLocation}"

if [ $? == 0 ] && [ "${CMD}" == "build" ] ; then
	echo ${buildLocation}/debug/Main ../../Private/Server/SharedImagesServer.json
	# .build/debug/Main ../../Private/Server/Server.json
fi

