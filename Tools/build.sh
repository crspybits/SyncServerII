#!/bin/bash

## Note: I'd like to have the option of doing `swift package update` as part of this, but it seems like while you can run `swift build --skip-update`, there's no `swift build --update`. And running `swift build` by itself does *not* update from the latest packages. I just verified this. Odd.
## In order to update, you have to do this in two steps. First, run `swift package update` and then second, run this build script. This seems to do more work than it needs to. It actually seems to update twice this way.

# Usage: build [verbose]

VERBOSE=""
if [ "$1empty" == "verboseempty" ]; then
	VERBOSE="-v"
fi

# For --build-path, see https://stackoverflow.com/questions/62805684/server-side-swift-development-on-macos-with-xcode-testing-on-docker-ubuntu-how

swift build --build-path .build.linux $VERBOSE -Xswiftc -DDEBUG -Xswiftc -DSERVER
