# For the available tags on swiftdocker/swift, see https://hub.docker.com/r/library/swift/tags/
# For the Docker files see https://hub.docker.com/r/_/swift/

# xenial is for Ubuntu 16.04; this pulls from the Docker Official Swift image
FROM swift:5.0.1-xenial
LABEL maintainer="Chris Prince <chris@SpasticMuffin.biz>"
LABEL Description="Docker image for building the Swift SyncServer server"

# Install additional packages
# 6/9/19; As of today, I get a warning and then a Swift build failure that I need openssl and libssl-dev; and I get a further Swift build failure on curl dependencies
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