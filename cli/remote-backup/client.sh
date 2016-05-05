#!/bin/bash

# Check if backup is already running
pidof -x $(basename $0) -o %PPID >/dev/null 2>&1
if [ $? -eq 0 ] && [[ ! "$2" == "1" ]]; then
  [[ ! "$1" == "cron" ]] && echo "Backup is already running"
  exit 0
fi

# Check if VPN is up
timeout 5 ping -c 1 acc.magestack.com >/dev/null 2>&1
if [ $? -ne 0 ]; then
  /etc/init.d/openvpn restart >/dev/null 2>&1
  sleep 10
  timeout 5 ping -c 1 acc.magestack.com >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "VPN tunnel is still down, cannot perform backup"
  fi
fi

echo_date ()
{
  DATE=$(date +%FT%T);
  echo -e "[$DATE]: $1"
}

REMOTE_HOSTS=( acc.magestack.com )
REMOTE_USER="remote-backup"
MAIN_BACKUP_DIR="/microcloud/backups_ro"
MAIN_LOGS_DIR="/microcloud/logs_ro"
BACKUP_TYPES=( logs_ro mysql domains )
SSH_OPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no -o Compression=no -p 22 -o ConnectTimeout=10"
RETENTION_DAYS=7
RSYNC_OPTS="-a"
FORCE_BACKUP=1
RESULT_FILE=$(mktemp /tmp/results.XXXXX)
ionice="ionice -c2 -n7"

[ -f "remote-backup.conf" ] && source remote-backup.conf

for HOST in ${REMOTE_HOSTS[@]}; do

  REMOTE="$REMOTE_USER@$HOST"
  BACKUP_DEST="$MAIN_BACKUP_DIR/$HOST"
  BACKUP_SOURCE="$MAIN_BACKUP_DIR"
  BACKUP_DIR="$BACKUP_DEST"
  CMD_FILE="$BACKUP_DIR/cmd"
  START_TIME=$(date +%s)
  BACKUP_DATE=$(date +%F)

  echo_date "Running backup on $HOST"

  # Create backup dir
  if [ ! -d "$BACKUP_DEST" ]; then
    mkdir -p $BACKUP_DEST/domains $BACKUP_DEST/mysql $BACKUP_DEST/logs_ro
    touch $BACKUP_DEST -d "-1 day"
  fi

  # Skip a backup if it has been recently created (last 24 hours)
  LAST_BACKUP=$(find $MAIN_BACKUP_DIR -maxdepth 1 -mindepth 1 -name $HOST -type d -mmin +1440 | wc -l)
  if [ $LAST_BACKUP -eq 0 ] && [ $FORCE_BACKUP -eq 0 ]; then
    echo_date "Backup less than 24 hours old, skipping ..."
    continue
  fi

  # Check SSH is up before proceeding
  REMOTE_BACKUP_SIZE=$(</dev/null ssh $SSH_OPTS $REMOTE test 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo_date "ERROR: Failed to connect via SSH"
    FAILURE=1 && continue
  fi

  # Check to see if any remote backups are running before proceeding
  for BACKUP_TYPE in ${BACKUP_TYPES[@]}; do
    RES=$(</dev/null ssh $SSH_OPTS $REMOTE "ls $MAIN_BACKUP_DIR/.$BACKUP_TYPE.running" 2>/dev/null | wc -l)
    [ $RES -eq 1 ] && echo_date "ERROR: Local $BACKUP_TYPE backup is currently running on remote host ($HOST)" && continue 2
  done

  echo_date "Starting backup for $HOST"

  REMOTE_LOGS_SPACE=$(</dev/null ssh $SSH_OPTS $REMOTE df -P /microcloud/logs_ro 2>/dev/null)
  REMOTE_BACKUPS_SPACE=$(</dev/null ssh $SSH_OPTS $REMOTE df -P /microcloud/backups_ro 2>/dev/null)

  # First, rotate the local dirs for the domains so that the incremental changes are much smaller
  if [ -d "$BACKUP_DIR/domains" ]; then

    echo_date "Synchronsing and deleting domain backups locally before remote sync"
    (cd $BACKUP_DIR/domains; find -mindepth 1 -maxdepth 1 -type d -regex "./[0-9]+-[0-9]+-[0-9]+" | sed 's#./##g') | while read DIR; do
      touch $BACKUP_DIR/domains/$DIR -d "$DIR"
    done

    # Get a list of the remote domain backups (some customers might keep backups longer than others), then remove any local dirs that don't exist remotely
    for BACKUP_TYPE in ${BACKUP_TYPES[@]}; do
      case $BACKUP_TYPE in
        "logs_ro")
          continue
          ;;
       esac

      REMOTE_DIRS=( $(</dev/null ssh $SSH_OPTS $REMOTE "find $MAIN_BACKUP_DIR/${BACKUP_TYPE}/ -mindepth 1 -maxdepth 1 -type d" | sed "s#$MAIN_BACKUP_DIR/${BACKUP_TYPE}/##g" | sort -n ) )

      case $BACKUP_TYPE in
        "domains")
          REMOTE_DOMAIN_DIRS=( ${REMOTE_DIRS[@]} )
          ;;
       esac

    done

    # Remove old backups up to the retention period
    for BACKUP_TYPE in ${BACKUP_TYPES[@]}; do
      echo_date "Removing old ${BACKUP_TYPE} backups"
      LOCAL_BACKUP_DIRS=( $(find $BACKUP_DEST/$BACKUP_TYPE -maxdepth 1 -mindepth 1 -type d -regex "./[0-9]+-[0-9]+-[0-9]+" 2>/dev/null | sort -n) )
      if [ ${#LOCAL_BACKUP_DIRS[@]} -gt $RETENTION_DAYS ]; then
        for LOCAL_DIR in ${LOCAL_BACKUP_DIRS[@]}; do
          $ionice rm -rf $LOCAL_DIR
        done
      fi
    done

  fi

  # Now run the backup
  for BACKUP_TYPE in ${BACKUP_TYPES[@]}; do
    echo_date "Running incremental remote backup ($BACKUP_TYPE)"

    >$CMD_FILE

    case $BACKUP_TYPE in
      "mysql")
        cat >> $CMD_FILE <<EOF
          rsync --bwlimit=5000 --stats -a -e "ssh -c arcfour $SSH_OPTS" --numeric-ids $SSH_CMD \
            --exclude="hot" \
            $REMOTE:$BACKUP_SOURCE/$BACKUP_TYPE/ $BACKUP_DEST/$BACKUP_TYPE/
EOF
        ;;
      "domains")
        # Remove junk files
        rm $BACKUP_DEST/$BACKUP_TYPE/{latest-full,latest-snap,results.txt,*.log} 2>/dev/null

        # Run a number of supplementary syncs that reference local backups for a quicker sync
        for DATE_DIR in ${REMOTE_DOMAIN_DIRS[@]}; do
          cat >> $CMD_FILE <<EOF
            rsync --bwlimit=5000 --stats -a -e "ssh -c arcfour $SSH_OPTS" --numeric-ids --delete $SSH_CMD \
              --exclude="./snap" \
              --link-dest=$BACKUP_DEST/$BACKUP_TYPE/latest \
              $REMOTE:$BACKUP_SOURCE/$BACKUP_TYPE/$DATE_DIR/. $BACKUP_DEST/$BACKUP_TYPE/$DATE_DIR/
          rm $BACKUP_DEST/$BACKUP_TYPE/latest 2>/dev/null
          ln -s $BACKUP_DEST/$BACKUP_TYPE/$DATE_DIR $BACKUP_DEST/$BACKUP_TYPE/latest
