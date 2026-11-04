#!/bin/sh
# Restore the stock Arch graphics stack and the AMD_DEBUG workaround.
set -e
pacman -Rdd --noconfirm mesa-ps4 lib32-mesa-ps4
pacman -S --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
  vulkan-mesa-implicit-layers lib32-vulkan-mesa-implicit-layers
sed -i "s|^# export AMD_DEBUG=.*|export AMD_DEBUG=notiling,nodisplaytiling,noefc,nocmask,nofmask,nohyperz|" /usr/local/bin/ps4-session
systemctl restart getty@tty1
echo "stock graphics stack restored, AMD_DEBUG re-enabled, session restarted"
