Need to modify build image because of: 
1) /root/SyncServerII/.build/checkouts/Perfect-LinuxBridge.git--87219909877364581/LinuxBridge/include/LinuxBridge.h:6:10: fatal error: 'uuid/uuid.h' file not found
I added: `uuid-dev`

2) /root/SyncServerII/.build/checkouts/Perfect-mysqlclient-Linux.git--5648820300544252669/module.modulemap:2:12: error: header '/usr/include/mysql/mysql.h' not found
    header "/usr/include/mysql/mysql.h"
I added: `libmysqlclient-dev`

3) TimeZone returns nil in my tests. See https://bugs.swift.org/browse/SR-4921
I added: `tzdata`
(NOTE-- as of 6/17/18-- this is now in the Swift Docker image

4) I'm also adding `jq` because my test case runner (see runTests.sh) uses it. Note that this does *not* need to be in the run time image.

5) 5/30/20-- I've moved to basing my Dockerfile on Apple's, and I'm now getting failures when building related to CCurl. E.g., /root/Apps/ServerMain/.build/checkouts/Kitura-net/Sources/KituraNet/ClientRequest.swift:18:8: error: could not build C module 'CCurl'
Is CCurl not in Apple's Swift Dockerfile? libcurl3 is in the Apple Swift Dockerfile.
I see that IBM's Ubuntu 16.04 Dockerfile (https://github.com/IBM-Swift/swift-ubuntu-docker/blob/master/swift-development/swift-ubuntu-xenial-multiarch/amd64/Dockerfile) had libcurl4-openssl-dev. I'm going to try adding that. Looks like that solved the problem!

Create the image based on the Dockerfile using (do this from a Terminal window opened within the devops/Docker/Building folder):
docker build -t swift-ubuntu:latest .

docker tag swift-ubuntu:latest crspybits/swift-ubuntu:latest 
docker tag swift-ubuntu:latest crspybits/swift-ubuntu:5.2.3
docker push crspybits/swift-ubuntu:latest
docker push crspybits/swift-ubuntu:5.2.3

Also relying on https://github.com/hopsoft/relay/wiki/How-to-Deploy-Docker-apps-to-Elastic-Beanstalk

Run this with:
docker run --rm -i -t -v /Users/chris/Desktop/Apps/:/root/Apps crspybits/swift-ubuntu:5.2.3

To figure out the IP address of the docker host:
ip addr show eth0

See also
https://stackoverflow.com/questions/24319662/from-inside-of-a-docker-container-how-do-i-connect-to-the-localhost-of-the-mach

# To access mysql running on Docker host on MacOS for testing, use docker.for.mac.localhost for the mysql host.
See https://stackoverflow.com/questions/24319662/from-inside-of-a-docker-container-how-do-i-connect-to-the-localhost-of-the-mach?noredirect=1&lq=1

6/10/19
I tried to get Ubuntu 18.04 working with Swift 5 and my server, but ran into a problem. I was getting the error "Parsed fewer bytes than were passed to the HTTP parser" during request parsing. See also https://github.com/IBM-Swift/Kitura/issues/1146
I have gone back to 16.04 and the server is working again. I wonder if this is at least part of the reason why IBM doesn't overtly support 18.04 in their released Docker images.
See also https://github.com/IBM-Swift/Kitura-net/issues/312