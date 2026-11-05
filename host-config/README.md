# Host-side session config (Linux rootfs)

These are copies of the files on the console's Linux rootfs that make the desktop and
GPU behave. They are **not** part of the payload; re-apply them after a rootfs reinstall.

| file | install to | notes |
|---|---|---|
| `ps4-session` | `/usr/local/bin/ps4-session` (mode 0755) | `~ps4/.xinitrc` execs this; it is the session env that `exec`s Steam |
| `amd-notiling.sh.disabled` | (was `/etc/profile.d/amd-notiling.sh`) | login-shell export of the old workaround; **disabled** (see below) |
| `steambt-shim.c`, `libsteambt.so` | `/usr/local/lib/libsteambt.so` (mode 0755) | 32-bit `LD_PRELOAD`; enables Steam's real BlueZ backend |
| `build-steambt.sh` | (host-side helper) | rebuilds `libsteambt.so` with `gcc -m32` |
| `bt-bondable.service` | `/etc/systemd/system/` | keeps the adapter bondable so controller link keys are stored |
| `bt-pair.sh` | `/root/bt-pair.sh` | headless scan → pair → trust → connect helper for a controller |
| `perf-watch.sh` | `/root/perf-watch.sh` | samples game CPU/RSS/threads + `radeontop` into `/tmp/perf-new.log` |
| `ps4-gfx-rollback.sh` | `/root/ps4-gfx-rollback.sh` | restores stock Mesa and re-enables `AMD_DEBUG` |
| `pacman-ps4.conf` | `/tmp/pacman-ps4.conf` | pacman config that accepts the unsigned Mesa packages; the console's `/tmp` is tmpfs, so re-copy it after a reboot |
| `ps4-session.bak` | (reference) | `ps4-session` as it was before the Mesa/`AMD_DEBUG` edits |
| `ps4-gfx-versions.txt` | (reference) | package and library versions recorded before the Mesa change |
| `mesa-ps4/` | (host-side build recipe) | patched Mesa 26.2.6 that identifies `CHIP_LIVERPOOL` |

Prebuilt output of `mesa-ps4/` is kept outside `/tmp` in
`../prebuilt/mesa-26.2.6/` (`mesa-ps4` + `lib32-mesa-ps4`, with `SHA256SUMS`), so a
rootfs reinstall does not require a rebuild.

## Graphics: patched Mesa instead of `AMD_DEBUG`

**The `AMD_DEBUG` workaround is no longer used.** It existed because stock Mesa
mis-identifies the PS4 GPU (`1002:9923`) as Kaveri and programs Kaveri's raster
configuration (`0x16000012`, 1 SE) instead of Liverpool's (`0x2a00161a`, 2 SE).
That corrupts CMASK/FMASK/HTILE and display tiling; the six debug flags only
avoided those paths, at the cost of tiling, Hi-Z and fast-clear.

`mesa-ps4/` contains the 26.2.6 + `ps4-mesa-26.2.6.patch` build recipe (64-bit
`mesa-ps4` and 32-bit `lib32-mesa-ps4`). With it installed,
`glxinfo` reports `radeonsi, liverpool`, and Big Picture renders correctly with
**no** `AMD_DEBUG` set (verified 2026-11-04). The line is kept, commented out, in
`ps4-session` as a fallback; `/root/ps4-gfx-rollback.sh` restores the stock stack
and re-enables it.

Measured cost of the old workaround (glmark2 2023.01, 1080p off-screen, patched
Mesa in both runs, only `AMD_DEBUG` differs; two no-flag runs agree within 1.5%):

| scene | no flags | six flags | gain |
|---|---|---|---|
| terrain | 263 | 98 | 2.7× |
| shadow | 1140 | 844 | 1.35× |
| refract | 347 | 232 | 1.49× |
| bump | 6350 | 2266 | 2.8× |
| desktop | 954 | 499 | 1.9× |
| effect2d | 4036 | 1167 | 3.4× |
| **score** | **2180** | **850** | **2.56×** |

`glmark2` is installed on the console (`glmark2 --off-screen --size 1920x1080
-b terrain:duration=5 ...`) if the A/B needs to be repeated.

Legacy workaround (only if reverting): without the six flags the stock stack
misrenders tiled buffers and fast-clear metadata — horizontal bands / black
tiles in exclusive fullscreen, black blocks in font atlases and Big Picture
images. All six are required; dropping any one reproduces the glitch.

`xset s off -dpms` disables X's 600 s blanking, which does not restore cleanly on this
display path and makes it look like the game died.

