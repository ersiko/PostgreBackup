#!/bin/bash

. $(dirname $0)/backup_vars
. $(dirname $0)/max_backup_duration

MAX_LOAD=1 #Maximum load in the server when the backup starts
START_TIME=0:00 # 
END_TIME=6:00 #Maximum time our script is allowed to start. The script code should be changed if backup windows starts and ends in different days, it only works on the same day.
MARGIN_TIME=1800 # how much deviation from max_backup_duration we want, in seconds
DESTINATION=/tmp
MAX_RETRIES=3 # Max backup error retries 
RETRY_SECONDS=10 # seconds to wait for a retry

#initial values
endtime=$(date -d $END_TIME +%s)
starttime=$(date -d $START_TIME +%s)
backup_done=0
backup_uploaded=0
day_suffix=$(date +%Y%m%d)
errors=0
backup_started=$(date +%s)

function backup {
  if [ $backup_done -eq 0 ];then
    echo "Starting backup"
    pg_dumpall | gzip > $DESTINATION/$DBNAME-$day_suffix.gz
    if [ $? -eq 0 ];then
      echo "Backup successful"
      backup_done=1
      errors=0
    else
      echo "Something went wrong backing up, we will try again in $RETRY_SECONDS seconds"
      let errors++
      sleep $RETRY_SECONDS
    fi
  fi
}

function upload_backup {
  if [ $backup_uploaded -eq 0 ];then
    s3cmd put $DESTINATION/$DBNAME-$day_suffix.gz s3://$BUCKET
    if [ $? -eq 0 ];then
      echo "Backup uploaded succesfully"
      backup_uploaded=1
    else
      echo "Something went wrong uploading the backup, we will try again in $RETRY_SECONDS seconds"
      let errors++
      sleep $RETRY_SECONDS
    fi  
  fi  
}

function high_load {
  [ $(cat /proc/loadavg |cut -f1 -d".") -ge $MAX_LOAD ] && echo "1" && exit
  echo "0"
}

while [ $(date +%s) -lt $starttime ];do
  echo "It's too early, can't start backup. Waiting until $START_TIME"
  sleep 300
done

now=$(date +%s)
let foreseeable_endtime=$now+$max_backup_duration+$MARGIN_TIME  #calculating when backup might end to see if it's still inside the time window 

while [ $foreseeable_endtime -lt $endtime ] && [ $backup_uploaded -eq 0 ] && [ $errors -lt $MAX_RETRIES ]; do
  if [ $(high_load) -eq 0 ];then
    backup
    upload_backup
  else
    echo "Couldn't start backup, server load is too high"
    sleep 60
  fi
  now=$(date +%s)
  let foreseeable_endtime=$now+$max_backup_duration+$MARGIN_TIME  #calculating when backup might end to see if it's still inside the time window 
done

backup_ended=$(date +%s)
let backup_duration=$backup_ended-$backup_started

[ $foreseeable_endtime -ge $endtime ] && echo "Out of our backup window, giving up" && send_mail "Error backing up pg_sql" "Out of our backup window, giving up" 
[ $errors -eq $MAX_RETRIES ] && echo "Too much backup retries, giving up" && send_mail "Error backing up pg_sql" "Too much backup retries, giving up"
[ $backup_done -eq 1 ] && send_mail "Successfully backed up pg_sql" "Backup successful" && [ $backup_duration -gt $max_backup_duration ] && echo "max_backup_duration=$backup_duration" > $(dirname $0)/max_backup_duration

