"AWSEBDockerrunVersion": "1",
	The value `1` indicates single container Docker environment.
	This is the right value since my server is using just a single container.
	
Elastic Beanstalk and NGINX:
https://medium.com/trisfera/getting-to-know-and-love-aws-elastic-beanstalk-configuration-files-ebextensions-9a4502a26e3c

# I haven't been able to get this to work. Seems specific to Java apps.
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/java-se-nginx.html

# for the pgrep command I have in the 2nd .config file, see
https://stackoverflow.com/questions/18908426/increasing-client-max-body-size-in-nginx-conf-on-aws-elastic-beanstalk?rq=1

# The example.manifests folder contains example Elastic Beanstalk environment configuration files. They are specific to particular AWS accounts. You can either a) create these files manually, or b) save them from an Elastic Beanstalk environment (I used option b)). See:
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-install-osx.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3-configuration.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-configuration-savedconfig.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-cfg-manifest.html