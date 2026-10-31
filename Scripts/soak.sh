#!/bin/zsh
# Soak test: run the built app for N hours and sample its resource usage.
#
# usage: Scripts/soak.sh <path/to/mac-stats.app> [hours=12] [interval_sec=300]
#        Scripts/soak.sh --pid <pid>               [hours=12] [interval_sec=300]
#
# With --pid the script samples an already running instance (for example the
# one launched from /Applications) instead of starting its own, and leaves it
# running at the end. stdout.log stays empty in that mode.
#
# Writes to ./soak-<timestamp>/:
#   samples.csv   one row per interval: rss, vsz, cpu time, threads, fds, children, mach ports
#   stdout.log    everything the app printed (should stay near-empty)
#   leaks.txt     output of `leaks` against the live process at the end
#   summary.txt   pass/fail against the acceptance thresholds
#
# Acceptance (summary.txt): rss drift < 5 MB between the 10-minute mark and the end,
# zero child processes ever observed, zero lines matching /error/i in stdout.log.

set -u
attach=0
if [[ "${1:-}" == "--pid" ]]; then
  attach=1
  pid=${2:?pid of a running mac-stats}
  kill -0 "$pid" 2>/dev/null || { echo "no such process: $pid"; exit 1; }
  shift 2
else
  app=${1:?path to mac-stats.app}
  bin="$app/Contents/MacOS/mac-stats"
  [[ -x "$bin" ]] || { echo "not executable: $bin"; exit 1; }
  shift
fi
hours=${1:-12}
interval=${2:-300}

out="soak-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
samples="$out/samples.csv"
log="$out/stdout.log"

if (( attach )); then
  : > "$log"
  echo "attached to pid=$pid, sampling every ${interval}s for ${hours}h into $out"
else
  "$bin" > "$log" 2>&1 &
  pid=$!
  echo "started pid=$pid, sampling every ${interval}s for ${hours}h into $out"
fi
sleep 10

echo "ts,rss_kb,vsz_kb,cpu_time,threads,fds,children,ports" > "$samples"
total=$(( hours * 3600 / interval ))
for i in $(seq 1 $total); do
  if ! kill -0 $pid 2>/dev/null; then echo "$(date +%H:%M:%S),DEAD" >> "$samples"; break; fi
  rss=$(ps -o rss= -p $pid | tr -d ' ')
  vsz=$(ps -o vsz= -p $pid | tr -d ' ')
  cpu=$(ps -o time= -p $pid | tr -d ' ')
  thr=$(ps -M -p $pid | tail -n +2 | wc -l | tr -d ' ')
  fds=$(lsof -p $pid 2>/dev/null | wc -l | tr -d ' ')
  kids=$(pgrep -P $pid | wc -l | tr -d ' ')
  ports=$(lsmp -p $pid 2>/dev/null | grep -c '^0x'); ports=${ports:-0}
  echo "$(date +%H:%M:%S),$rss,$vsz,$cpu,$thr,$fds,$kids,$ports" >> "$samples"
  sleep $interval
done

if kill -0 $pid 2>/dev/null; then
  leaks $pid > "$out/leaks.txt" 2>&1 || true
  (( attach )) || kill $pid
fi

# ---- summary ----
{
  echo "samples: $(($(wc -l < "$samples") - 1))"
  first=$(awk -F, 'NR>1 && $2 != "DEAD" {c++; if (c==2) {print $2; exit}}' "$samples")
  last=$(awk -F, '$2 != "DEAD" {v=$2} END {print v}' "$samples")
  drift_kb=$(( ${last:-0} - ${first:-0} ))
  echo "rss first(after 10 min)=${first:-?} kB  last=${last:-?} kB  drift=${drift_kb} kB"
  maxkids=$(awk -F, 'NR>1 && $7+0 > m {m=$7+0} END {print m+0}' "$samples")
  echo "max child processes observed: $maxkids"
  errs=$(grep -ci "error" "$log" || true)
  echo "stdout lines: $(wc -l < "$log")  error lines: $errs"
  applog="$HOME/Library/Logs/mac-stats/stats.log"
  if [[ -f "$applog" ]]; then
    since=$(grep -n '^==== ' "$applog" | tail -1 | cut -d: -f1)
    tail -n +"${since:-1}" "$applog" > "$out/stats.log"
    echo "app log lines this session: $(wc -l < "$out/stats.log")  ERR lines: $(grep -c ' ERR ' "$out/stats.log" || true)"
    grep 'health' "$out/stats.log" | sed -n '1p;$p'
  fi
  grep -E "leaks for|LEAK:" "$out/leaks.txt" 2>/dev/null | head -3
  pass=1
  (( drift_kb < 5120 )) || { echo "FAIL: rss drift >= 5 MB"; pass=0; }
  (( maxkids == 0 )) || { echo "FAIL: child processes spawned"; pass=0; }
  (( errs == 0 )) || { echo "FAIL: error lines in stdout"; pass=0; }
  (( pass )) && echo "PASS"
} | tee "$out/summary.txt"
