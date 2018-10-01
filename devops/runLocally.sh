#!/bin/bash

# Usage: runLocally.sh <Server.json>

# Once started, you can test with:
# 	http://localhost:8080/HealthCheck/

# E.g., runLocally.sh ~/Desktop/Apps/SyncServerII/Private/Server/SharedImages-local.json
SERVER_JSON=$1
RUN_DIR=/Users/chris/Desktop/Apps/SyncServer.Run
IMAGE=syncserver-runner

# Copy Server.json file into the directory where the server's going to look for it
cp "${SERVER_JSON}" "${RUN_DIR}"/Server.json

docker run -p 8080:8080 --rm -i -t -v "${RUN_DIR}"/:/root/extras crspybits/syncserver-runner:latest