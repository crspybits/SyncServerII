# `swift:5.2.3-xenial` below references https://github.com/apple/swift-docker/blob/38f179345ace24236d6c09de84e77d91384014cd/5.2/ubuntu/16.04/Dockerfile
# More generally, these Dockerfile's are listed at https://hub.docker.com/_/swift

# This is for Ubuntu 16.04 (xenial), the latest build of Swift 5.3
# See https://hub.docker.com/r/swiftlang/swift/tags
# FROM swiftlang/swift:nightly-5.3-xenial

# Note that I'm not using Ubuntu 14.04 because I'm currently using Perfect for mySQL interface
# and that has problems with the mysqlclient for 14.04. See https://github.com/PerfectlySoft/Perfect-MySQL

# This is for Ubuntu 16.04 (xenial), the prod build of Swift 5.3.1
FROM swift:5.3.1-xenial
LABEL maintainer="Chris Prince <chris@SpasticMuffin.biz>"
LABEL Description="Docker image for building the Swift SyncServer server"

# pkg-config below is trying to avoid:
# 	warning: failed to retrieve search paths with pkg-config; maybe pkg-config is not installed
# Without tzdata, the TimeZone Swift method fails, at least sometimes.

# As of 5/30/20, the base swift Dockerfile now has pkg-config, so removing that from mine. Similarly it also has tzdata, so removing that.

# 5/30/20, Getting build failures missing CCurl, so adding: libcurl4-openssl-dev, which was in the IBM Dockerfile.

# Install additional packages
RUN apt-get -q update && \
	apt-get -q install -y \
		uuid-dev \
    	libmysqlclient-dev \
    	jq \
    	openssl \
    	libssl-dev \
    	libcurl4-openssl-dev \
    && rm -r /var/lib/apt/lists/*  

# Print Installed Swift Version
RUN swift --version
