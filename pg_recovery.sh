#!/bin/bash

. $(dirname $0)/backup_vars


DBNAME=dbdump
last_backup=$(s3cmd ls s3://$BUCKET|grep $DBNAME|grep .gz|sort|tail -1|awk '{print $4}')
backup_downloaded=0

function backup_download {
  yes-no "We're going to download file $backup_file, is that correct? (y/N) " 
  s3cmd get $backup_file
  [ $? -eq 0 ] && backup_downloaded=1
  while [ $backup_downloaded -eq 0 ];do
    yes-no "Download unsuccessful. Do you want to retry? (y/N) " 
  done
}

function import_backup {
  local_file=$(basename $backup_file)
  yes-no "We're going to uncompress $local_file. Is that ok? (y/N) "
  pv $local_file |gzip -d > ${local_file%.*}
  [ $? -ne 0 ] && echo "Error uncompressing backup file" && exit 1
  yes-no "File uncompressed. Do you want to import it? (y/N)"
  pv ${local_file%.*} | pgsql
  [ $? -ne 0 ] && echo "Error importing backup file" && exit 1
}

function list_files {
  s3cmd ls s3://$BUCKET/$1
}

function yes-no {
  read -p "$1" bool
  [ "$bool" != "y" ] && echo "Ok, aborting..." && exit 1
}

[ $# -lt 1 ] && echo "Error, missing parameter" && echo "Usage: $0 list|recovery [date]" && exit 1

[ $1 == "list" ] && list_files && exit 0
[ $1 != "recovery" ] && echo "Error, $1 is an incorrect action. Correct values: list, recovery" && exit 1
[ -z $2 ] && echo "No date provided, assuming recovery of last backup" && backup_file=$last_backup

[ ! -z $2 ] && backup_file=$(s3cmd ls s3://$BUCKET|grep $DBNAME|grep $2.gz|tail -1|awk '{print $4}')
[ -z $backup_file ] && echo "There is no backup of this database on this date, please check again with '$0 list', and remember date format is YYYYmmdd" && exit


backup_download
import_backup
echo "Backup imported successfully!"
yes-no "Do you want to delete downloaded backup files? (y/N) "
rm -f $local_file ${local_file%.*}
