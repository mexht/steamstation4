#!/bin/bash
set -euo pipefail
echo "== enabling multilib =="
grep -q '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
grep -A2 '^\[multilib\]' /etc/pacman.conf
pacman -Syu --noconfirm
echo "== installing 32-bit build deps =="
pacman -S --noconfirm --needed \
  base-devel meson ninja python-mako python-packaging python-pyaml \
  glslang wayland-protocols xorgproto pkgconf \
  lib32-glibc lib32-gcc-libs lib32-libdrm lib32-wayland lib32-libelf \
  lib32-libglvnd lib32-libva lib32-libxrandr lib32-libxml2 lib32-libx11 \
  lib32-libxcb lib32-libxext lib32-libxfixes lib32-libxdamage \
  lib32-libxshmfence lib32-libxxf86vm lib32-libunwind lib32-lm_sensors \
  lib32-zlib lib32-zstd lib32-expat lib32-llvm lib32-llvm-libs \
  lib32-spirv-tools lib32-vulkan-icd-loader lib32-clang
id builder >/dev/null 2>&1 || useradd -m -u 1000 builder
chown -R builder:builder /work/build32
echo "== building 32-bit =="
su builder -c 'cd /work/build32 && makepkg -f --nodeps --noconfirm'
mkdir -p /work/out
cp /work/build32/*.pkg.tar.zst /work/out/
echo "== done =="
ls -lh /work/out
