#!/bin/bash

script -q /dev/null awslogs --query=message get /aws/elasticbeanstalk/sharedimages-production/home/ec2-user/output.log ALL --watch | cut -d " " -f 3- 

