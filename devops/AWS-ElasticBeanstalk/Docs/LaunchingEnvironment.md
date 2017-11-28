ASSUMPTIONS
===========

* I assume you're running MacOS. :).

ONE-TIME INSTALL
================

* Install the eb cli
	http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-install-osx.html

* To use the `make.sh` script (see below; it zips up your application bundle), you'll need the `jq` program installed. The make.sh script below contains, inside it, instructions on how to do this.

PER SERVER ENVIRONMENT INSTALLS
===============================

  Note that I'm not making a big difference here between Elastic Beanstalk Applications and Environments becaise I'm just using a single environment within each of my applications.

* Configure the eb cli for an environment in a folder. I've put mine in subfolders of EBSEnvironments in the repo. See http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-configuration.html
I get rid of the .gitignore files in these directories. I like to put them under version control.

* In your environment folder, add the following to the .elasticbeanstalk/config.yml file in that folder. It tells the eb cli where to find your application bundle, which the make.sh script is going to place on your desktop.

```
deploy:
  artifact: <your-user-path>/Desktop/bundle.zip
```

  See also http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-configuration.html#eb-cli3-artifact

* Create a Server.json file -- this provides the configuration needed by SyncServer. Put that in your environment folder. (I have just put a sym link because I don't want to expose private info in my repo!). Hold off on putting the database specifics into this file. That comes below.

* Create a SSL certificate for the domain or subdomain for your environment. For example, I'm using staging.syncserver.cprince.com for my staging server. It's free using the AWS Certificate Manager. As part of the creation process, AWS sends a confirmation email to several email addresses related to the domain or subdomain. E.g., you have to be the administrator on record with WHOIS for the domain or subdomain. See https://aws.amazon.com/certificate-manager/

  You will need the `arn` reference for this SSL certificate in the configure.yml file below.
  
* If you want your database secured not only by password and username, but also secured behind an AWS Virtual Private Cloud (VPC), then [also follow these steps](LaunchingEnvironment-VPC.md).

* Create a yml file for your environmnent (I'm calling them `configure.yml` files). There's an example in EBSEnvironments/sharedimages-staging/configure.yml. It's suitable to put these files in your environment folder because they are specific to the environment. These files contain many of the parameters needed for your environment. While much of it can just be copied and used for other environments, you will need to change the value of at least two parameters:

1. `SSLCertificateId` -- which you generated with the AWS Certificate Manager above, and is tied to a particular URL. 

2. `EC2KeyName` -- which is the name of a security key pair to allow you SSH access into the EC2 instances. You need to create this using the AWS web console.

3. VPC related parameters-- If you have setup a VPC, then see [the VPC instructions](LaunchingEnvironment-VPC.md) for additional changes you'll need to make to configure.yml.
    
  Also, if you want to change parameters such as the EC2 instance type used in the environment you'll need to make changes to this file. See the README.txt in the "AWS application bundle" folder for references on the details on the contents of the configure.yml file.

FOR ENVIRONMENT/DATABASE COMBO's THAT YOU REGULARLY START/SHUTDOWN, THIS IS THE PART YOU REPEAT:
================================================================================================

* Start a database for your environment. I've been using RDS mySQL. You'll need a specific database schema created, and a username and password to access that database. If you are using a VPC to connect to your database, select "No" for "Public accessibility" and [see these instructions](LaunchingEnvironment-VPC.md) for other changes you'll need when creating your database. If you are not using a VPC, then select "Yes" for "Public accessibility", and you'll also need to change the database security group to allow ingress from any IP address.

* Edit your Server.json file for the environment to contain the database particulars, i.e., endpoint, username, password, database name. You *must* do this before the next step (of zipping up your application bundle) because your Server.json file goes into the zipped application bundle.

* Zip up your AWS application bundle using the make.sh script within the "AWS application bundle". Do this at the command line within the "AWS application bundle" folder. The top comments of make.sh contain examples on how to run it, but the basics are that you give three command line arguments:

  ./make.sh `<DockerImageTag>` Server.json configure.yml

  As a result of running make.sh, your application bundle will contain your environment's Server.json and configure.yml files, and a few others. One of these is a file named Dockerrun.aws.json. This file, amongst other things, indicates the Docker image for SyncServer that will be used. In particular, it uses the docker image: https://hub.docker.com/r/crspybits/syncserver-runner/ with the tag `<DockerImageTag>` (that you gave to make.sh). That is, the application bundle indicates which SyncServer image to pull from hub.docker.com.

  To learn more about AWS application bundles, see http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/beanstalk-environment-configuration-advanced.html

* Start up your environment using the eb cli. Within one of your evironment folders, run, for example:

```
eb create sharedimages-staging --cname sharedimages-staging
```

  See also http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb3-create.html

  You can control this Elastic Beanstalk environment at the AWS UI web console. Use https://aws.amazon.com/console/ and find Elastic Beanstalk.

* The configure.yml file specified an SSL certificate. Now, finally, you have to set up a DNS CNAME record to direct the domain or subdomain referenced by that SSL certificate to the CNAME address for the load balancer for the server. The URL for your load balancer will be something like:

```
sharedimages-staging.us-west-2.elasticbeanstalk.com
```

NOTE: The configuration I'm using is for a Classical Elastic Beanstalk load balancer (not a Network Load Balancer) and so its CNAME doesn't have a static IP address. Hence, you can't use redirection with a DNS A record (I learned this the hard way!). See also:
https://forums.aws.amazon.com/thread.jspa?threadID=9061
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environments-cfg-nlb.html
http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-loadbalancer.html
https://stackoverflow.com/questions/9935229/cname-ssl-certificates

* Hit on your server!
