#!/usr/bin/env bash
set -euo pipefail

REPORT_URL="${BACKREST_REPORTER_URL:-}"
HEALTHCHECK_PING_URL="${HEALTHCHECK_PING_URL:-}"

# -----------------------------------------------------------------------------
# Optional healthcheck pinging if configured
# -----------------------------------------------------------------------------
ping_healthcheck() {
  local suffix="$1"
  local msg="$2"

  if [[ -n "${HEALTHCHECK_PING_URL:-}" ]]; then
    curl -fsS -X POST "${HEALTHCHECK_PING_URL}${suffix}" \
      -H 'Content-Type: text/plain' \
      --data "$msg" \
      || log_error "Healthcheck ping to ${suffix:-/} failed"
  fi
}

# -----------------------------------------------------------------------------
# Core logger: handles timestamp + level + message
# -----------------------------------------------------------------------------
_log_message() {
  local LEVEL="$1"
  local MSG="$2"
  # * Generate ISO-8601 timestamp with timezone (e.g. 2025-05-31T14:23:45-0400)
  local TIMESTAMP
  TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S%z")

  # * Write to container’s stdout ( /proc/1/fd/1 ) so docker can capture it
  echo "[$TIMESTAMP] [$LEVEL] $MSG" >> /proc/1/fd/1
}

# -----------------------------------------------------------------------------
# Public logging functions (no healthcheck)
# -----------------------------------------------------------------------------
log_info() {
  _log_message "INFO" "$1"
}

log_error() {
  _log_message "ERROR" "$1"
}

# -----------------------------------------------------------------------------
# Convenience wrappers that ALSO ping a healthcheck endpoint
# -----------------------------------------------------------------------------
#   start:  INFO + /start healthcheck
#   ok:     INFO + (no suffix) healthcheck
#   fail:   ERROR + /fail healthcheck
# -----------------------------------------------------------------------------
start() {
  local MSG="$1"
  # Log at INFO
  _log_message "INFO" "$MSG"
  # Ping the "/start" endpoint
  ping_healthcheck "/start" "$MSG"
}

ok() {
  local MSG="$1"
  # Log at INFO
  _log_message "INFO" "$MSG"
  # Ping the default-success endpoint
  ping_healthcheck "" "$MSG"
}

fail() {
  local MSG="$1"
  # Log at ERROR
  _log_message "ERROR" "$MSG"
  # Ping the "/fail" endpoint
  ping_healthcheck "/fail" "$MSG"
}

