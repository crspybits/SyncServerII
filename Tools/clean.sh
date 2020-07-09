#!/bin/bash

# See https://stackoverflow.com/questions/62805684/server-side-swift-development-on-macos-with-xcode-testing-on-docker-ubuntu-how

/bin/rm -rf .build.linux

# 9/14/18; Get a problem with `swift package update` now if we leave this in. An apparent dependency "cycle" or other such that issue that never gets resolved, never returns from swift package update.
# rm Package.resolved >& /dev/null

/bin/rm -rf .testing

