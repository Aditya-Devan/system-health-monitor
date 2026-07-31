# System Health Monitor

A small, production-grade Bash script that monitors **CPU, memory, and disk** usage,
compares them against configurable thresholds, **logs** every check with timestamps,
**alerts** when a threshold is breached, and **cleans up** its own old logs.
Designed to run unattended on a schedule via `cron`.

> Built as the capstone for a Linux & Shell Scripting course — it exercises
> Linux fundamentals, text processing, scripting, and defensive/production techniques.

## Features

- Collects CPU (from load average), memory %, and disk % usage
- Cross-platform metric collection — works on both **Linux** and **macOS**
- Configurable thresholds via environment variables
- **One log file per day** (`health-YYYY-MM-DD.log`); the log directory is created automatically
- Timestamped, leveled logging (`INFO` / `WARN` / `ERROR`) to a logfile and screen
- Optional Slack alerting via webhook
- Automatic cleanup of logs older than N days
- Defensive scripting: `set -euo pipefail`, `trap` cleanup, input-safe quoting

## Requirements

- Bash 4+
- Standard coreutils (`df`, `awk`, `tr`, `find`)
- **Linux:** `free`, `nproc`, `/proc/loadavg`
- **macOS:** `vm_stat`, `sysctl` (used automatically when running on Darwin)
- Optional: `curl` (only if using Slack alerts)

## Usage

```bash
# make it executable (once)
chmod +x health-monitor.sh

# run with defaults (thresholds = 80%, log to ~/logs/health-YYYY-MM-DD.log)
./health-monitor.sh

# override any setting via environment variables
LOGFILE=/var/log/health.log DISK_MAX=90 MEM_MAX=85 ./health-monitor.sh
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `LOGFILE` | `$HOME/logs/health-$(date +%F).log` | Where results are logged; a new file is created each day |
| `CPU_MAX` | `80` | CPU % threshold |
| `MEM_MAX` | `80` | Memory % threshold |
| `DISK_MAX` | `80` | Disk % threshold |
| `RETAIN_DAYS` | `7` | Delete `*.log` older than this |
| `SLACK_WEBHOOK_URL` | *(empty)* | If set, alerts POST here |

## Scheduling with cron

Run every 5 minutes and capture all output:

```bash
crontab -e
# add:
*/5 * * * * /absolute/path/health-monitor.sh >> /var/log/health-cron.log 2>&1
```

Verify with `crontab -l`.

## Example output

```
2026-07-11 16:36:37 [INFO] ----- health check start -----
2026-07-11 16:36:37 [INFO] CPU ok at 5%
2026-07-11 16:36:37 [INFO] MEM ok at 5%
2026-07-11 16:36:37 [ERROR] ALERT: DISK at 21% (limit 10%)
2026-07-11 16:36:37 [INFO] ----- health check done -----
```

## How it works

1. **Config** block at the top — everything tunable, overridable via env vars.
   `LOGFILE` embeds today's date, so each day gets its own file and the log
   directory is created automatically on first run.
2. `collect()` reads each metric and parses a clean number. It detects the OS
   (`uname -s`) and uses `free`/`/proc/loadavg`/`nproc` on Linux or
   `vm_stat`/`sysctl` on macOS.
3. One reusable `check()` compares a value against its limit and logs/alerts.
4. `prune_logs()` deletes logfiles older than `RETAIN_DAYS`. Because each day
   writes to a new dated file, older files age out and get removed cleanly.
5. `main()` orchestrates the run; a `trap` logs any abnormal exit.

## Possible extensions

- Read config from a file instead of env vars
- Add more metrics (load average, inode usage, specific processes)
- A `--dry-run` flag and a `--summary` report mode
- PagerDuty / email alerting alongside Slack

## License

MIT
