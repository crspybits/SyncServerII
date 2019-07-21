These folders are where you run the eb cli.

To initialize the folder, with the basic environment setup, do:
eb init

(also see Docs/LaunchingEnvironment.md)

Later, e.g., in the sharedimages-staging folder, you create (start) an environment with:
eb create sharedimages-staging --cname sharedimages-staging

---------------------------------------------------------

For the most recent version of the AWS Platform Version of AWS Linux to put in the .elasticbeanstalk/config.yml file, see:
https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html
