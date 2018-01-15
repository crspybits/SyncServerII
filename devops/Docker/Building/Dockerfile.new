# For the available tags on swiftdocker/swift, see https://hub.docker.com/r/library/swift/tags/
FROM swiftdocker/swift:latest
LABEL maintainer="Chris Prince <chris@SpasticMuffin.biz>"
LABEL Description="Docker image for building the Swift SyncServer server"

# Install additional packages
RUN apt-get -q update && \
	apt-get -q install -y \
		uuid-dev \
    	libmysqlclient-dev \
    	jq \
    && rm -r /var/lib/apt/lists/*  

# Print Installed Swift Version
RUN swift --version