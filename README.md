# PS4 14.00 — Linux hand-off (payload + boot medium)

Everything needed to rebuild, deploy and boot the 14.00 Linux hand-off payload.
Console: PS4 Slim **CUH-2016A** (Belize), retail **14.00**, GoldHEN **2.4b18.13**.

Start with `../PS4-LINUX-14.00-REPORT.md` (technical) and
`../PROGRESS-2026-11-03.md` (session log / open items).

## Layout

```
PS4-14.00-linux/
├── build.sh                     rebuild both payloads from source
├── ps4-linux-loader/            upstream clone + the 14.00 hand-off patches
├── tools/yasm                   yasm 1.3.0 built for this box (build needs it)
├── host-config/                 Linux-side session/GPU config (see host-config/README.md)
├── payloads/
│   ├── linux-autoboot.bin       rebuilt here (hardware-validated 2026-11-04)
│   ├── linux-autoboot.elf       rebuilt here (same code, PayLoader path untested)
│   ├── linux-autoboot-shipped.bin  the build that booted Linux on hardware
│   └── linux-autoboot-shipped.elf  same build, PayLoader .elf form
└── boot/                        contents of the FAT32 boot stick
    ├── bzImage                  Linux 7.1.7 "Strawberry General" (20,415,488 B)
    ├── initramfs.cpio.gz        better-initramfs with PS4 helpers (10,024,281 B)
    └── bootargs.txt             kernel cmdline (root=LABEL=psxitarch)
```

`-shipped` = proven on the console (2026-11-03/04). The plain names are what
`build.sh` produces from the patched tree. Compare hashes before deploying:

| file | sha256 | state |
|---|---|---|
| `linux-autoboot-shipped.bin` | `f301181d…d7d25a` | proven 4× on 2026-11-04 over HTTP 200 (`:9090`) → Linux in ~2 s |
| `linux-autoboot-shipped.elf` | `9159f8d1…b9f3e3` | on console, PayLoader path not re-tested |
| `linux-autoboot.bin` | `2b159783…adea5c6` | **rebuilt and proven 2026-11-04 20:07** → Linux up in ~2 s |
| `linux-autoboot.elf` | `d7ca0b92…25c8e396` | rebuild, same embedded blob; PayLoader path untested |

Sizes: shipped `.bin` 329,096 B, rebuild `.bin` 333,188 B. The 16,040-byte
`kexec_1400` blob embedded in each is **byte-identical**: `961037b6…cc5f05`
(also kept standalone as `kexec-1400-shipped.bin`).

### Rebuild vs shipped: resolved (2026-11-04)

The reconstruction is complete. The one difference that mattered was the shipped
blob's diagnostics: our first rebuild omitted seven `kern.printf` calls that the
shipped build carries (`DIAG alloc %zu: spins=…`, `DIAG copyin image/initramfs`,
`DIAG gpu stage start/done`, `DIAG hook: wlanbt disabled`,
`DIAG icc_query_nowait=%p`). Without them the payload froze after `AUTO_TRIGGER`
(2/2 runs, at different points), with them the rebuilt blob compiles to the exact
shipped 16,040-byte image and boots.

Bisect that isolated it:

- shipped userland + our old blob → froze (so the userland `netlog` was innocent);
- shipped userland + shipped blob → booted;
- our userland + rebuilt blob with the printfs → booted (20:07 run).

They are effectively timing: the freeze point moved between runs (inside `wlanbt`
once, after `DSDT` once), and `fix_acpi_tables`/`cpu_quiesce_gate`/`jmp_to_linux`
were already instruction-identical to the shipped blob. Keep the prints.

`klog` can go dark right after `hook_kern_reboot called` because `wlanbt(0x2)` takes
the network down; a missing line there is not evidence of a hang. The Pi's
netconsole (`~/ps4-linux/netconsole.log`) is the reliable "did Linux boot" signal.

## What the patches do

Upstream already has the 14.00 offset table (`magic.h`: `kern_off_icc_query_nowait 0x448630`,
`kern_off_kern_reboot 0x3A2850`) and resolves `kern.kern_reboot`. The changes on top:

1. **`ps4-kexec-common/linux_boot.c`** — `hook_kern_reboot()`: same teardown as the ICC hook
   (`wlanbt(0x2)` → `fix_acpi_tables` → `smp_rendezvous(cpu_quiesce_gate)`), never returns.
   `kern_reboot_hooked` records whether the install worked.
2. **`ps4-kexec-common/linux_boot.h`** — declares both.
3. **`ps4-kexec-common/kexec.c`** — after the ICC hook, install the `kern_reboot` hook
   (`-DHOOK_KERN_REBOOT`) and, if it took, call `kern.kern_reboot(AUTO_TRIGGER)` from kernel
   context inside `sys_kexec` (`-DAUTO_TRIGGER=0x0`). Guarded: a failed install only prints
   `AUTO_TRIGGER: skipped`, it never shuts the console down.
