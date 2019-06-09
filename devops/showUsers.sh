#!/bin/bash

# Usage: showUsers.sh <Server.json>

# e.g., ./devops/showUsers.sh ~/Desktop/Apps/SyncServerII/Private/Server.json.aws.app.bundles/Neebla-production.json

MY_SQL_JSON=$1
DATABASE=`jq -r '.["mySQL.database"]' < ${MY_SQL_JSON}`
USER=`jq -r '.["mySQL.user"]' < ${MY_SQL_JSON}`
PASSWORD=`jq -r '.["mySQL.password"]' < ${MY_SQL_JSON}`
HOST=`jq -r '.["mySQL.host"]' < ${MY_SQL_JSON}`

SCRIPT="select username, accountType from User;"

# --json option on mysql not working on version of mysql I have installed with macOS: 
# mysql  Ver 14.14 Distrib 5.7.23, for osx10.14 (x86_64) using  EditLine wrapper
# and the mySQL version I'm using on AWS RDS doesn't support it either:
# https://stackoverflow.com/questions/41758870/how-to-convert-result-table-to-json-array-in-mysql
# I get:
# ERROR 1305 (42000) at line 1: FUNCTION SyncServer_SharedImages.JSON_OBJECT does not exist

echo "Users: "
mysql -P 3306 --password="$PASSWORD" --user="$USER" --host="$HOST" --database="$DATABASE" -Bse "$SCRIPT" 2>&1 | grep -v "Using a password"
