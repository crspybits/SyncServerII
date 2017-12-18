#!/bin/bash

# Usage: build [verbose]
VERBOSE=""
if [ "$1empty" == "verboseempty" ]; then
	VERBOSE="-v"
fi

swift build $VERBOSE -Xswiftc -DDEBUG -Xswiftc -DSERVER