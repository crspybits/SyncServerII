#!/bin/bash

# Purpose: Creates an application bundle for upload to the AWS Elastic Beanstalk, for running SyncServer
# Usage: ./make.sh <file>.json [<environment-configuration>.yml]
# The .json file will be used as the Server.json file to start the server.
# To see how to get an environment configuration look at: 	http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-configuration-savedconfig.html
# WARNING: I believe AWS doesn't do well with Server.json files that have blank lines in the technique I'm using to transfer the file to the Docker container.
# Assumes: That this script is run from the directory the script is located in.

# Examples: 
# ./make.sh ../../../Private/Server.json.aws.app.bundles/iOSClient-testing.json 
# ./make.sh ../../../Private/Server.json.aws.app.bundles/SharedImages-staging.json example-manifests/SharedImages-staging.yml

SERVER_JSON=$1
ENV_CONFIG=$2
ZIPFILE=bundle.zip
FINAL_ENV_CONFIG=""

# 6 Extra blanks because config file needs these prepended before json file lines for YAML formatting.
EXTRA_BLANKS="      "

if [ "empty${SERVER_JSON}" == "empty" ]; then
	echo "**** You need to give the server .json file as a parameter!"
	exit
fi

if [ "empty${ENV_CONFIG}" != "empty" ]; then
	if [ ! -e "${ENV_CONFIG}" ]; then
		echo "**** Couldn't find: ${ENV_CONFIG} -- giving up!"
		exit
	fi
	
	echo "Using your environment configuration: ${ENV_CONFIG}"

	# Make sure the env configuration is named env.yml; see the web reference given above.
	cp "${ENV_CONFIG}" env.yml
	FINAL_ENV_CONFIG="env.yml"
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

zip -r ${ZIPFILE} Dockerrun.aws.json .ebextensions ${FINAL_ENV_CONFIG}
# zip -d ${ZIPFILE} __MACOSX/\*

if [ -e ~/Desktop/${ZIPFILE} ]; then
	rm ~/Desktop/${ZIPFILE}
fi

mv ${ZIPFILE} ~/Desktop
rm .ebextensions/*
rmdir .ebextensions

echo
echo "application bundle ${ZIPFILE} created and moved to the Desktop-- upload this to AWS."

