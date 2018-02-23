#!/bin/bash

# Usage: pass in the directory to process

DIRECTORY=$1

for fileNameWithPath in "$DIRECTORY"/*; do
    mimeType=`file --mime-type "$fileNameWithPath" | awk '{print $NF}'`
    # echo \"$mimeType\"
    if [ "$mimeType" == "text/plain" ]; then
        extension="txt"
    else
        extension="jpg"
    fi

    # fileName=$(basename "$fileNameWithPath")
    mv "$fileNameWithPath" "$fileNameWithPath.$extension"
done