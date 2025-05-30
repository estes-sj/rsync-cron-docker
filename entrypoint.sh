#!/usr/bin/env bash
set -euo pipefail

# Configure timezone
if [ -n "${TZ:-}" ]; then
  cp "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# Prepare cron log file
LOGFILE=/var/log/rsync-cron.log
touch "$LOGFILE"
chmod 644 "$LOGFILE"

# Build crontab
: > /etc/crontabs/root
echo "${SYNC_FREQUENCY:-} /usr/local/bin/run-rsync-jobs.sh >> $LOGFILE 2>&1" >> /etc/crontabs/root

# Startup message and next run calculation
TS=$(date +"%Y-%m-%dT%H:%M:%S%z")
NEXT=$(python3 - <<PYCODE
from croniter import croniter
from datetime import datetime
import os
expr = os.getenv('SYNC_FREQUENCY') or ''
if expr:
    next_run = croniter(expr, datetime.now()).get_next(datetime)
    print(next_run.strftime("%Y-%m-%d %H:%M:%S %Z"))
PYCODE
)
echo "[$TS] rsync-cron container started. Next scheduled run at: ${NEXT}" | tee -a "$LOGFILE"

# Start cron daemon
exec crond -f -l 2