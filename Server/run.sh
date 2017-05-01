#!/bin/bash

# Build and run the server from the command line
# Optionally, you can give a single argument: build or test. The default is build, which will also run the server after building.

CMD=$1
if [ "empty${CMD}" == "empty" ] ; then
	CMD="build"
fi

# use --verbose flag to show more output
swift "${CMD}" -Xswiftc -DDEBUG -Xswiftc -DSERVER

if [ $? == 0 ] && [ "${CMD}" == "build" ] ; then
	.build/debug/Main ../../Private/Server/SharedImagesServer.json
	# .build/debug/Main ../../Private/Server/Server.json
fi