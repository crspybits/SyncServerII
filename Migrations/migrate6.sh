#!/bin/bash

user=""
host=""
dbname="SyncServer_SharedImages"
sqlScript="6.sql"

result=$(mysql -P 3306 -p --user="$user" --host="$host" --database="$dbname" < "$sqlScript" 2>&1 )

# I've embedded "ERROR999" to be output from the sql script -- when an error and subsequent rollback occurs.

ERROR=`echo $result | grep ERROR999`
if [ "empty$ERROR" = "empty" ]; then
    echo "Success running migration"
else
    echo "**** Failure running migration *******"
    echo $result
fi

