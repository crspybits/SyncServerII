#!/bin/bash

# The following does a "tail" on the CloudWatch log for staging.
# script -q /dev/null # This unbuffers the output
# cut -d " " -f 3- # This removes the first two fields of the output. Just fluff.
script -q /dev/null awslogs --query=message get /aws/elasticbeanstalk/sharedimages-staging/home/ec2-user/output.log ALL --watch | cut -d " " -f 3- 
