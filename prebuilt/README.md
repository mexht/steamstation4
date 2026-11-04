# Prebuilt packages

Built on the host (Arch container) from `../host-config/mesa-ps4/` and installed on
the console on 2026-11-04. Kept here because the build tree lived under `/tmp`
(tmpfs) and would not survive a host reboot.

| file | what it is |
|---|---|
| `mesa-ps4-26.2.6-1-x86_64.pkg.tar.zst` | 64-bit Mesa 26.2.6 + PS4 (Liverpool) patch |
| `lib32-mesa-ps4-26.2.6-1-x86_64.pkg.tar.zst` | 32-bit (`lib32-`) build for Steam's 32-bit process |
| `SHA256SUMS` | integrity check for the two packages above |

```sh
sha256sum -c SHA256SUMS
```

Both packages are **unsigned**. The console has a pacman config with
`SigLevel = Optional TrustAll` at `/tmp/pacman-ps4.conf`, so install with:

```sh
# on the console, with the session stopped
systemctl stop getty@tty1
pacman -Rdd --noconfirm mesa lib32-mesa
pacman --config /tmp/pacman-ps4.conf -U mesa-ps4-26.2.6-1-x86_64.pkg.tar.zst \
                                     lib32-mesa-ps4-26.2.6-1-x86_64.pkg.tar.zst
systemctl start getty@tty1
```

Verify with `glxinfo | grep -i "device:"` → should report `radeonsi, liverpool`,
and `pacman -Q mesa-ps4 lib32-mesa-ps4` → `26.2.6-1`.

Rollback: `/root/ps4-gfx-rollback.sh` (copy in `../host-config/`).
