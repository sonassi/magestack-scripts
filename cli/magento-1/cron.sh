#!/bin/bash

EMAIL_RECIPIENT=""
MAX_DURATION="43200"

##########################################
# Do not modify anything below this line #
##########################################

CUR_PID="$$"
SCRIPT_NAME="$0"
INSTALLDIR=$(dirname $0)
PHP_BIN=$(which php)
DOMAIN_GROUP=$(echo $INSTALLDIR | sed -n -E 's#/.*domains/([^/]+)/domains.*#\1#p')
REL_INSTALLDIR=$(echo $INSTALLDIR | sed -E "s#.*?$DOMAIN_GROUP/#/#g" )
PIDKEY=$(echo "${SCHEDULER_WHITELIST}/${SCHEDULER_BLACKLIST}" | md5sum - | cut -f1 -d" ")
LOG_FILE="$INSTALLDIR/var/log/cron.log"
PID_FILE="$INSTALLDIR/var/log/.cron.${PIDKEY}.pid"
CRON_ARGS=( "na" )

[ ! -d "$INSTALLDIR/var/log" ] && mkdir -p $INSTALLDIR/var/log
[ ! -f "$LOG_FILE" ] && touch $LOG_FILE
[ ! -f "$PID_FILE" ] && touch $PID_FILE

# Empty the log file before each run (remove this if you want continuous logging, but ensure log rotation is configured first)
>$INSTALLDIR/var/log/cron.log

function print_time() {
  echo -e "\n=============================================================\n$1:$(date)\n=============================================================" >> $LOG_FILE 2>&1
  echo "$1"
}

PID=$(cat $PID_FILE)
if [[ ! "$PID" == "" ]]; then
  kill -0 $PID 2>/dev/null
  [ $? -eq 0 ] && echo "Error: Cron is already running" && exit 99
fi

[[ ! "$SCHEDULER_WHITELIST" == "" ]] && export SCHEDULER_WHITELIST=$SCHEDULER_WHITELIST
[[ ! "$SCHEDULER_BLACKLIST" == "" ]] && export SCHEDULER_BLACKLIST=$SCHEDULER_BLACKLIST

print_time "Starting cron"
echo $CUR_PID > $PID_FILE

# Magento 1.8/1.13 fix for revised recursive cron.php
grep -qF "($isShellDisabled)" /$INSTALLDIR/cron.php
[ $? -eq 0 ] && CRON_ARGS=( "-mdefault 1" "-malways 1" )

RES=5
for ARGS in "${CRON_ARGS[@]}"; do
  echo "$PHP_BIN $REL_INSTALLDIR/cron.php $ARGS" | timeout $MAX_DURATION fakechroot /usr/sbin/chroot /microcloud/domains/$DOMAIN_GROUP /bin/bash >> $LOG_FILE 2>&1
  [ $RES -ne 0 ] && RES=$?
done

if [ $RES -ne 0 ] && [[ ! "$EMAIL_RECIPIENT" == "" ]]; then
  echo "Something went wrong with the cron, see attached" | mutt -s "Cron error" -a "$LOG_FILE" -- $EMAIL_RECIPIENT
fi
print_time "Completed cron"
exit 0
