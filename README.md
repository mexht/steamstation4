# SteamStation4

**Boot Linux on a PlayStation 4 (firmware 14.00) from Orbis in one action**, then
run Steam Big Picture with the GPU, session and Bluetooth fixes that make the
desktop usable.

Validated on a PS4 Slim **CUH-2016A** (Belize southbridge), retail firmware
**14.00**, GoldHEN **2.4b18.13**. The underlying loader also carries offset
tables for older firmware; this repository targets 14.00.

> [!WARNING]
> This is homebrew that runs with kernel privileges. A bad payload can hang the
> console, and modifying a console can lead to data loss, instability or a
> service ban. Use it on hardware you own and accept the risk. Not affiliated
> with Sony or Steam.

---

## What it does

- Installs a **`kern_reboot` hook** and triggers the hand-off from kernel
  context, so the switch to Linux is a single action instead of a manual
  reboot/power cycle.
- Loads `bzImage`, `initramfs.cpio.gz` and `bootargs.txt` from USB or the
  internal disk and kexecs into the Linux kernel.
- Ships the kernel/initramfs/boot args that were actually used for the validated
  boot, plus a rebuilt payload whose embedded 16,040-byte kexec blob is
  **byte-identical** to the hardware-proven one.
- Includes host-side configuration for:
  - a clean 1080p Big Picture session (**no `AMD_DEBUG` workaround**),
  - a **patched Mesa** that identifies the PS4 GPU as Liverpool instead of
    Kaveri (fixes tiling/fast-clear corruption),
  - **Bluetooth HID bonding**, so a DualShock 4 works inside Big Picture.

## Repository layout

