#!/bin/bash

# Build and run the server from the command line

swift build -Xswiftc -DDEBUG -Xswiftc -DSERVER

if [ $? == 0 ] ; then
	.build/debug/Main ../../Private/Server/SharedImagesServer.json
fi