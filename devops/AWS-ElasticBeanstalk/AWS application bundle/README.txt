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




