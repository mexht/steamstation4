# PS4-patched Mesa 26.2.6 (Liverpool raster config)

This directory holds the reproducible recipe for the graphics-stack fix described
in `PS4-LINUX-14.00-REPORT.md` ("Root cause: stock Mesa uses Kaveri's raster
config on Liverpool").

## Why

Stock Mesa mis-identifies the PS4 GPU (`1002:9923`) as **Kaveri** and programs
Kaveri's raster configuration:

| | `raster_config` | `raster_config_1` |
|---|---|---|
| Kaveri (stock Mesa) | `0x16000012` | `0x0000002a` |
| **Liverpool (correct)** | **`0x2a00161a`** | **`0x00000000`** |

That register describes the SE/RB layout (bits 12-15 = number of shader
engines). Kaveri = 1 SE; Liverpool = 2 SE. With the wrong value, CMASK/FMASK/HTILE
and display-tiling metadata are interpreted incorrectly, producing black tiles
and text/atlas corruption. The old
`AMD_DEBUG=notiling,nodisplaytiling,noefc,nocmask,nofmask,nohyperz` workaround
merely avoids those paths (and costs tiling, Hi-Z, fast-clear and mask
compression).

Hardware confirmation on the console (AMDGPU `INFO_DEV_INFO` ioctl):

```
device_id     0x9923
external_rev  0x61      # STARSHA range = [0x61, 0x71) -> LIVERPOOL
family        0x7d      # AMDGPU_FAMILY_KV -> the patched FAMILY_KV case runs
num_se        2
num_sa_per_se 1
```

## What the patch changes

`ps4-mesa-26.2.6.patch` (rebased from the upstream PS4 patch for 26.0.8):

- `src/amd/addrlib/src/amdgpu_asic_addr.h`: adds `AMDGPU_STARSHA_RANGE`
  (`0x61..0x71`) and `AMDGPU_STARSHP_RANGE` (`0x71..0x81`).
- `src/amd/common/ac_gpu_info.c`: `identify_chip2(STARSHA, LIVERPOOL)` /
  `identify_chip2(STARSHP, GLADIUS)` in the `FAMILY_KV` case; adds both to the
  GFX7 paths (L2 size, raster config). Liverpool gets
  `raster_config = 0x2a00161a`, `raster_config_1 = 0`.
- `src/amd/common/amd_family.{c,h}`: new `CHIP_LIVERPOOL`/`CHIP_GLADIUS`
  families, GFX7, LLVM processor `bonaire`.
- `src/gallium/winsys/radeon/drm/radeon_surface.c`: non-amdgpu path support.

The companion patches from the same upstream set are **not** installed here, but
are kept next to this file for reference: `ps4-libdrm.patch` only adds device
names to `amdgpu.ids`, and `ps4-xf86-video-amdgpu.patch` only fixes the CIK+
cursor size (128 -> 64). Neither affects tiling or the raster config.
`reference/ps4-mesa.patch` is the original upstream patch; `ps4-mesa-26.2.6.patch`
is the rebased version that is actually applied.

## Build (host, Arch container, generic x86-64)

The Jaguar has no AVX2, so the packages must be built with plain `-march=x86-64`
(the Arch container's default), not a CachyOS `x86-64-v3` preset.

```sh
cd /tmp/opencode/ps4-video

# 1. source + patch
curl -fLO https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-26.2.6/mesa-mesa-26.2.6.tar.gz
mkdir mesa-26.2.6 && tar -xzf mesa-mesa-26.2.6.tar.gz -C mesa-26.2.6 --strip-components=1
(cd mesa-26.2.6 && patch -p1 -i /path/to/ps4-mesa-26.2.6.patch)
tar -czf build64/mesa-26.2.6-ps4.tar.gz mesa-26.2.6
cp build64/mesa-26.2.6-ps4.tar.gz build32/

# 2. 64-bit package (mesa-ps4)
docker run --rm -v /tmp/opencode/ps4-video:/work -w /work/build64 \
  archlinux:base-devel bash /work/build64/run.sh

# 3. 32-bit package (lib32-mesa-ps4; enables multilib in the container)
docker run --rm -v /tmp/opencode/ps4-video:/work -w /work/build32 \
  archlinux:base-devel bash /work/build32/run.sh
```

`PKGBUILD-mesa-ps4` / `PKGBUILD-lib32-mesa-ps4` are the exact PKGBUILDs used.
The 32-bit build uses `CC="gcc -m32"`, `PKG_CONFIG=i686-pc-linux-gnu-pkg-config`
and `llvm32.native` (`llvm-config32`).

Result (verified):

```
libgallium-26.2.6.so   ELF 64-bit, contains LIVERPOOL/GLADIUS + 0x2a00161a
lib32/libgallium-26.2.6.so  ELF 32-bit, contains LIVERPOOL + 0x2a00161a
```

Max required glibc symbol is `GLIBC_2.43`; the console has glibc 2.44, so the
packages run unchanged.

The already-built packages and their `SHA256SUMS` are kept in
`../../prebuilt/mesa-26.2.6/` — outside `/tmp` — so a rebuild is only needed if
the patch or the Mesa version changes. The `/tmp/opencode/ps4-video` build tree
itself is disposable; this directory plus `../../prebuilt/` is everything needed
to reproduce it. Note that `/tmp` here is tmpfs and does not survive a reboot.

## Install (console)

The patched package replaces the `mesa`/`vulkan-radeon` split set, so remove the
stock providers first (they conflict by design):

```sh
systemctl stop getty@tty1                     # stop X/Steam so old libs are not held

pacman -Rdd --noconfirm vulkan-mesa-implicit-layers lib32-vulkan-mesa-implicit-layers \
                        vulkan-radeon lib32-vulkan-radeon
pacman -Rdd --noconfirm mesa lib32-mesa
pacman --config /tmp/pacman-ps4.conf -U --noconfirm \
       mesa-ps4-26.2.6-1-x86_64.pkg.tar.zst lib32-mesa-ps4-26.2.6-1-x86_64.pkg.tar.zst

systemctl start getty@tty1
```

`/tmp/pacman-ps4.conf` is a copy of `pacman.conf` with
`SigLevel = Optional TrustAll` (packages are locally built and unsigned).

## Verify

```sh
su - ps4 -c "DISPLAY=:0 XAUTHORITY=\$HOME/.Xauthority glxinfo -B" | grep -E "Device|renderer"
# Device: AMD Jaguar (radeonsi, liverpool, ACO, DRM 3.64, ...) (0x9923)
# OpenGL renderer string: AMD Jaguar (radeonsi, liverpool, ACO, ...)

# both processes use the patched gallium
grep -oE "/usr/lib(32)?/libgallium[^ ]*" /proc/$(pgrep -x steam)/maps        # /usr/lib32/...
grep -oE "/usr/lib(32)?/libgallium[^ ]*" /proc/$(pgrep -x steamwebhelper | head -1)/maps
```

With the patched stack the `AMD_DEBUG` workaround is **not** needed; it is
commented out in `ps4-session`. Big Picture (32-bit Steam UI) and the CEF UI
(64-bit) were verified clean by screenshot with no `AMD_DEBUG`.

## Rollback

`/root/ps4-gfx-rollback.sh` on the console reinstalls stock
`mesa/lib32-mesa/vulkan-radeon/lib32-vulkan-radeon` (plus the implicit-layer
packages), re-enables the `AMD_DEBUG` line and restarts the session.
