# Make the server runtime-image Dockerfile, e.g., see https://developer.ibm.com/swift/2017/02/14/new-runtime-docker-image-for-swift-applications/#comment-2962

# Create a runtime image using the new Dockerfile by executing the following command in SyncServerII/devops/Docker/Runtime folder:

docker build -t swift-ubuntu-runtime:latest .

# Push that image to Docker hub-- Currently I'm using a public Docker hub repo-- so am *not* exposing anything private in that image.

docker login

# Tag the image
# See also https://stackoverflow.com/questions/41984399/denied-requested-access-to-the-resource-is-denied-docker

docker tag swift-ubuntu-runtime:latest crspybits/swift-ubuntu-runtime:latest
docker tag swift-ubuntu-runtime:latest crspybits/swift-ubuntu-runtime:5.2.3
docker push crspybits/swift-ubuntu-runtime:latest
docker push crspybits/swift-ubuntu-runtime:5.2.3

Run this with:
docker run -p 8080:8080 --rm -i -t -v /Users/chris/Desktop/Apps/:/root/extras crspybits/swift-ubuntu-runtime:latest

# Run a container

# Assumes AWS Elastic Beanstalk configuration files (.ebextensions) have been used to copy Server.json into the directory: /home/ubuntu on the ec2 instance

Get into the running container:
docker exec -it <mycontainer> bash
<mycontainer> is the container id.

Show stopped containers:
docker ps --filter "status=exited"
docker ps -a
(these don't show up with docker ps).
