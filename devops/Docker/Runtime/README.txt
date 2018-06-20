# Make the server runtime-image Dockerfile, e.g., see https://developer.ibm.com/swift/2017/02/14/new-runtime-docker-image-for-swift-applications/#comment-2962

# Create a runtime image using the new Dockerfile by executing the following command in the folder of the SyncServerII repo, where the Dockerfile is located.

docker build -t syncserver-runner:latest .

# Push that image to Docker hub-- Currently I'm using a public Docker hub repo-- so am *not* exposing anything private in that image.

docker login

# Before the first push, it looks like you have to do:
docker tag syncserver-runner:latest crspybits/syncserver-runner:latest
# see https://stackoverflow.com/questions/41984399/denied-requested-access-to-the-resource-is-denied-docker

docker tag syncserver-runner:latest crspybits/syncserver-runner:latest
docker tag syncserver-runner:latest crspybits/syncserver-runner:4.1.2
docker push crspybits/syncserver-runner:latest
docker push crspybits/syncserver-runner:4.1.2

# Run a container

# Assumes AWS Elastic Beanstalk configuration files (.ebextensions) have been used to copy Server.json into the directory: /home/ubuntu on the ec2 instance

docker run -p 8080:8080 --rm -i -t -v /Users/chris/Desktop/Apps/:/root/Apps crspybits/syncserver-runner:latest

Get into the running container:
docker exec -it <mycontainer> bash
<mycontainer> is the container id.

Show stopped containers:
docker ps --filter "status=exited"
docker ps -a
(these don't show up with docker ps).
