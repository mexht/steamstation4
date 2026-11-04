#!/bin/sh
log=/tmp/bt-pair.log
: > "$log"
echo "scan start $(date +%T)" >> "$log"
bluetoothctl --timeout 240 scan on >/tmp/bt-scan.log 2>&1 &
scanpid=$!
mac=""
i=0
while [ $i -lt 120 ]; do
  mac=$(bluetoothctl devices 2>/dev/null | awk "/Wireless Controller|Sony|054C|DualShock/ {print \$2; exit}")
  [ -n "$mac" ] && break
  sleep 2
  i=$((i+1))
done
echo "found mac=[$mac] after $((i*2))s" >> "$log"
kill $scanpid 2>/dev/null
pkill -f "bluetoothctl --timeout 240 scan" 2>/dev/null
if [ -n "$mac" ]; then
  bluetoothctl trust "$mac" >> "$log" 2>&1
  bluetoothctl pair "$mac" >> "$log" 2>&1
  sleep 3
  bluetoothctl connect "$mac" >> "$log" 2>&1
  sleep 5
  bluetoothctl info "$mac" >> "$log" 2>&1
  echo "--- hid devices ---" >> "$log"
  ls /sys/bus/hid/devices/ >> "$log" 2>&1
  echo "--- input nodes ---" >> "$log"
  ls -l /dev/input/by-id/ >> "$log" 2>&1
  echo "--- evtest list ---" >> "$log"
  evtest 2>&1 | head -20 >> "$log"
  echo "--- bluez log ---" >> "$log"
  journalctl -u bluetooth --since "-2 min" --no-pager 2>/dev/null | grep -iE "hidp|input|bond" | tail -10 >> "$log"
else
  echo "no controller found" >> "$log"
fi
echo "done $(date +%T)" >> "$log"
