#!/bin/bash

# Odd things seem to happen if you have xcode running when you run tweakXcodeproj.rb
killall Xcode

swift package generate-xcodeproj
./tweakXcodeproj.rb
