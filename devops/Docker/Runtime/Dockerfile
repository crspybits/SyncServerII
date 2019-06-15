# For Ubuntu 16.04, Swift 5.0.1 (IBM only has a `latest` at least as of 6/12/19)
FROM ibmcom/swift-ubuntu-xenial-runtime:latest
LABEL maintainer="Chris Prince <chris@SpasticMuffin.biz>"
LABEL Description="Runtime Docker Container for the Apple's Swift programming language"

# 6/15/19; I got a failure in running SyncServerII due to not finding libbsd; apparently this is present in the development build of Kitura/Ubuntu, but not in the runtime. Though I can't find it in the development build with `dpkg -l libbsd` or `dpkg -l libbsd-dev`. `apt-get install libbsd` doesn't find a package.

# Install additional packages
RUN apt-get -q update && \
	apt-get -q install -y \
		uuid-dev \
    	libmysqlclient-dev \
    	openssl \
    	libssl-dev \
    	pkg-config \
    	tzdata \
    	libbsd-dev \
    && rm -r /var/lib/apt/lists/*  

CMD /bin/bash