#!/bin/bash

user=""
host=""

# user="root"
# host="localhost"

dbname="SyncServer_SharedImages"
sqlScript="7.sql"

echo "Migrating $dbname on $host"

result=$(mysql -P 3306 -p --user="$user" --host="$host" --database="$dbname" < "$sqlScript" 2>&1 )

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

