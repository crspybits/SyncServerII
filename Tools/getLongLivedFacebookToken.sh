#!/bin/bash

# Usage:
# 	arg1: the name of the .json configuration file for the server
# 	arg2: the name of the Facebook token in that file, e.g., FacebookLongLivedToken1
#

# Using https://stackoverflow.com/questions/10467272/get-long-live-access-token-from-facebook to extend the life of a Facebook access token

CONFIG_FILE=$1
FACEBOOK_TOKEN=$2

getToken () {
    # Parameters to this method:
    local tokenKey=$1
    
	local FB_CLIENT_ID=`jq -r .FacebookClientId < "$CONFIG_FILE"`
	local FB_CLIENT_SECRET=`jq -r .FacebookClientSecret < "$CONFIG_FILE"`
	
	local ACCESS_TOKEN=`jq -r .${tokenKey} < "$CONFIG_FILE"`

	local RESULT=`curl --silent  "https://graph.facebook.com/oauth/access_token?client_id=${FB_CLIENT_ID}&client_secret=${FB_CLIENT_SECRET}&grant_type=fb_exchange_token&fb_exchange_token=${ACCESS_TOKEN}"`

	echo "Long lived token for: ${tokenKey}:"
	echo $RESULT | jq -r .access_token
}

getToken ${FACEBOOK_TOKEN}
