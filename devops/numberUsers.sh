#!/bin/bash

# Usage: numberUsers.sh <Server.json>

# e.g., ./numberUsers.sh ~/Desktop/Apps/SyncServerII/Private/Server.json.aws.app.bundles/Neebla-production.json

MY_SQL_JSON=$1
DATABASE=`jq -r '.["mySQL.database"]' < ${MY_SQL_JSON}`
USER=`jq -r '.["mySQL.user"]' < ${MY_SQL_JSON}`
PASSWORD=`jq -r '.["mySQL.password"]' < ${MY_SQL_JSON}`
HOST=`jq -r '.["mySQL.host"]' < ${MY_SQL_JSON}`

SCRIPT="select count(*) from User;"

echo -n "Number of users: "
mysql -P 3306 --password="$PASSWORD" --user="$USER" --host="$HOST" --database="$DATABASE" -Bse "$SCRIPT" 2>&1 | grep -v "Using a password"
