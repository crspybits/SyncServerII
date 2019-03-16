#!/bin/bash

# Purpose: Creates an application bundle for upload to the AWS Elastic Beanstalk, for running SyncServer
# Usage: ./make.sh <DockerImageTag> <file>.json [<environment-variables>.yml]
# :<DockerImageTag> is appended to the image name given in Dockerrun.aws.json (see the raw.materials folder)
# The .json file will be used as the Server.json file to start the server.
# The environment variables are a little tricky. See the README.txt in this folder.
# WARNING: I believe AWS doesn't do well with Server.json files that have blank lines in the technique I'm using to transfer the file to the Docker container.
# Assumes:
#	That this script is run from the directory the script is located in.
#	That the `jq` command line program is installed (e.g., brew install jq); see also https://stackoverflow.com/questions/24942875/change-json-file-by-bash-script

# Examples: 

# Neebla production server
# ./make.sh 0.21.2 ../Environments/neebla-production/Server.json ../Environments/neebla-production/configure.yml

# SharedImages production server
# ./make.sh 0.7.7 ../Environments/sharedimages-production/Server.json ../Environments/sharedimages-production/configure.yml

# SharedImages staging server
# ./make.sh 0.7.6 ../Environments/sharedimages-staging/Server.json ../Environments/sharedimages-staging/configure.yml

# iOS Client testing server
# ./make.sh 0.14.0 ../Environments/syncserver-testing/Server.json ../Environments/syncserver-testing/configure.yml

DOCKER_IMAGE_TAG=$1
SERVER_JSON=$2
ENV_VAR_PARAM=$3
ZIPFILE=bundle.zip
ENV_VARIABLES="env.variables.config"

# 6 Extra blanks because config file needs these prepended before json file lines for YAML formatting.
EXTRA_BLANKS="      "

# Check if jq is installed.
if [ "empty`command -v jq`" == "empty" ]; then
	echo "**** The jq command needs to be installed. See docs in this script."
	exit
fi

if [ ! -d .ebextensions ]; then
	mkdir .ebextensions
fi

if [ ! -d tmp ]; then
	mkdir tmp
fi

if [ "empty${DOCKER_IMAGE_TAG}" == "empty" ]; then
	echo "**** You need to give the Docker image tag as a parameter!"
	exit
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
	
	# Make sure the environment variables file is named with a .config extension.
	cp "${ENV_VAR_PARAM}" "$ENV_VARIABLES"
	mv -f "$ENV_VARIABLES" .ebextensions
fi

echo "Using:"
echo -e "\tDocker image tag\n\t\t${DOCKER_IMAGE_TAG}"
echo -e "\tEnvironment variables file\n\t\t${ENV_VAR_PARAM}"
echo -e "\tServer json file\n\t\t${SERVER_JSON}"
echo

cp -f raw.materials/Server.json.config tmp

# There's some trickyness to avoid removing white space and avoid removing the last line if it doesn't end with a newline. See https://stackoverflow.com/questions/10929453/
while IFS='' read -r line || [[ -n "$line" ]]; do
	echo "${EXTRA_BLANKS}$line" >> tmp/Server.json.config
done < "${SERVER_JSON}"

mv -f tmp/Server.json.config .ebextensions
cp -f raw.materials/SyncServer.ngnix.config .ebextensions
cp -f raw.materials/SyncServer.logging.config .ebextensions

if [ -e ${ZIPFILE} ]; then
	echo "Removing old ${ZIPFILE}"
  	rm ${ZIPFILE}
fi

# Modify the Docker image name in Dockerrun.aws.json with the tag given.
DOCKER_IMAGE=`jq -r '.Image.Name' raw.materials/Dockerrun.aws.json`
JQ_CMD=".Image.Name = \"${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}\""
jq "${JQ_CMD}" raw.materials/Dockerrun.aws.json > Dockerrun.aws.json

zip -r ${ZIPFILE} Dockerrun.aws.json .ebextensions
# zip -d ${ZIPFILE} __MACOSX/\*

if [ -e ~/Desktop/${ZIPFILE} ]; then
	rm ~/Desktop/${ZIPFILE}
fi

mv ${ZIPFILE} ~/Desktop
rm .ebextensions/*
rmdir .ebextensions
rmdir tmp
rm Dockerrun.aws.json

echo
echo "application bundle ${ZIPFILE} created and moved to the Desktop-- upload this to AWS."
