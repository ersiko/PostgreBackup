#!/bin/bash

. $(dirname $0)/backup_vars

[ $# -lt 1 ] && echo "Missing arguments" && echo "Usage: $0 daily|weekly" && exit 1
[ $1 != "daily" ] && [ $1 != "weekly" ] && echo "Error, incorrect argument. Accepted values: daily, weekly. Usage: $0 daily|weekly" && exit 1
[ $1 == "daily" ] && date=$(date -d "7 days ago" +%Y%m%d)
[ $1 == "weekly" ] && date=$(date -d "53 weeks ago" +%Y%m%d)

file_exists=$(s3cmd ls s3://pg_backup/$DBNAME-$date.gz)
[ -z "$file_exists" ] && send_mail "Error pruning pg_backup bucket" "Something went wrong pruning pg_backup bucket. File s3://pg_backup/$DBNAME-$date.gz doesn't exists" && exit 1
s3cmd del s3://pg_backup/$DBNAME-$date.gz
