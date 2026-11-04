#!/bin/sh
# Sample the real Unity game process (comm = VampireSurvivor) + GPU.
out=/tmp/perf-new.log
: > "$out"
pids=""
prev_ticks=0
prev_t=0
while :; do
  pid=$(pgrep -x VampireSurvivor | head -1)
  if [ -n "$pid" ]; then
    ticks=$(awk "{print \$14 + \$15}" /proc/$pid/stat 2>/dev/null)
    t=$(date +%s)
    rss=$(awk "/VmRSS/{print \$2}" /proc/$pid/status 2>/dev/null)
    thr=$(awk "/Threads/{print \$2}" /proc/$pid/status 2>/dev/null)
    if [ -n "$ticks" ] && [ "$prev_t" -gt 0 ]; then
      dt=$((t - prev_t)); di=$((ticks - prev_ticks))
      cpu=$(( di / (dt>0?dt:1) ))
      printf "%s gamecpu=%s%% rss=%skB thr=%s\n" "$(date +%T)" "$cpu" "$rss" "$thr" >> "$out"
    fi
    [ -n "$ticks" ] && prev_ticks=$ticks
    prev_t=$t
    radeontop -d - -l 1 2>/dev/null | grep "bus 00" >> "$out"
    sleep 4
  else
    prev_t=0
    sleep 2
  fi
done
