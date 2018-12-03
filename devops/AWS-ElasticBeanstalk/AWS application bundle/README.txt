1) Dockerrun.aws.json
	"AWSEBDockerrunVersion": "1",
		The value `1` indicates single container Docker environment.
		This is the right value since my server is using just a single container.
	
2) Elastic Beanstalk and NGINX:
https://medium.com/trisfera/getting-to-know-and-love-aws-elastic-beanstalk-configuration-files-ebextensions-9a4502a26e3c

3) I haven't been able to get this to work. Seems specific to Java apps.
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/java-se-nginx.html

4) For the pgrep command I have in the 2nd .config file, see
https://stackoverflow.com/questions/18908426/increasing-client-max-body-size-in-nginx-conf-on-aws-elastic-beanstalk?rq=1

5) At first I thought that the environment manifest file they talk about here
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-cfg-manifest.html
could be used to specify all of the environment options. After much struggling, that doesn't seem so. Instead, I've moved on to specifying these options in a .config file in the .ebextensions folder.
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-configuration-methods-during.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/ebextensions-optionsettings.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/command-options-general.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-configuration-methods-before.html

See also:
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environments-cfg-applicationloadbalancer.html

I did use the Elastic Beanstalk configuration files, saved from particular environments, as a starting point for these.

5) I struggled quite a bit trying to figure out how to put most of the parameters needed to launch an environment from the EB web UI into a .config file. However, that doesn't seem fully possible. See https://devops.stackexchange.com/questions/2598/elastic-beanstalk-setting-parameters-from-a-config-file-in-the-application-bun

6) I've finally boiled down the .config file (I'm calling it configure.yml) contents to two parts that work when using the eb cli. One part is a `Resources` section and the other part is a `option_settings` section. It seems the Resources section is needed with the eb cli, otherwise, the load balancer doesn't get configured properly.
https://aws.amazon.com/blogs/devops/three-easy-steps-to-enable-cross-zone-load-balancing-in-elastic-beanstalk/
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/customize-containers-format-resources-eb.html
http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environment-resources.html
http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-elb.html

7) Setting up CloudWatch logs

See
https://stackoverflow.com/questions/34018931/how-to-view-aws-log-real-time-like-tail-f
https://github.com/jorgebastida/awslogs

Seems like the final secret sauce in all this was:
"Before you can configure integration with CloudWatch Logs using configuration files, you must set up IAM permissions to use with the CloudWatch Logs agent. You can attach the following custom policy to the instance profile that you assign to your environment." (https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/AWSHowTo.cloudwatchlogs.html#AWSHowTo.cloudwatchlogs.streaming). I attached that custom policy to the IAM aws-elasticbeanstalk-ec2-role.

"When you launch an environment in the AWS Elastic Beanstalk environment management console, the console creates a default instance profile, called aws-elasticbeanstalk-ec2-role, and assigns managed policies with default permissions to it." (https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/iam-instanceprofile.html)

It also looks like the prefix "/etc/awslogs/config/" in the .config file is necessary. I restarted the staging environment with the above custom policy change in place, and that didn't do the job. But with that policy change *and* the prefix "/etc/awslogs/config/" in the .config file, I *am* now seeing the log in CloudWatch.

awslogs groups

# The following does a "tail" on the CloudWatch log for staging.
# script -q /dev/null # This unbuffers the output
# cut -d " " -f 3- # This removes the first two fields of the output. Just fluff.
script -q /dev/null awslogs --query=message get /aws/elasticbeanstalk/sharedimages-staging/home/ec2-user/output.log ALL --watch | cut -d " " -f 3- 

# The following does a "tail" on the CloudWatch log for production.
script -q /dev/null awslogs --query=message get /aws/elasticbeanstalk/sharedimages-production/home/ec2-user/output.log ALL --watch | cut -d " " -f 3- 


