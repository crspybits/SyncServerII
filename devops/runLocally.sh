#!/bin/bash

# Usage: runLocally.sh <Server.json> [latest | <ServerRelease>]
# This runs a docker image.

# Once started, you can test with:
# 	http://localhost:8080/HealthCheck/

# E.g., runLocally.sh ~/Desktop/Apps/SyncServerII/Private/Server/SharedImages-local.json 0.19.1
# E.g., runLocally.sh ~/Desktop/Apps/SyncServerII/Private/Server/ClientTesting-local.json latest
SERVER_JSON=$1
SERVER_RELEASE=$2

if [ "empty$SERVER_RELEASE" != "empty" ]; then
	SERVER_RELEASE=":${SERVER_RELEASE}"
fi

RUN_DIR=/Users/chris/Desktop/Apps/SyncServer.Run
IMAGE=syncserver-runner

# Copy Server.json file into the directory where the server's going to look for it
cp "${SERVER_JSON}" "${RUN_DIR}"/Server.json

docker run -p 8080:8080 --rm -i -t -v "${RUN_DIR}"/:/root/extras crspybits/"${IMAGE}${SERVER_RELEASE}"