4. **`main-aio.c`** — `diag()` writes `tag=value` lines to `/mnt/usb0/ps4linux-diag.txt`
   (fallback `/data/linux/ps4linux-diag.txt`) and **fsyncs each line**, so a freeze leaves a
   post-mortem. `-DNO_REBOOT_WATCHDOG` removes the legacy `reboot_thread`, which runs the
   `evf_cancel(0x4000)` + `kill(1, SIGUSR1)` trigger that wedges 14.00 one second after arming.

Why `kern_reboot`: on 14.00 `sys_reboot()` never reaches `icc_query_nowait`; only the
shell-orchestrated shutdown (power menu) does. `kern_reboot` is on every reboot path.

## Build

```sh
./build.sh
```

Prereqs: `gcc`, `make`, `ld`, `objcopy`, `python3`, `yasm`.
yasm 1.3.0 needs `CFLAGS="-O2 -std=gnu17"` to build under GCC 15 (C23 `bool` keyword);
this box has no yasm package, so a working binary is vendored at `tools/yasm`
(`export PATH="$PWD/tools:$PATH"`). To rebuild it from source:

```sh
curl -LO https://github.com/yasm/yasm/releases/download/v1.3.0/yasm-1.3.0.tar.gz
tar xzf yasm-1.3.0.tar.gz && cd yasm-1.3.0
./configure --prefix=/tmp/yasm CFLAGS="-O2 -std=gnu17" && make -j"$(nproc)"
```

`build.sh` does: libc stubs → all 21 kexec blobs (`main-aio.c` `.incbin`s every firmware) →
14.00 blob **with** `-DHOOK_KERN_REBOOT -DAUTO_TRIGGER=0x0` → payload with
`-DNO_REBOOT_WATCHDOG` → `objcopy` to `.bin`.

## Deploy

| target | path | notes |
|---|---|---|
| console PayLoader | `/data/payloads/linux-autoboot.elf` | PayLoader scans `/data/payloads` and `/usb*/payloads`, `.elf` only |
| console GoldHEN | `/data/GoldHEN/payloads/linux-autoboot.bin` | raw `.bin`, GoldHEN payload menu |
| lab | `~/ps4-14.00-wkjb/artifacts/linux-autoboot.bin` | what the **Linux** button POSTs to `:9090` |
| Pi working copies | `~/ps4-linux/payload/bin/`, `…/payload/elf/`, `~/ps4-linux/` | |

### Operational rules (learned the hard way)

- **`:9090` only executes raw `.bin`.** ELF images there hang the loader.
- **Never probe 9090.** Every accepted TCP connection is treated as a payload; a connect-and-close
  is `invalid payload format` and the binloader exits for that boot.
- **Never post while SceShellCore is restarting** — i.e. never in the same second the jailbreak
  chain returns, and never after a chain that aborted (`boot is spent`). The lab now refuses
  the Linux button unless the last chain exited 0.
- **One Linux payload per boot.** A second payload overwrites the installed hooks.
- `reboot` / plain `shutdown` do not come back cleanly; use `systemctl poweroff -f` after `sync`
  (the **Power off (Orbis)** Steam shortcut does this).

## Provenance

Reconstructed 2026-11-04 after `/tmp` was wiped overnight and the original working tree was
lost. The lost commits were `53123cd` (kern_reboot hook) and `308d85c` (no watchdog + fsync);
this tree re-implements them on upstream `d0f4d4c` ("Add PS4 14.00 support"). The hardware-proven
binaries are kept alongside as `*-shipped.*`.

The `diag()` file/UDP logging and the compile-time probe branches from those commits
(`SCU_PROBE`, `FLAG_WATCH`, `AUTO_EVF_SET`, `API_PROBE`, `SHELL_CORE_REBOOT`) were diagnostics
used to find the root cause and are **not** re-implemented here; only the durable file marker
(`diag`) is, because it is what makes a frozen hand-off diagnosable.

**Keep working trees out of `/tmp`.** It is wiped on reboot; this directory is the durable copy.

## Linux desktop (after the hand-off)

GPU/display tuning for the booted system is **not** part of the payload — it lives on the
console's rootfs. On this gfx7 box the driver needs
`AMD_DEBUG=notiling,nodisplaytiling,noefc,nocmask,nofmask,nohyperz`, set in
`/usr/local/bin/ps4-session` (the session env that `exec`s Steam) and mirrored in
`/etc/profile.d/amd-notiling.sh`; `ps4-session` also runs `xset s off -dpms`. Steam Big
Picture's own screensaver is disabled in its UI. Full rationale, test matrix and the
screenshot evidence are in `../PS4-LINUX-14.00-REPORT.md` → *Linux desktop: display/GPU
tuning*.

