#!/bin/bash

# Purpose: Creates an application bundle for upload to the AWS Elastic Beanstalk, for running SyncServer
# Usage: ./make.sh <file>.json
# The .json file will be used as the Server.json file to start the server.
# WARNING: I believe AWS doesn't do well with Server.json files that have blank lines in the technique I'm using to transfer the file to the Docker container.

SERVER_JSON=$1
ZIPFILE=bundle.zip

# 6 Extra blanks because config file needs these prepended before json file lines for YAML formatting.
EXTRA_BLANKS="      "

if [ "empty${SERVER_JSON}" == "empty" ]; then
	echo "**** You need to give the server .json file as a parameter!"
	exit
fi

echo "Using ${SERVER_JSON} as the server json file ..."
echo

if [ ! -d .ebextensions ]; then
	mkdir .ebextensions
fi

if [ ! -d tmp ]; then
	mkdir tmp
fi

cp -f raw.materials/Server.json.config tmp

# There's some trickyness to avoid removing white space and avoid removing the last line if it doesn't end with a newline. See https://stackoverflow.com/questions/10929453/
while IFS='' read -r line || [[ -n "$line" ]]; do
	echo "${EXTRA_BLANKS}$line" >> tmp/Server.json.config
done < ${SERVER_JSON}

mv -f tmp/Server.json.config .ebextensions
cp -f raw.materials/SyncServer.ngnix.config .ebextensions

if [ -e ${ZIPFILE} ]; then
	echo "Removing old ${ZIPFILE}"
  	rm ${ZIPFILE}
fi

zip -r ${ZIPFILE} Dockerrun.aws.json .ebextensions
# zip -d ${ZIPFILE} __MACOSX/\*

rm ~/Desktop/${ZIPFILE} 2> /dev/null
mv ${ZIPFILE} ~/Desktop
rm .ebextensions/*
rmdir .ebextensions

echo
echo "application bundle ${ZIPFILE} created and moved to the Desktop-- upload this to AWS."

