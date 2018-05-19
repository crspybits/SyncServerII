#!/bin/bash

# Add a blank discussion thread file to all images that don't (yet) have a discussion thread. This also requires a change to appMetaData for each image file that doesn't yet have discussion thread.
# First, I need to figure out which images don't have a discussion thread. Could do this by:
# 	a) Get a list of all image files
# 	b) Get a list of all discussion thread files.
# 	c) For each discussion thread file:
# 		i) read its JSON and get the associated imageUUID.
# 		ii) remove that file from the list of image files.
# 	d) The remaining image files do not have discussion threads.
# 	e) For each remaining image file:
# 		i) Generate an empty discussion thread file for that image file. Use as a device UUID, for the discussion thread file, the same as for the image file. Put the imageUUID into that file.
# 		ii) Generate mySQL statements to insert this file reference into the FileIndex, along with app meta data for this file.

# Usage: pass in the directory to process; doesn't need a trailing "/", and the directory to place the output files.

INPUT_DIRECTORY=$1
OUTPUT_DIRECTORY=$2

# a file in the output directory
SQL_STMTS="4.sql"

# names without paths in directory.
DISCUSSIONS=()
IMAGES=()

if [ ! -d $OUTPUT_DIRECTORY ]; then
	mkdir -p $OUTPUT_DIRECTORY;
fi

for fileNameWithPath in "$INPUT_DIRECTORY"/*; do
    mimeType=`file --mime-type "$fileNameWithPath" | awk '{print $NF}'`
    # echo \"$mimeType\"

	fileName=$(basename "$fileNameWithPath")

    if [ "$mimeType" == "text/plain" ]; then
        DISCUSSIONS+=("$fileName")
    else
        IMAGES+=("$fileName")
    fi
done

# echo ${DISCUSSIONS[*]}
# echo ${IMAGES[*]}

removeImageFromList () {
	local imageUUID=$1

	for imageFileIndex in ${!IMAGES[*]}; do
		local imageFile=${IMAGES[$imageFileIndex]}
		if [[ $imageFile == *"$imageUUID"* ]]; then
			unset IMAGES[$imageFileIndex]
			# So we don't get gaps in the array
			IMAGES=( "${IMAGES[@]}" )
			return
		fi
	done

	echo "ERROR: Not contained: $imageUUID"
}

echo "Number of images before:" ${#IMAGES[@]}
echo "Number of discussions before:" ${#DISCUSSIONS[@]}

for discussionFile in ${DISCUSSIONS[*]}; do
	imageUUID=`jq -r .imageUUID < "$INPUT_DIRECTORY/$discussionFile"`
	# This image has a discussion, remove it from list of images
	removeImageFromList $imageUUID
done

echo "Number of images after:" ${#IMAGES[@]}

# Generate discussion threads for the images that don't have them.
# Put them in $OUTPUT_DIRECTORY
for imageFile in ${IMAGES[*]}; do
	# Files are named like this: 0A97AC41-0E4C-40F7-92FB-5601863521BA.FAF13FCE-EA89-4BCA-84C2-D6F594E3A429.0.jpg
	# The first UUID is the UUID of the image. The second is the UUID of the device.

	# Split a string at period delimiters: From https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash
	splitAtPeriods=(${imageFile//./ })
	imageUUID=${splitAtPeriods[0]}

	deviceUUID=${splitAtPeriods[1]}

	# Discussion thread files have initial contents like: {"elements":[],"imageUUID":"6FD07995-66E0-4E51-96E5-E5C0E1A197C0"}
	contents="{\"elements\":[],\"imageUUID\":\"$imageUUID\"}"
	
	# The number of bytes in the initial discussion thread file
	fileSizeBytes=${#contents}

	# Generate UUID for new discussion thread file. Uses MacOS function. 
	discussionUUID=`uuidgen`

	# Need to fake a deviceUUID to make the file name.
	discussionFileName=$discussionUUID.$deviceUUID.0.txt

	echo -n $contents > $OUTPUT_DIRECTORY/$discussionFileName

	# Generate mySQL to insert into the FileIndex table to add this discussion. This will be in two parts

	fileGroupUUID=`uuidgen`
	userId=1
	discussionAppMetaData='{"fileType":"discussion"}'

	# 1) For the new discussion thread file
	insert="INSERT INTO FileIndex (fileUUID, userId, deviceUUID, fileGroupUUID, creationDate, updateDate, mimeType, appMetaData, deleted, fileVersion, appMetaDataVersion, fileSizeBytes) VALUES (\"$discussionUUID\", $userId, \"$deviceUUID\", \"$fileGroupUUID\", Now(), Now(), \"text/plain\", '$discussionAppMetaData', FALSE, 0, 0, $fileSizeBytes);"

	# 2) An update to the existing image file to give it the new fileGroupUUID
	update="UPDATE FileIndex SET fileGroupUUID = \"$fileGroupUUID\" WHERE fileUUID = \"$imageUUID\";"

	echo "$insert" >> "$OUTPUT_DIRECTORY"/$SQL_STMTS
	echo "$update" >> "$OUTPUT_DIRECTORY"/$SQL_STMTS
	echo >> "$OUTPUT_DIRECTORY"/$SQL_STMTS
done

