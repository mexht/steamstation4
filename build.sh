#!/bin/sh
# Build the PS4 14.00 Linux hand-off payload (raw .bin + PayLoader .elf).
#
# Needs: gcc, make, ld, objcopy, yasm, python3.
# yasm 1.3.0 does not compile with GCC 15 defaults (C23 makes "bool" a
# keyword in libyasm/bitvect.h): build it with CFLAGS="-O2 -std=gnu17".
set -eu

TOP=$(cd "$(dirname "$0")" && pwd)
# vendored yasm 1.3.0 (no distro package on this box)
PATH="$TOP/tools:$PATH"; export PATH
cd "$TOP/ps4-linux-loader/linux"

# 1. libc stubs (yasm)
make -C ../lib

# 2. every firmware's kexec blob: main-aio.c .incbin's all of them
make kexec-bins

# 3. rebuild 14.00 with the hand-off flags
make -C ps4-kexec-common FW_DEFINE=PS4_14_00 \
     BUILD_DIR="$(pwd)/kexec-build/1400" \
     EXTRA_CFLAGS="-DHOOK_KERN_REBOOT -DAUTO_TRIGGER=0x0"

# 4. payload: no legacy reboot watchdog (it fires the broken evf trigger)
mkdir -p payloads
gcc -isystem ../freebsd-headers -nostdinc -nostdlib -fno-stack-protector \
    -static -fPIE -ffreestanding ../lib/lib.a \
    -DVRAM_MB_DEFAULT=1024 -DVRAM_MB_MIN=32 -DVRAM_MB_MAX=4096 \
    -DNO_REBOOT_WATCHDOG main-aio.c fw_detect.c \
    -Wl,-gc-sections -o payloads/linux-autoboot.elf
objcopy payloads/linux-autoboot.elf \
    --only-section .text --only-section .data --only-section .bss \
    --only-section .rodata -O binary payloads/linux-autoboot.bin

mkdir -p "$TOP/payloads"
cp payloads/linux-autoboot.elf payloads/linux-autoboot.bin "$TOP/payloads/"
ls -l "$TOP/payloads/linux-autoboot.elf" "$TOP/payloads/linux-autoboot.bin"
