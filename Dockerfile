# Builds a Docker image for running SyncServer.

FROM crspybits/swift-ubuntu-runtime:latest
MAINTAINER Spastic Muffin, LLC
LABEL Description="Docker image for running SyncServer."

USER root

# This depends on the Server.json file using port 8080 for SyncServer.
EXPOSE 8080

# The git tag of the deployed SyncServer -- this is for documentation, *and* is read when the server launches-- the server reports this back in healthchecks.
ADD VERSION .

# Binaries should have been compiled against the correct platform (i.e. Ubuntu 16.04).
COPY .build.linux/debug/Main /root/SyncServerII/.build/debug/Main

# This depends on the Server.json file being copied into a directory that's mounted at /root/extras
# For now, I'm also writing the server log to /root/extras. Later it would be nice to make it available over the web instead of having to sign-in to the server.

# `stdbuf` gets rid of buffering to make it easier to tail the log; see also https://serverfault.com/questions/294218/is-there-a-way-to-redirect-output-to-a-file-without-buffering-on-unix-linux

# CMD [ "sh", "-c", "cd /root/SyncServerII && ( stdbuf -o0 .build/debug/Main /root/extras/Server.json > /root/extras/output.log 2>&1 & )" ]

CMD stdbuf -o0 /root/SyncServerII/.build/debug/Main /root/extras/Server.json > /root/extras/output.log 2>&1
