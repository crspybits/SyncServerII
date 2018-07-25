#!/bin/bash

user=
password=
host=
dbname=

result=$(mysql --user="$user" --password="$password" --host="$host" --database="$dbname" < 5.sql 2>&1 )

if [ $? = 0 ]; then
    echo "Success running migration"
else
    echo "**** Failure running migration *******"
    echo $result
fi
