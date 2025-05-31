#!/usr/bin/env bash
set -euo pipefail

REPORT_URL="${BACKREST_REPORTER_URL:-}"

ping_healthcheck() {
  local suffix="$1"
  local msg="$2"

  if [[ -n "${HEALTHCHECK_PING_URL:-}" ]]; then
    curl -fsS -X POST "${HEALTHCHECK_PING_URL}${suffix}" \
      -H 'Content-Type: text/plain' \
      --data "$msg" || echo "Healthcheck ping to ${suffix:-/} failed" >> /proc/1/fd/1
  fi
}

start() {
  local msg="$1"
  echo "$msg" >> /proc/1/fd/1
  ping_healthcheck "/start" "$msg"
}

ok() {
  local msg="$1"
  echo "$msg" >> /proc/1/fd/1
  ping_healthcheck "" "$msg"
}

fail() {
  local msg="$1"
  echo "$msg" >> /proc/1/fd/1
  ping_healthcheck "/fail" "$msg"
}

# Iterate over configured pairs
for i in $(compgen -A variable \
              | grep '^STORAGE_FROM_' \
              | sed 's/STORAGE_FROM_//'); do

  SRC_VAR="STORAGE_FROM_$i"
  DST_VAR="STORAGE_TO_$i"

  SRC="${!SRC_VAR:-}"
  DST="${!DST_VAR:-}"

  MNT_SRC="/mnt/from$i"
  MNT_DST="/mnt/to$i"

  # skip if env not set
  if [ -z "${!SRC_VAR:-}" ] || [ -z "${!DST_VAR:-}" ]; then
    continue
  fi

  TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S%z")
  log "[$TIMESTAMP] Starting rsync: '$SRC' → '$DST' (mount: '$MNT_SRC' → '$MNT_DST')"

  rsync -avh --delete "$MNT_SRC"/ "$MNT_DST"/
  EXIT_CODE=$?

  log "[$(date +"%Y-%m-%dT%H:%M:%S%z")] Completed rsync: '$SRC' → '$DST' (mount: '$MNT_SRC' → '$MNT_DST'): exit code $EXIT_CODE"

done
