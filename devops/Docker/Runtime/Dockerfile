# `swift:5.2.3-xenial-slim` below references https://github.com/apple/swift-docker/blob/38f179345ace24236d6c09de84e77d91384014cd/5.2/ubuntu/16.04/slim/Dockerfile
# More generally, these Dockerfile's are listed at https://hub.docker.com/_/swift

# For Ubuntu 16.04, Swift 5.3.1 beta
# https://hub.docker.com/r/swiftlang/swift/tags
# FROM swift:nightly-master-xenial-slim

FROM swift:5.3.1-xenial-slim
LABEL maintainer="Chris Prince <chris@SpasticMuffin.biz>"
LABEL Description="Runtime Docker Container for the Apple's Swift programming language"

# 6/15/19; I got a failure in running SyncServerII due to not finding libbsd; apparently this is present in the development build of Kitura/Ubuntu, but not in the runtime. Though I can't find it in the development build with `dpkg -l libbsd` or `dpkg -l libbsd-dev`. `apt-get install libbsd` doesn't find a package.

# As of 5/30/20. Now using Apple base image. This Apple base swift Dockerfile now has tzdata, so removing that.

# 5/30/20, Getting build failures missing CCurl, so adding: libcurl4-openssl-dev, which was in the IBM Dockerfile.

# Install additional packages
RUN apt-get -q update && \
	apt-get -q install -y \
		uuid-dev \
    	libmysqlclient-dev \
    	openssl \
    	libssl-dev \
    	libbsd-dev \
    	pkg-config \
    	libcurl4-openssl-dev \
    && rm -r /var/lib/apt/lists/*  

CMD /bin/bash