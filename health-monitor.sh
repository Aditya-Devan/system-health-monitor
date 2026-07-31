#!/bin/bash
#
# health-monitor.sh — System Health Monitor (Capstone)
# Collects CPU/memory/disk, compares to thresholds, logs, alerts,
# and prunes its own old logs. Schedule via cron.
#
set -euo pipefail

# ---------------- CONFIG (tune these) ----------------
# a NEW file each day, e.g. health-2026-07-18.log
LOGFILE="${LOGFILE:-$HOME/logs/health-$(date +%F).log}"
CPU_MAX="${CPU_MAX:-10}"
MEM_MAX="${MEM_MAX:-10}"
DISK_MAX="${DISK_MAX:-10}"
RETAIN_DAYS="${RETAIN_DAYS:-7}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"   # optional; empty = skip webhook

# ---------------- SAFETY: cleanup on exit ----------------
trap 'rc=$?; [ $rc -ne 0 ] && log ERROR "monitor exited with code $rc"; exit $rc' EXIT

# ---------------- LOGGING ----------------
# make sure the log directory exists before we write to it
mkdir -p "$(dirname "$LOGFILE")"

log() {
    local level="$1"; shift
    echo "$(date '+%F %T') [$level] $*" | tee -a "$LOGFILE"
}

# ---------------- ALERTING ----------------
alert() {
    local msg="$1"
    log ERROR "ALERT: $msg"
    # optional Slack webhook (only if a URL is configured and curl exists)
    if [ -n "$SLACK_WEBHOOK_URL" ] && command -v curl >/dev/null; then
        curl -s -X POST -H 'Content-type: application/json' \
             -d "{\"text\":\"[$(hostname)] $msg\"}" "$SLACK_WEBHOOK_URL" >/dev/null || \
             log WARN "failed to post to Slack webhook"
    fi
}

# ---------------- ONE REUSABLE CHECKER ----------------
check() {                       # $1=name  $2=value  $3=limit
    local name="$1" value="$2" limit="$3"
    if [ "$value" -gt "$limit" ]; then
        alert "$name at ${value}% (limit ${limit}%)"
    else
        log INFO "$name ok at ${value}%"
    fi
}

# ---------------- COLLECT METRICS ----------------
collect() {
    DISK=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    local load cores
    if [ "$(uname -s)" = "Darwin" ]; then
        # macOS
        # Memory used% from vm_stat page counts
        MEM=$(vm_stat | awk '
            /page size of/ {ps=$8}
            /Pages free/ {free=$3}
            /Pages active/ {active=$3}
            /Pages inactive/ {inactive=$3}
            /Pages speculative/ {spec=$3}
            /Pages wired down/ {wired=$4}
            END {
                gsub(/\./,"",free); gsub(/\./,"",active);
                gsub(/\./,"",inactive); gsub(/\./,"",spec); gsub(/\./,"",wired);
                used=active+wired; total=free+active+inactive+spec+wired;
                if (total>0) printf "%.0f", used/total*100; else print 0
            }')
        # 1-min load average via sysctl, cores via hw.ncpu
        load=$(sysctl -n vm.loadavg | awk '{print $2}')
        cores=$(sysctl -n hw.ncpu)
    else
        # Linux
        MEM=$(free | awk '/Mem/ {printf "%.0f", $3/$2*100}')
        load=$(awk '{print $1}' /proc/loadavg)
        cores=$(nproc)
    fi

    # CPU% from 1-min load average / cores (robust, no top dependency)
    CPU=$(awk -v l="$load" -v c="$cores" 'BEGIN {printf "%.0f", (l/c)*100}')
}

# ---------------- FILESYSTEM AUTOMATION: prune old logs ----------------
prune_logs() {
    local dir; dir=$(dirname "$LOGFILE")
    find "$dir" -maxdepth 1 -name '*.log' -mtime +"$RETAIN_DAYS" -delete 2>/dev/null || true
    log INFO "pruned logs older than ${RETAIN_DAYS} days in $dir"
}

# ---------------- MAIN ----------------

main() {
    log INFO "----- health check start -----"
    collect
    check CPU  "$CPU"  "$CPU_MAX"
    check MEM  "$MEM"  "$MEM_MAX"
    check DISK "$DISK" "$DISK_MAX"
    prune_logs
    log INFO "----- health check done -----"
}

main "$@"
