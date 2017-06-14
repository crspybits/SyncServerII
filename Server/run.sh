#!/bin/bash

# Build and run the server from the command line
# Optionally, you can give a single argument: build or test. The default is build, which will also run the server after building.

buildLocation=~/builds/.build-server

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
	# ( ./run.sh > ~/output.log 2>&1 & ) 
	# ${buildLocation}/debug/Main ../../Private/Server/SharedImagesServer.json
	${buildLocation}/debug/Main ../../Private/Server/Server.json
fi

exit 0

# For running SharedImages server on AWS

# `stdbuf` gets rid of buffering; see also https://serverfault.com/questions/294218/is-there-a-way-to-redirect-output-to-a-file-without-buffering-on-unix-linux
cd
sudo bash
source ~/.bashrc
cd SyncServerII/Server/
# Should have check here to make sure `Main` isn't running
# and need to make sure we have selected SharedImages db.
( stdbuf -o0 ./run.sh > ~/output.log 2>&1 & ) 


