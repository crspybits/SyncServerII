#!/bin/bash

# Usage: release.sh <ReleaseTag>
# 	<ReleaseTag> is the tag to apply to git, and to use as a tag for Docker Hub.
# Run this from the root of the repo. i.e., ./devops/release.sh
# after you have built the SyncServer server binary.
# Example: 
#	./devops/release.sh 0.7.7

# Note that you can also use this to "release" testing versions. For example, if you do:
#	./devops/release.sh release-candidate-0.8.0

# This script adapted from https://medium.com/travis-on-docker/how-to-version-your-docker-images-1d5c577ebf54

RELEASE_TAG=$1

if [ "empty${RELEASE_TAG}" == "empty" ]; then
        echo "**** Please give a release tag."
        exit
fi

# docker hub username
USERNAME=crspybits
# image name
IMAGE=syncserver-runner

# ensure we're up to date
git pull

# bump version

echo $RELEASE_TAG > VERSION
echo "version: $RELEASE_TAG"

# build the runtime image
docker build -t $USERNAME/$IMAGE:latest .

# tag it
git add -A
git commit -m "version $RELEASE_TAG"
git tag -a "$RELEASE_TAG" -m "version $RELEASE_TAG"
git push
git push --tags
docker tag $USERNAME/$IMAGE:latest $USERNAME/$IMAGE:$RELEASE_TAG

# push it
docker push $USERNAME/$IMAGE:latest
docker push $USERNAME/$IMAGE:$RELEASE_TAG