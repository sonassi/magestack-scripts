#!/bin/bash

MAIN_BACKUP_DIR="/microcloud/backups_ro"
MAIN_LOGS_DIR="/microcloud/logs_ro"
SSH_ORIGINAL_COMMAND="$1"

if [[ ! "$SSH_ORIGINAL_COMMAND" == "" ]]; then
  case "$SSH_ORIGINAL_COMMAND" in
    "get_usage")
      get_usage
      ;;
    "ls $MAIN_BACKUP_DIR/.domains.running"|\
    "ls $MAIN_BACKUP_DIR/.mysql.running"|\
    "ls $MAIN_BACKUP_DIR/.config.running"|\
    "ls $MAIN_BACKUP_DIR/.logs.running"|\
    "find $MAIN_BACKUP_DIR/domains/ -mindepth 1 -maxdepth 1 -type d"|\
    "find $MAIN_BACKUP_DIR/logs/ -mindepth 1 -maxdepth 1 -type d"|\
    "find $MAIN_BACKUP_DIR/mysql/ -mindepth 1 -maxdepth 1 -type d")
      $SSH_ORIGINAL_COMMAND
      ;;
    "df -P /microcloud/backups_ro"|\
    "df -P /microcloud/logs_ro")
      $SSH_ORIGINAL_COMMAND | awk '/microcloud/ {printf("%d", $2)}'
      ;;
    "rsync --server --sender -logDtpre.iLsf --bwlimit=5000 --numeric-ids . $MAIN_BACKUP_DIR/domains/"[0-9][0-9][0-9][0-9]"-"[0-9][0-9]"-"[0-9][0-9]"/."|\
    "rsync --server --sender -logDtpre.iLsf --bwlimit=5000 --numeric-ids . $MAIN_BACKUP_DIR/domains/"|\
    "rsync --server --sender -logDtpre.iLsf --bwlimit=5000 --numeric-ids . $MAIN_BACKUP_DIR/mysql/"|\
    "rsync --server --sender -logDtpre.iLsf --bwlimit=5000 --numeric-ids . $MAIN_BACKUP_DIR/config/"|\
    "rsync --server --sender -logDtpre.iLsf --bwlimit=5000 --numeric-ids . $MAIN_LOGS_DIR/")
      ionice -c 2 -n 7 nice $SSH_ORIGINAL_COMMAND
      ;;
    "test")
      su remote-backup -c whoami
      ;;
    *)
      echo "Invalid command"
      ;;
  esac
fi

exit 0
