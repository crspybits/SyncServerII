#!/bin/bash

# Usage: build [verbose]
VERBOSE=""
if [ "$1empty" == "verboseempty" ]; then
	VERBOSE="-v"
fi

# For --build-path, see https://stackoverflow.com/questions/62805684/server-side-swift-development-on-macos-with-xcode-testing-on-docker-ubuntu-how

swift build --build-path .build.linux $VERBOSE -Xswiftc -DDEBUG -Xswiftc -DSERVER
