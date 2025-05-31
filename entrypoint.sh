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
msg="[$TS] rsync-cron container started. Next scheduled run at: ${NEXT}"
echo "$msg" | tee -a "$LOGFILE"

if [[ -n "${HEALTHCHECK_PING_URL:-}" ]]; then
  curl -fsS -X POST "${HEALTHCHECK_PING_URL}" \
    -H 'Content-Type: text/plain' \
    --data "$msg" || echo "Failed to notify healthcheck OK" >> /proc/1/fd/1
fi

# Start cron daemon
exec crond -f -l 2