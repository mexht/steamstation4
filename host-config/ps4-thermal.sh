#!/bin/sh
# Read-only thermal / fan probe for PS4 Linux.
# Run as root on the console (or pipe over ssh).
echo "== kernel =="
uname -r

echo
echo "== hwmon devices =="
for h in /sys/class/hwmon/hwmon*; do
  [ -e "$h/name" ] || continue
  echo "-- $h  name=$(cat "$h/name" 2>/dev/null)"
  for f in "$h"/temp*_input "$h"/temp*_label "$h"/temp*_max \
           "$h"/fan*_input "$h"/fan*_label "$h"/pwm* \
           "$h"/fan_target_temperature; do
    [ -e "$f" ] || continue
    printf '   %-24s = %s\n' "$(basename "$f")" "$(cat "$f" 2>/dev/null)"
  done
done

echo
echo "== thermal zones =="
for z in /sys/class/thermal/thermal_zone*; do
  [ -e "$z/type" ] || continue
  echo "$z type=$(cat "$z/type" 2>/dev/null) temp=$(cat "$z/temp" 2>/dev/null)"
done
for c in /sys/class/thermal/cooling_device*; do
  [ -e "$c/type" ] || continue
  echo "$c type=$(cat "$c/type" 2>/dev/null) cur=$(cat "$c/cur_state" 2>/dev/null) max=$(cat "$c/max_state" 2>/dev/null)"
done

echo
echo "== ICC =="
ls -l /dev/icc 2>/dev/null || echo "no /dev/icc node"
grep -i icc /proc/devices 2>/dev/null || true
ls /sys/class/icc 2>/dev/null || true

echo
echo "== relevant modules (built-in ones will not appear) =="
lsmod | grep -iE 'ps4|k10temp|fam15h|amdgpu' || true

echo
echo "== kernel config =="
zcat /proc/config.gz 2>/dev/null | grep -E \
  'CONFIG_HWMON|CONFIG_SENSORS_K10TEMP|CONFIG_SENSORS_FAM15H_POWER|CONFIG_PS4|CONFIG_THERMAL' \
  || echo "no /proc/config.gz"

echo
echo "== fan threshold write test (writes the current value back) =="
for h in /sys/class/hwmon/hwmon*; do
  f="$h/fan_target_temperature"
  [ -e "$f" ] || continue
  cur=$(cat "$f" 2>/dev/null)
  echo "current: $cur"
  if echo "$cur" > "$f" 2>/dev/null; then
    echo "write-back: ok -> $(cat "$f" 2>/dev/null)"
  else
    echo "write-back: FAILED (read-only or permission)"
  fi
done
