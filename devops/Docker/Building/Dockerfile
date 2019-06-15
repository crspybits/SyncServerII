# See https://github.com/IBM-Swift/swift-ubuntu-docker

# Note that I'm not using Ubuntu 14.04 because I'm currently using Perfect for mySQL interface
# and that has problems with the mysqlclient for 14.04. See https://github.com/PerfectlySoft/Perfect-MySQL

# This is for Ubuntu 16.04; It's for Swift 5.0.1 as of 6/12/19, there just is only a `latest` tag.
FROM ibmcom/swift-ubuntu-xenial:latest
LABEL maintainer="Chris Prince <chris@SpasticMuffin.biz>"
LABEL Description="Docker image for building the Swift SyncServer server"

# pkg-config below is trying to avoid:
# 	warning: failed to retrieve search paths with pkg-config; maybe pkg-config is not installed
# Without tzdata, the TimeZone Swift method fails, at least sometimes.

# Install additional packages
RUN apt-get -q update && \
	apt-get -q install -y \
		uuid-dev \
    	libmysqlclient-dev \
    	jq \
    	openssl \
    	libssl-dev \
    	pkg-config \
    	tzdata \
    && rm -r /var/lib/apt/lists/*  

# Print Installed Swift Version
RUN swift --version