EOF
        done
        ;;
        "logs_ro")
          cat >> $CMD_FILE <<EOF
            rsync --bwlimit=5000 --stats -a -e "ssh -c arcfour $SSH_OPTS" --numeric-ids $SSH_CMD \
              $REMOTE:$MAIN_LOGS_DIR/ $BACKUP_DEST/$BACKUP_TYPE/$BACKUP_DATE
EOF
          ;;
    esac

    bash $CMD_FILE >> $RESULT_FILE
    RES=$?
    if [ $RES -ne 0 ]; then
      echo_date "ERROR: Failure during rsync"
      FAILURE=1 && continue
    fi

  done

  sleep 1
  SPEED_TRUE_MB=$(awk '/([0-9.]+) bytes/sec/ { count+=1; sum+=$7 } END { printf("%0.2f", sum/count/1000000) }' $RESULT_FILE)
  TRANSFER_SIZE_TRUE_GB=$(awk '/Total bytes received: ([0-9]+)/ { sum+=$4 } END { printf("%0.2f", sum/1000000000) }' $RESULT_FILE)
  TOTAL_TIME=$(( $(date +%s) - START_TIME ))
  TOTAL_TIME_FORMATTED=$(echo - | awk -v "S=$TOTAL_TIME" '{printf "%dh %dm %ds",S/(60*60),S%(60*60)/60,S%60}')
  touch $BACKUP_DIR

  echo_date "Backup ${TRANSFER_SIZE_TRUE_GB}GB completed successfully in $TOTAL_TIME_FORMATTED at $SPEED_TRUE_MB MB/s"

done

rm $RESULT_FILE $CMD_FILE
