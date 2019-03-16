#!/bin/bash

# Usage:
#   logTail.sh <EnvironmentName>
# E.g.,
#   logTail.sh neebla-production
#   logTail.sh sharedimages-production
#   logTail.sh sharedimages-staging

ENVIRONMENT=$1

if [ "empty${ENVIRONMENT}" == "empty" ]; then
    echo "**** Please give an environment name."
    exit
fi

script -q /dev/null awslogs --query=message get /aws/elasticbeanstalk/${ENVIRONMENT}/home/ec2-user/output.log ALL --watch | cut -d " " -f 3- 

