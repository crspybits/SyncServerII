#!/bin/bash

# Usage:
# 	arg1: the name of the .json configuration file for the server
#	arg2: The name of the sql script.
#	arg3: (optional) host-- replaces the host from the configuratin file.
# e.g., ./Migrations/migrate8.sh ~/Desktop/Apps/SyncServerII/Private/Server/SharedImages-local.json Migrations/8.sql localhost

CONFIG_FILE=$1
SQL_SCRIPT=$2
CMD_LINE_HOST=$3

DBNAME=`jq -r '.["mySQL.database"]' < ${CONFIG_FILE}`
USER=`jq -r '.["mySQL.user"]' < ${CONFIG_FILE}`
PASSWORD=`jq -r '.["mySQL.password"]' < ${CONFIG_FILE}`
HOST=`jq -r '.["mySQL.host"]' < ${CONFIG_FILE}`

if [ "empty$CMD_LINE_HOST" != "empty" ]; then
	HOST=$CMD_LINE_HOST
fi

echo "Migrating $DBNAME on $HOST"

result=$(mysql -P 3306 -p --user="$USER" --password="$PASSWORD" --host="$HOST" --database="$DBNAME" < "$SQL_SCRIPT" 2>&1 )

# I've embedded "ERROR999" to be output from the sql script -- when an error and subsequent rollback occurs.

ERROR=`echo $result | grep ERROR999`
if [ "empty$ERROR" = "empty" ]; then
	SUCCESS=`echo $result | grep SUCCESS123`
	
	# Didn't have ERROR string-- presumably no error.
	
	if [ "empty$SUCCESS" = "empty" ]; then
		# Didn't find SUCCESS string-- must have error.
		
		echo "**** Failure running migration, despite no error marker *******"
		echo $result
	else
		echo "Success running migration"
	fi
else
    echo "**** Failure running migration (with error marker) *******"
    echo $result
fi

