#!/bin/bash

user=
host=
dbname="SyncServer_SharedImages"

result=$(mysql -P 3306 -p --user="$user" --host="$host" --database="$dbname" < 5.sql 2>&1 )

if [ $? = 0 ]; then
    echo "Success running migration"
else
    echo "**** Failure running migration *******"
    echo $result
fi