Steam Big Picture still has its own screensaver; disable it in
**Settings → Customization → Screensaver**: "Show screensavers when playing a game" off,
"When idle, start screensaver after" → Disabled.

Full test matrix and screenshots: `../../PS4-LINUX-14.00-REPORT.md` →
*Linux desktop: display/GPU tuning*.

## Bluetooth

The stock rootfs only ships `bluez-libs`; the daemon and CLI are missing. Install and
enable them once:

```sh
pacman -S bluez bluez-utils          # 5.87-2
systemctl enable --now bluetooth
bluetoothctl show                    # Powered: yes, Controller <adapter-mac>
```

`ps4-session` waits up to 10 s for `org.bluez` before starting Steam, because the real
backend needs `bluetoothd` up when the UI starts.

Pairing a DS4: hold **PS + Share** until the lightbar double-flashes, then use
**Big Picture → Settings → System → Bluetooth** (or the Quick Access Bluetooth tab).
Select **Wireless Controller**; it is paired, trusted and connected in one step. After
that, pressing PS reconnects it.

Big Picture's **Forget** only disconnects — the device stays trusted and comes back on
the next connection. To really unpair, run `bluetoothctl remove <MAC>` and pair again.

### The adapter must be bondable

Without this, the pad reports `Paired: yes` but **no link key is stored**
(`Bonded: no`), BlueZ's HID plugin logs
`hidp_add_connection() Rejected connection from !bonded device`, and no
`/dev/input/event*` node is created — the controller looks connected but nothing
works in Big Picture. The half-paired record is also why "Forget" appears to do
nothing.

Check:

```sh
btmgmt info | grep "current settings"   # must contain "bondable"
bluetoothctl show | grep Pairable       # must be yes while pairing
```

Fix and install the unit:

```sh
install -Dm644 bt-bondable.service /etc/systemd/system/bt-bondable.service
systemctl daemon-reload
systemctl enable --now bt-bondable.service
systemctl restart bluetooth
systemctl is-active bt-bondable.service    # active
btmgmt info | grep "current settings"      # includes bondable
```

`PartOf=bluetooth.service` re-applies the setting on every Bluetooth restart. If a
pad was paired while the adapter was not bondable, drop the stale record
(`bluetoothctl remove <MAC>`) and pair again — a `pair` on top of it fails with
`AlreadyExists`.

`/etc/bluetooth/input.conf` stays at its default (`#ClassicBondedOnly=true`).
`ClassicBondedOnly=false` is only a diagnostic: it lets a half-paired device
through, but the missing link key is the actual bug.

### Why the shim is needed

Steam chooses its Bluetooth backend once, at UI startup, in `steamui.so`:

- `CSystemBluetoothControllerLinux` — real org.bluez/D-Bus backend;
- `CSystemBluetoothControllerStub` — no-op, hides all Bluetooth UI.

The selector calls `Plat_IsSteamOSManagementEnabled()` (in `libtier0_s.so`). That
function returns true only for the SteamOS launch flags `-steamos3` / `-holo`, so on a
normal Linux host Steam logs `Initializing bluetooth manager: stub` and the Big Picture
Bluetooth tab does not exist.

`-steamos3` does enable it, but it also makes `Plat_IsSteamOS()` true and starts the
SteamOS first-run OOBE ("Select your audio configuration" → "Waiting for network..."),
so it is **not** usable here. `libsteambt.so` instead overrides only
`Plat_IsSteamOSManagementEnabled()` and returns 1; `Plat_IsSteamOS()` stays false, so no
OOBE/update paths. It must be **32-bit** because `ubuntu12_32/steamui.so` runs inside the
32-bit `steam` process. The 64-bit `steamwebhelper` inherits `LD_PRELOAD` and logs a
harmless `wrong ELF class ... ignored` warning.

Verified 2026-11-04: Big Picture showed **Bluetooth → Available to pair →
Wireless Controller**, and after clicking it `bluetoothctl info` reported
`Paired: yes / Trusted: yes / Connected: yes`.

If a future Steam update changes the gate/symbol, the Bluetooth entry will disappear
again; re-check `steamui_system.txt` for `Initializing bluetooth manager: stub` and update
the shim.

The module is the Marvell SD8797 combo (`btmrvl_sdio`, firmware
`/lib/firmware/mrvl/sd8797_uapsta.bin`); the adapter MAC `<adapter-mac>` is the
Foxconn factory MAC.

Automatic Orbis→Linux controller hand-off is not possible without Orbis's link key
(encrypted keystore; the DS4 only keeps one host pairing). Use USB on the Orbis side or
re-pair with PS+Share. Details in `../../PS4-LINUX-14.00-REPORT.md` → *Bluetooth*.
