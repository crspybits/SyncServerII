#!/bin/bash

# Purpose: Temporarily suspend an Elastic Beanstalk environment.

# Usage: suspend on | off
# 	on-- initiates suspending
#	off-- turns off suspending

# See:
# https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb3-scale.html
# https://stackoverflow.com/questions/32210389/pause-an-elastic-beanstalk-app-environment
# https://forums.aws.amazon.com/thread.jspa?threadID=121273

SUSPENDED=$1
NUMBER_INSTANCES=1

if [ "$SUSPENDED" == "on" ]; then
	echo "Suspending environment"
	eb scale 0
elif [ "$SUSPENDED" == "off" ]; then
	echo "Unsuspending environment"
	eb scale $NUMBER_INSTANCES
else
	echo "Bad args-- see docs for usage"
fi



