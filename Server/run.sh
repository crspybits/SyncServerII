#!/bin/bash

# Build and run the server from the command line

# use --verbose flag to show more output
swift build -Xswiftc -DDEBUG -Xswiftc -DSERVER

# swift test -Xswiftc -DDEBUG -Xswiftc -DSERVER

if [ $? == 0 ] ; then
	.build/debug/Main ../../Private/Server/SharedImagesServer.json
	# .build/debug/Main ../../Private/Server/Server.json
fi