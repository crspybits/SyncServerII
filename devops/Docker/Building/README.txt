Need to modify build image because of: 
1) /root/SyncServerII/.build/checkouts/Perfect-LinuxBridge.git--87219909877364581/LinuxBridge/include/LinuxBridge.h:6:10: fatal error: 'uuid/uuid.h' file not found
I added: `uuid-dev`

2) /root/SyncServerII/.build/checkouts/Perfect-mysqlclient-Linux.git--5648820300544252669/module.modulemap:2:12: error: header '/usr/include/mysql/mysql.h' not found
    header "/usr/include/mysql/mysql.h"
I added: `libmysqlclient-dev`

3) TimeZone returns nil in my tests. See https://bugs.swift.org/browse/SR-4921
I added: `tzdata`

4) I'm also adding `jq` because my test case runner (see runTests.sh) uses it. Note that this does *not* need to be in the run time image.

Create the image based on the Dockerfile using:
docker build -t swift-ubuntu:latest .

docker tag swift-ubuntu:latest crspybits/swift-ubuntu:latest 
docker tag swift-ubuntu:latest crspybits/swift-ubuntu:4.0.2
docker push crspybits/swift-ubuntu:latest
docker push crspybits/swift-ubuntu:4.0.2

Also relying on https://github.com/hopsoft/relay/wiki/How-to-Deploy-Docker-apps-to-Elastic-Beanstalk

Run this with:
docker run -i -t -v /Users/chris/Dropbox/Ubuntu/SyncServerII/SyncServerII/:/root/SyncServerII crspybits/swift-ubuntu:4.0.0

To figure out the IP address of the docker host:
ip addr show eth0

See also
https://stackoverflow.com/questions/24319662/from-inside-of-a-docker-container-how-do-i-connect-to-the-localhost-of-the-mach

# To access mysql running on Docker host on MacOS for testing, use docker.for.mac.localhost for the mysql host.
See https://stackoverflow.com/questions/24319662/from-inside-of-a-docker-container-how-do-i-connect-to-the-localhost-of-the-mach?noredirect=1&lq=1

# 12/20/17-- I'm now going to see if I can build my Docker build image from https://github.com/swiftdocker/docker-swift in my Dockerfile so I can more easily stay up with changes in the Swift compiler. E.g., the change to 4.0.3
