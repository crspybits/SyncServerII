ONE-TIME INSTALL
================

* Install the eb cli
	http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-install-osx.html

PER SERVER ENVIRONMENT INSTALLS
===============================

Note that I'm not making a difference here between Elastic Beanstalk Applications and Environments. I'm just using a single environment within each of my applications.

* Configure the eb cli for an environment in a folder. I've put mine in subfolders of EBSEnvironments in the repo. See http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-configuration.html
I get rid of the .gitignore files in these directories. I  like to put them under version control.

* In your environment folder, add the following to the .elasticbeanstalk/config.yml file in that folder. It tells the eb cli where to find your application bundle, which the make.sh script is going to place on your desktop (I'm just dealing with MacOS for the time being).

deploy:
  artifact: <your-user-path>/Desktop/bundle.zip

See also http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-configuration.html#eb-cli3-artifact

* Create a Server.json file -- this provides the configuration needed by SyncServer. Put that in your environment folder. (I have just put a sym link because I don't want to expose private info in my repo!). Hold off on putting the database specifics into this file. That comes below.

* Create a SSL certificate for the domain or subdomain for your environment. For example, I'm using staging.syncserver.cprince.com for my staging server. It's free using the AWS Certificate Manager. As part of the creation process, AWS sends a confirmation email to several email addresses related to the domain or subdomain. E.g., you have to be the administrator on record with WHOIS for the domain or subdomain. See https://aws.amazon.com/certificate-manager/
You will need the `arn` reference for this SSL certificate in the configure.yml file below.

* Create a yml file for your environmnent (I'm calling them `configure.yml` files). There's an example in EBSEnvironments/sharedimages-staging/configure.yml. It's suitable to put these files in your environment folder because they are specific to the environment. These files contain many of the parameters needed for your environment. While much of it can just be copied and used for other environments, you will need to change the value of at least two parameters:
	a) SSLCertificateId -- which you generated with the AWS Certificate Manager above, and is tied to a particular URL, and 
	b) EC2KeyName -- which is the name of a security key pair to allow you SSH access into the EC2 instances. You need to create this using the AWS web console.
Also, if you want to change parameters such as the EC2 instance type used in the environment you'll need to make changes to this file. See the README.txt in the "AWS application bundle" folder for references on the details on the contents of the configure.yml file.

FOR ENVIRONMENT/DATABASE COMBO's THAT YOU REGULARLY START/SHUTDOWN, THIS IS THE PART YOU REPEAT:
================================================================================================

* Start a database for your environment. I've been using RDS mySQL. You'll need a specific database schema created, and a username and password to access that database. You will need to open up the security group for your database to allow access from the necessary ports (so far I've just been opening this up to the world-- and plan to figure out how to make this more restrictive using AWS VPC).

* Edit your Server.json file for the environment to contain the database particulars. You *must* do this before the next step (of zipping up your application bundle) because your Server.json file goes into the zipped application bundle.

* Zip up your AWS application bundle using the make.sh script within the "AWS application bundle". Your application bundle will contain your environment's Server.json and configure.yml files, and a few others. Do this at the command line within the "AWS application bundle" folder. The top comments of make.sh contain examples on how to run it. 
The make.sh script puts a few other files into the application bundle. One of these is a file named Dockerrun.aws.json. This file, amongst other things, configures the Docker image (for SyncServer) that will be used. In particular, it uses the docker image: https://hub.docker.com/r/crspybits/syncserver-runner/ which contains the most recent build of the SyncServer. That is, each time you start an environment, it pulls the current SyncServer image from hub.docker.com-- which will be updated from time to time.

To learn more about AWS application bundles, see http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/beanstalk-environment-configuration-advanced.html

* Start up your environment using the eb cli. Within one of your evironment folders, run, for example:
    eb create sharedimages-staging --cname sharedimages-staging
See also http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb3-create.html

You can control this Elastic Beanstalk environment at the AWS UI web console. Use https://aws.amazon.com/console/ and find Elastic Beanstalk.

* The configure.yml file specified an SSL certificate. Now, finally, you have to set up a DNS A record to direct the domain or subdomain referenced by that SSL certificate to the IP address for the load balancer for the server. The URL for your load balancer (from which you can get its IP address) will be something like: 	
	sharedimages-staging.us-west-2.elasticbeanstalk.com

* Hit on your server!