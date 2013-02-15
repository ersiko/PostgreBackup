#!/bin/bash

MAX_LOAD=1 #Maximum load in the server when the backup starts
START_TIME=0:00 # 
END_TIME=4:30 #Maximum time our script is allowed to start. The script code should be changed if backup windows starts and ends in different days, it only works on the same day.
ADMIN_MAIL=tomas@criptos.com #Address where to notify about the results
DESTINATION=/tmp
FILENAME=dbdump
MAX_RETRIES=3 # Max backup error retries 
RETRY_SECONDS=10 # seconds to wait for a retry

#initial values
endtime=$(date -d $END_TIME +%s)
starttime=$(date -d $START_TIME +%s)
backup_done=0
day_suffix=$(date +%Y%m%d)
errors=0

function backup {
  echo "Starting backup"
  pg_dumpall | gzip > $DESTINATION/$FILENAME-$day_suffix.gz
  if [ $? -eq 0 ];then
    echo "Backup successful"
    backup_done=1
  else
    echo "Something went wrong, we will try again in $RETRY_SECONDS seconds"
    let errors++
    sleep $RETRY_SECONDS
  fi
}

function high_load {
  [ $(cat /proc/loadavg |cut -f1 -d".") -ge $MAX_LOAD ] && echo "1" && exit
  echo "0"
}

function send_mail {
  mail $ADMIN_MAIL << EOF
$1  
EOF
}

while [ $(date +%s) -lt $starttime ];do
  echo "It's too early, can't start backup. Waiting until $START_TIME"
  sleep 300
done

while [ $(date +%s) -lt $endtime ] && [ $backup_done -eq 0 ] && [ $errors -lt $MAX_RETRIES ]; do
  if [ $(high_load) -eq 0 ];then
    backup
  else
    echo "Couldn't start backup, server load is too high"
    sleep 60
  fi
done

[ $(date +%s) -ge $endtime ] && echo "Out of our backup window, giving up" && send_mail "Out of our backup window, giving up" 
[ $errors -eq $MAX_RETRIES ] && echo "Too much backup retries, giving up" && send_mail "Too much backup retries, giving up"
[ $backup_done -eq 1 ] && send_mail "Backup successful"
