#!/bin/bash

# Usage: buildlatest.sh
# For local server testing. Assumes that you have built a binary. Builds the docker image for that binary. Doesn't push to docker hub.

# docker hub username
USERNAME=crspybits
# image name
IMAGE=syncserver-runner

# build the runtime image
docker build -t $USERNAME/$IMAGE:latest .