# -----------------------------------------------------------------------------
# MAIN LOOP: iterate over STORAGE_FROM_N / STORAGE_TO_N pairs and perform rsync
# -----------------------------------------------------------------------------
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

  # Prepare fields for JSON
  # ──────────────────────────────────────────────────────────────────────────────
  # 1) Generate a snapshot ID (SHA-256 of the sources, destination, and current timestamp)
  snapshot_id=$(echo "${SRC}_${DST}_$(date +%s%N)" | sha256sum | cut -c1-64)

  # 2) Record start time (seconds since epoch w/ nanoseconds) & a pretty timestamp
  start_ns=$(date +"%s%N")
  TIMESTAMP_START=$(date +"%Y-%m-%dT%H:%M:%S%z")
  start "[$TIMESTAMP_START] Starting rsync: '$SRC' → '$DST' (mount: '$MNT_SRC' → '$MNT_DST')"

  # 3) Run rsync with --stats, capturing all output (stdout+stderr) into a variable
  rsync_output=$(rsync -avh --delete --stats "$MNT_SRC"/ "$MNT_DST"/ 2>&1) || EXIT_CODE=$?
  EXIT_CODE=${EXIT_CODE:-0}

  # 4) Record finish time and compute duration
  finish_ns=$(date +"%s%N")
  TIMESTAMP_END=$(date +"%Y-%m-%dT%H:%M:%S%z")
  # Subtract to get the elapsed time in ns
  diff_ns=$(( finish_ns - start_ns )) # e.g. 212112 ns
  # Convert to seconds + fractional part
  duration_sec=$(awk "BEGIN { printf \"%.6f\", $diff_ns / 1000000000 }")

  # 5) Compute folder stats from the source mount
  total_files=$(find "$MNT_SRC" -type f 2>/dev/null | wc -l)
  total_dirs=$(find "$MNT_SRC" -type d 2>/dev/null | wc -l)
  total_bytes=$(du -sb "$MNT_SRC" 2>/dev/null | awk '{print $1}')

  # Normalize numeric values: if empty or not digits, set to ""
  if [[ ! "$total_bytes" =~ ^[0-9]+$ ]]; then
    total_bytes=""
  fi
  if [[ ! "$total_files" =~ ^[0-9]+$ ]]; then
    total_files=""
  fi
  if [[ ! "$total_dirs" =~ ^[0-9]+$ ]]; then
    total_dirs=""
  fi

  # 6) Parse the --stats from the rsync output
  # (a) Number of created files
  created_files=$(awk -F: '/^Number of created files:/ { gsub(/[^0-9]/, "", $2); print $2 }' <<<"$rsync_output")
  # (b) Number of deleted files
  deleted_files=$(awk -F: '/^Number of deleted files:/ { gsub(/[^0-9]/, "", $2); print $2 }' <<<"$rsync_output")
  # (c) Number of regular files transferred
  regular_transferred=$(awk -F: '/^Number of regular files transferred:/ { gsub(/[^0-9]/, "", $2); print $2 }' <<<"$rsync_output")
  # (d) Total transferred file size (as raw, e.g. "13.17K")
  total_transferred_size=$(awk -F: '/^Total transferred file size:/ { gsub(/^[[:space:]]*/,"", $2); print $2 }' <<<"$rsync_output")

  # If any of these didn’t match, force them to "0" or empty
  created_files=${created_files:-0}
  deleted_files=${deleted_files:-0}
  regular_transferred=${regular_transferred:-0}
  total_transferred_size=${total_transferred_size:-"0"}

  # Extract "13.17K" (strip off the trailing " bytes")
  total_transferred_size_human=$(awk -F: '/^Total transferred file size:/ {
    sub(/ bytes$/, "", $2)
    gsub(/^[[:space:]]+/, "", $2)
    print $2
  }' <<<"$rsync_output")

  # Convert to a raw‐byte integer (e.g. 13500)
  if [[ -n "$total_transferred_size_human" ]]; then
    total_transferred_size_bytes=$(
      numfmt --from=iec "$total_transferred_size_human" 2>/dev/null || echo ""
    )
  else
    total_transferred_size_bytes=""
  fi

  # Default to empty or null if conversion failed
  total_transferred_size_bytes=${total_transferred_size_bytes:-""}

  # Compute files_changed if the associated stats are valid
  if [[ -n "$deleted_files" && -n "$regular_transferred" ]]; then
    files_changed=$(( deleted_files + regular_transferred ))
  else
    files_changed=""
  fi

  # Compute files_unmodified if the associated stats are valid
  if [[ -n "$total_files" && -n "$created_files" && -n "$regular_transferred" ]]; then
    files_unmodified=$(( total_files - created_files - regular_transferred ))
    # guard against negative (in case rsync stats were inconsistent)
    if (( files_unmodified < 0 )); then
      files_unmodified=0
    fi
  else
    files_unmodified=""
  fi

  # 7) Log success or failure for the rsync process.
  #    The logged duration only includes the rsync length while the healthchecks time (since the /start) includes gathering stats
  if [[ $EXIT_CODE -eq 0 ]]; then
    ok "Completed rsync: '$SRC' → '$DST' (exit code $EXIT_CODE, duration ${duration_sec}s, data_transferred=${total_transferred_size}, files_processed=${total_files:-0})"
  else
    fail "rsync FAILED: '$SRC' → '$DST' (exit code $EXIT_CODE, duration ${duration_sec}s, data_transferred=${total_transferred_size}, files_processed=${total_files:-0})"
  fi

  # 8) Backrest reporter - Build & POST JSON if REPORT_URL is set
  if [[ -n "$REPORT_URL" ]]; then
    if [[ -z "$BACKREST_API_KEY" ]]; then
      fail "BACKREST_REPORT_URL is set but BACKREST_API_KEY is not set."
      exit 1
    fi

    # Prepare event and error string
    if [[ $EXIT_CODE -eq 0 ]]; then
      EVENT="snapshot success"
      ERROR_FIELD="" # "" will become null in jq
    else
      EVENT="snapshot failure"
      ERROR_FIELD="\"rsync exited with code $EXIT_CODE\""
    fi

    # Populate the optional mock restic plan and repo names
    BACKREST_REPO_VAR="STORAGE_REPO_$i"
    BACKREST_PLAN_VAR="STORAGE_PLAN_$i"

    BACKREST_REPO="${!BACKREST_REPO_VAR:-}"
    BACKREST_PLAN="${!BACKREST_PLAN_VAR:-}"

    # Fallback logic
    REPO_ARG_VALUE="$BACKREST_REPO"
    PLAN_ARG_VALUE="$BACKREST_PLAN"

    # Use the STORAGE_FROM_N and STORAGE_TO_N if no plan/repo names were provided
    if [[ -z "$REPO_ARG_VALUE" ]]; then
      REPO_ARG_VALUE="$DST"
    fi

    if [[ -z "$PLAN_ARG_VALUE" ]]; then
      PLAN_ARG_VALUE="$SRC"
    fi

    # Build jq arguments to handle numeric vs null correctly
    # (jq will treat an empty string as a literal "" if we don’t convert it to null)
    #
    #      - repo                  = REPO_ARG_VALUE
    #      - plan                  = PLAN_ARG_VALUE
    #      - files_new             = created_files
    #      - files_changed         = files_changed (deleted_files + regular_transferred)
    #      - files_unmodified      = files_unmodified (total_files - created_files - regular_transferred)
    #      - dirs_unmodified       = total_dirs
    #      - total_files_processed = total_files
    #      - total_bytes_processed = total_bytes
    #      - total_duration        = duration_sec
    #      - data_added            = total_transferred_size_bytes
    #
    
    # Summary field repo
    jq_repo_arg=( --arg repo "$REPO_ARG_VALUE" )

    # Summary field plan
    jq_plan_arg=( --arg plan "$PLAN_ARG_VALUE" )

    # Summary field total_files_processed
    if [[ -n "$total_files" ]]; then
      jq_files_arg=( --argjson files_val "$total_files" )
    else
      jq_files_arg=( --argjson files_val null )
    fi

    if [[ -n "$total_dirs" ]]; then
      jq_dirs_arg=( --argjson dirs_val "$total_dirs" )
    else
      jq_dirs_arg=( --argjson dirs_val null )
    fi

    # Summary field total_bytes_processed
    if [[ -n "$total_bytes" ]]; then
      jq_bytes_arg=( --argjson bytes_val "$total_bytes" )
    else
      jq_bytes_arg=( --argjson bytes_val null )
    fi

    # Summary field total_duration
    if [[ -n "$duration_sec" ]]; then
      jq_duration_arg=( --argjson dur_val "$duration_sec" )
    else
      jq_duration_arg=( --argjson dur_val null )
    fi

    # Summary field - files_new
    if [[ -n "$created_files" ]]; then
      jq_new_arg=( --argjson files_new "$created_files" )
    else
      jq_new_arg=( --argjson files_new null )
    fi

    # Summary field - files_changed
    if [[ -n "$files_changed" ]]; then
      jq_changed_arg=( --argjson files_changed "$files_changed" )
    else
      jq_changed_arg=( --argjson files_changed null )
    fi

    # Summary field - files_unmodified
    if [[ -n "$files_unmodified" ]]; then
      jq_unmod_files_arg=( --argjson files_unmodified "$files_unmodified" )
    else
      jq_unmod_files_arg=( --argjson files_unmodified null )
    fi

    # Summary field - data_added
    if [[ -n "$total_transferred_size_bytes" ]]; then
      jq_data_added_arg=( --argjson data_added "$total_transferred_size_bytes" )
    else
      jq_data_added_arg=( --argjson data_added null )
    fi

    # Build the JSON payload exactly as requested
    payload=$(
      jq -n \
        --arg task     "backup for plan \"${PLAN_ARG_VALUE:-}\"" \
        --arg time     "$TIMESTAMP_END" \
        --arg event    "$EVENT" \
        "${jq_repo_arg[@]}" \
        "${jq_plan_arg[@]}" \
        --arg snapshot "$snapshot_id" \
        --arg error    "$ERROR_FIELD" \
        "${jq_new_arg[@]}" \
        "${jq_changed_arg[@]}" \
        "${jq_unmod_files_arg[@]}" \
        "${jq_dirs_arg[@]}" \
        "${jq_data_added_arg[@]}" \
        "${jq_files_arg[@]}" \
        "${jq_bytes_arg[@]}" \
        "${jq_duration_arg[@]}" \
        '
        {
          task:   $task,
          time:   $time,
          event:  $event,
          repo:   (if $repo == "" then null else $repo end),
          plan:   (if $plan == "" then null else $plan end),
          snapshot: $snapshot,
          snapshot_stats: {
            message_type:     "summary",
            error:            (if $error == "" then null else ($error | gsub("^\"|\"$"; "")) end),
            during:           "",                     # left empty per example
            item:             "",
            files_new:        ($files_new),           # CREATED files
            files_changed:    ($files_changed),       # DELETED + TRANSFERRED
            files_unmodified: ($files_unmodified),    # total_files - created - transferred
            dirs_new:         0,
            dirs_changed:     0,
            dirs_unmodified:  ($dirs_val),            # total_dirs
            data_blobs:       0,
            tree_blobs:       0,
            data_added:       ($data_added),          # bytes actually sent by rsync
            total_files_processed: ($files_val),      # total_files
            total_bytes_processed: ($bytes_val),      # total_bytes
            total_duration:        ($dur_val),        # duration_sec
            snapshot_id:     $snapshot,
            percent_done:    0,
            total_files:     0,
            files_done:      0,
            total_bytes:     0,
            bytes_done:      0,
            current_files:   null
          }
        }
        '
    )
    
    log_info "Posting JSON report to $REPORT_URL"
    if ! curl -fsS -X POST "$REPORT_URL" \
         -H 'Content-Type: application/json' \
         -H "X-API-Key: $BACKREST_API_KEY" \
         -d "$payload"; then
      fail "Failed to POST to REPORT_URL"
    fi
  fi

done
