#!/bin/bash

# Odd things seem to happen if you have xcode running when you run tweakXcodeproj.rb
RESULT=`killall Xcode 2>&1`

KILLED=0

if [ "empty$RESULT" == "empty" ]; then
	KILLED=1
elif [ "$RESULT" == "No matching processes belonging to you were found" ]; then
	# killall outputs "No matching processes belonging to you were found" if Xcode is not running, but that's OK.
	KILLED=1
fi

if [[ KILLED -eq 1 ]]; then
	swift package generate-xcodeproj
	./tweakXcodeproj.rb
	echo "Success!"
else
	echo "Youch: Could not kill xcode-- shut it down manually and try this again."
fi