```
PS4-14.00-linux/
|-- boot/                     boot files for the FAT32 stick / internal boot dir
|   |-- bzImage               Linux 7.1.7 "Strawberry General" (20,415,488 B)
|   |-- initramfs.cpio.gz     better-initramfs with PS4 helpers (10,024,281 B)
|   `-- bootargs.txt          kernel command line (edit for your network)
|-- payloads/
|   |-- linux-autoboot.bin    raw payload, rebuilt here (proven on hardware)
|   |-- linux-autoboot.elf    same code for GoldHEN PayLoader
|   |-- linux-autoboot-shipped.bin   build that was first proven on hardware
|   |-- linux-autoboot-shipped.elf   same build, PayLoader form
|   `-- kexec-1400-shipped.bin       the 16,040-byte 14.00 kexec blob
|-- host-config/              Linux-side session, Mesa and Bluetooth setup
|-- patches/                  the 14.00 hand-off changes, as git patches
|-- prebuilt/                 ready-to-install patched Mesa packages (optional)
|-- build.sh                  rebuilds both payloads from source
`-- README.md
```

`ps4-linux-loader/` is an upstream checkout used only for building. It is
deliberately **not** part of this repository.

## Requirements

- PS4 on firmware **14.00** with GoldHEN (or ps4-hen) running.
- A way to send a payload:
  - raw `.bin` over HTTP to port **9090** (e.g. GoldHEN's binloader), or
  - `.elf` through GoldHEN **PayLoader** from `/data/payloads` or
    `/usb*/payloads`.
- A Linux root filesystem on the console or on USB. The included initramfs
  expects a filesystem labelled **`psxitarch`** (`root=LABEL=psxitarch`).
- For building: `gcc`, `make`, `ld`, `objcopy`, `python3`, and `yasm` 1.3.0.

## Quick start

### 1. Put the boot files somewhere the payload can read

The payload searches these paths in order:

```
/mnt/usb0/bzImage
/mnt/usb1/bzImage
/data/linux/boot/bzImage
/user/system/boot/bzImage
```

and the same for `initramfs.cpio.gz` and `bootargs.txt`. So either copy
`boot/` to the root of a FAT32 USB stick, or to `/data/linux/boot/` on the
console (no USB needed).

Edit `bootargs.txt` if you need a static IP or a `netconsole` target; the
shipped one is intentionally generic. `vram.txt` is optional: it sets the VRAM
size in MB (default 1024, clamped by the build).

The initramfs can install a distro from a `distro.tar.*` / `psxitarch.tar.*`
on the boot medium if no Linux rootfs is present yet. See the upstream
[PS4 Linux tutorial](https://dionkill.github.io/ps4-linux-tutorial/) for the
rootfs side.

### 2. Send the payload

| target | file | notes |
|---|---|---|
| HTTP `:9090` | `payloads/linux-autoboot.bin` | raw `.bin` only |
| GoldHEN PayLoader | `payloads/linux-autoboot.elf` | scans `/data/payloads` and `/usb*/payloads` |

Send it **once**, after GoldHEN is healthy. Do not send it in the same second
the jailbreak chain returns.

### 3. Boot

The payload loads the kernel files, tears down Orbis and kexecs. On this
hardware Linux comes up in about two seconds after the trigger. The console
keeps HDMI output; the Linux rootfs then brings up the desktop/Steam.

### 4. Return to Orbis

```sh
sync; sync; systemctl poweroff -f
```

Plain `reboot` and `shutdown` do not come back cleanly on this port; use
`poweroff -f`. The desktop config also provides a Steam shortcut for this.

## Payload hashes

Compare before deploying. `-shipped` means the build that was first proven on
the console; the plain names are what `build.sh` produces.

| file | SHA256 (prefix) | state |
|---|---|---|
| `linux-autoboot-shipped.bin` | `f301181d...d7d25a` | proven on hardware |
| `linux-autoboot-shipped.elf` | `9159f8d1...b9f3e3` | PayLoader path not re-tested |
| `linux-autoboot.bin` | `2b159783...adea5c6` | rebuilt, proven 2026-11-04 |
| `linux-autoboot.elf` | `d7ca0b92...25c8e396` | same embedded blob |
| `kexec-1400-shipped.bin` | `961037b6...cc5f05` | 16,040 B, byte-identical in all payloads |

Sizes: shipped `.bin` 329,096 B; rebuilt `.bin` 333,188 B. The difference is the
diagnostic `printf` calls described below, not a functional change.

## Build from source

The loader itself is not vendored here. Clone upstream and apply the two
patches from `patches/`:

```sh
git clone https://github.com/ps4-linux/ps4-linux-loader.git
git -C ps4-linux-loader am "$PWD"/patches/*.patch
./build.sh
```

Upstream `master` is the base the patches were generated against (commit
`d0f4d4c`, "Add PS4 14.00 support"). `patches/README.md` describes each patch.

`build.sh` builds the libc stubs, every firmware's kexec blob, the 14.00 blob
with `-DHOOK_KERN_REBOOT -DAUTO_TRIGGER=0x0`, and the userland payload with
`-DNO_REBOOT_WATCHDOG`, then copies `.elf`/`.bin` into `payloads/`.

`yasm` is required. If your distro has no package, build 1.3.0 with:

```sh
curl -LO https://github.com/yasm/yasm/releases/download/v1.3.0/yasm-1.3.0.tar.gz
tar xzf yasm-1.3.0.tar.gz && cd yasm-1.3.0
./configure --prefix=/tmp/yasm CFLAGS="-O2 -std=gnu17" && make -j"$(nproc)"
export PATH="/tmp/yasm/bin:$PATH"
```

`build.sh` also looks in a local `tools/` directory first if you prefer to drop
a yasm binary there.

## How the hand-off works

On 14.00, `sys_reboot()` never reaches `icc_query_nowait`; only the
shell-orchestrated shutdown path does. The working hook is therefore
**`kern_reboot`**, which is on every reboot path.

1. `hook_kern_reboot()` performs the same teardown as the older ICC hook
   (`wlanbt(0x2)` -> `fix_acpi_tables` -> `smp_rendezvous(cpu_quiesce_gate)`)
   and never returns.
2. `kexec.c` installs that hook (`-DHOOK_KERN_REBOOT`) and, if the install
   succeeded, calls `kern.kern_reboot(AUTO_TRIGGER)` from kernel context inside
   `sys_kexec` (`-DAUTO_TRIGGER=0x0`). A failed install only prints
   `AUTO_TRIGGER: skipped`; it never shuts the console down.
3. `main-aio.c` writes `tag=value` lines to `/mnt/usb0/ps4linux-diag.txt`
   (fallback `/data/linux/ps4linux-diag.txt`) and **fsyncs each line**, so a
   freeze leaves a post-mortem.
4. `-DNO_REBOOT_WATCHDOG` removes the legacy `reboot_thread`, which runs the
   `evf_cancel(0x4000)` + `kill(1, SIGUSR1)` trigger that wedges 14.00 one
   second after arming.

`klog` can go dark immediately after `hook_kern_reboot called` because
`wlanbt(0x2)` takes the network down. A missing line there is **not** evidence
of a hang; use the diag file or a netconsole/serial collector instead.

## Host configuration (inside Linux)

See **[`host-config/README.md`](host-config/README.md)** for the full details.

- **Session**: `/usr/local/bin/ps4-session` starts the 1080p desktop and Steam
  Big Picture, disables X blanking (`xset s off -dpms`) and waits for BlueZ
  before Steam starts.
- **GPU**: stock Mesa mis-identifies the PS4 GPU and corrupts tiling/fast-clear.
  `host-config/mesa-ps4/` builds Mesa 26.2.6 with the PS4 patch; with it
  installed, `AMD_DEBUG` is not needed. Prebuilt Arch packages are in
  `prebuilt/` (unsigned - see `prebuilt/README.md`).
- **Bluetooth**: the adapter must be `bondable`, otherwise BlueZ stores no link
  key and rejects the HIDP connection (controller "connected" but dead).
  `host-config/bt-bondable.service` makes that setting persistent.
- **Helpers**: `bt-pair.sh`, `perf-watch.sh`, `ps4-gfx-rollback.sh`,
  `ps4-thermal.sh`.

## Operational rules

- **Never probe `:9090`.** Every accepted TCP connection is treated as a
  payload; a connect-and-close is an invalid payload and spends that boot.
- **One Linux payload per boot.** A second payload overwrites the installed
  hooks.
- **Do not chain jailbreak -> Linux.** Let the chain finish and exit 0 first.
- **Do not post while SceShellCore is restarting** (immediately after the chain
  returns, or after aborted boots).
- **Do not use `reboot`/plain `shutdown`.** `sync; sync; poweroff -f`.
- Launch games from Big Picture. `steam -applaunch` from a remote shell can
  wedge Big Picture.

## Troubleshooting

| symptom | check |
|---|---|
| payload runs but nothing happens | `ps4linux-diag.txt` (`/mnt/usb0/`, `/data/linux/`) for the last stage reached |
| klog stops after `hook_kern_reboot called` | expected; `wlanbt(0x2)` kills the network. Check HDMI/netconsole |
| `AIO: Unsupported firmware version` | the offset table has no entry for the detected firmware |
| `Failed to load file: bzImage` | boot files are not in `/mnt/usb*` or `/data/linux/boot/` |
| no video | check `bootargs.txt` (`video=HDMI-A-1:...`) and the kernel's `amdgpu.dpm=0` |
| black screen after idle | X blanking; ensure `xset s off -dpms` ran, and disable the Big Picture screensaver |
| controller connected but dead | see the Bluetooth section: adapter must be bondable |

## Provenance and credits

- [`ps4-linux-loader`](https://github.com/ps4-linux/ps4-linux-loader) by
  shuffle2, marcan and contributors - kexec implementation, firmware offset
  tables and the original loader.
- [GoldHEN](https://github.com/GoldHEN/GoldHEN) and ps4-hen - payload hosts.
- [`fail0verflow/ps4-linux`](https://github.com/fail0verflow/ps4-linux) and the
  wider PS4 Linux community - kernel, ICC/southbridge support and the
  `ps4-fan`/ICC interfaces.
- [better-initramfs](https://bitbucket.org/piotrkarbowski/better-initramfs) -
  initramfs framework.
- The PS4 Mesa patch set (`ps4-mesa*`), rebased here for Mesa 26.2.6.

The hardware-proven payloads in `payloads/` are kept alongside the rebuild so
the hand-off remains reproducible even if the build environment changes.

## License

There is no top-level `LICENSE` file yet. The loader code this payload is
derived from is BSD-2-Clause (see the upstream repository and the file headers);
`bzImage`, `initramfs.cpio.gz` and the Mesa packages are third-party works and
remain under their own licenses. Add a project license before redistributing
commercially.
