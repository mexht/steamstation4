#!/bin/bash
set -euo pipefail
echo "== syncing container =="
pacman -Syu --noconfirm
echo "== installing build deps =="
pacman -S --noconfirm --needed \
  base-devel meson ninja python-mako python-ply python-packaging python-pyaml \
  cbindgen glslang directx-headers wayland-protocols libxml2 libva elfutils \
  libxrandr xorgproto llvm clang \
  libunwind lm_sensors libxshmfence libxdamage libxxf86vm libxfixes libxext \
  libxcb libx11 libglvnd wayland libdrm zstd expat python xcb-util-keysyms \
  vulkan-icd-loader
id builder >/dev/null 2>&1 || useradd -m -u 1000 builder
chown -R builder:builder /work/build64
echo "== building =="
su builder -c 'cd /work/build64 && makepkg -f --nodeps --noconfirm'
mkdir -p /work/out
cp /work/build64/*.pkg.tar.zst /work/out/
echo "== done =="
ls -lh /work/out
