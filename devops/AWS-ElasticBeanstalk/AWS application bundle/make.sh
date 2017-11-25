#!/bin/bash

# Purpose: Creates an application bundle for upload to the AWS Elastic Beanstalk, for running SyncServer
# Usage: ./make.sh <file>.json [<environment-variables>.yml]
# The .json file will be used as the Server.json file to start the server.
# The environment variables are a little tricky. See the README.txt in this folder.
# WARNING: I believe AWS doesn't do well with Server.json files that have blank lines in the technique I'm using to transfer the file to the Docker container.
# Assumes: That this script is run from the directory the script is located in.

# Examples: 

# SharedImages staging server
# ./make.sh ../EBSEnvironments/sharedimages-staging\ /Server.json ../EBSEnvironments/sharedimages-staging\ /configure.yml

# iOS Client testing server
# ./make.sh ../EBSEnvironments/syncserver-testing/Server.json ../EBSEnvironments/syncserver-testing/configure.yml

SERVER_JSON=$1
ENV_VAR_PARAM=$2
ZIPFILE=bundle.zip
ENV_VARIABLES="env.variables.config"

# 6 Extra blanks because config file needs these prepended before json file lines for YAML formatting.
EXTRA_BLANKS="      "

if [ ! -d .ebextensions ]; then
	mkdir .ebextensions
fi

if [ ! -d tmp ]; then
	mkdir tmp
fi

if [ "empty${SERVER_JSON}" == "empty" ]; then
	echo "**** You need to give the server .json file as a parameter!"
	exit
fi

if [ "empty${ENV_VAR_PARAM}" != "empty" ]; then
	if [ ! -e "${ENV_VAR_PARAM}" ]; then
		echo "**** Couldn't find: ${ENV_VAR_PARAM} -- giving up!"
		exit
	fi
	
	echo "Using your environment variables file: ${ENV_VAR_PARAM}"

	# Make sure the environment variables file is named with a .config extension.
	cp "${ENV_VAR_PARAM}" "$ENV_VARIABLES"
	mv -f "$ENV_VARIABLES" .ebextensions
fi

echo "Using ${SERVER_JSON} as the server json file ..."
echo

cp -f raw.materials/Server.json.config tmp

# There's some trickyness to avoid removing white space and avoid removing the last line if it doesn't end with a newline. See https://stackoverflow.com/questions/10929453/
while IFS='' read -r line || [[ -n "$line" ]]; do
	echo "${EXTRA_BLANKS}$line" >> tmp/Server.json.config
done < "${SERVER_JSON}"

mv -f tmp/Server.json.config .ebextensions
cp -f raw.materials/SyncServer.ngnix.config .ebextensions

if [ -e ${ZIPFILE} ]; then
	echo "Removing old ${ZIPFILE}"
  	rm ${ZIPFILE}
fi

zip -r ${ZIPFILE} Dockerrun.aws.json .ebextensions
# zip -d ${ZIPFILE} __MACOSX/\*

if [ -e ~/Desktop/${ZIPFILE} ]; then
	rm ~/Desktop/${ZIPFILE}
fi

mv ${ZIPFILE} ~/Desktop
rm .ebextensions/*
rmdir .ebextensions
rmdir tmp

echo
echo "application bundle ${ZIPFILE} created and moved to the Desktop-- upload this to AWS."

