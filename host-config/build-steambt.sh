#!/bin/sh
# Build the 32-bit Steam Bluetooth gate shim and install it on the console.
#
# Run on any x86_64 Linux with gcc (+ 32-bit support) or binutils.
# The PS4 side needs the file at /usr/local/lib/libsteambt.so and
# LD_PRELOAD=/usr/local/lib/libsteambt.so in /usr/local/bin/ps4-session.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${1:-$here/libsteambt.so}"

gcc -m32 -shared -fPIC -O2 -o "$out" "$here/steambt-shim.c"

echo "built: $out"
echo "install:"
echo "  scp $out root@<ps4>:/usr/local/lib/libsteambt.so"
echo "  # ps4-session: export LD_PRELOAD=/usr/local/lib/libsteambt.so"
echo "  # restart the X session (or reboot) so Steam picks it up"
