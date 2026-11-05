# Patches for ps4-linux-loader

These are the changes on top of upstream
[`ps4-linux/ps4-linux-loader`](https://github.com/ps4-linux/ps4-linux-loader)
that implement the 14.00 hand-off. They were generated with `git format-patch`
against upstream `master` at commit `d0f4d4c` ("Add PS4 14.00 support"), which
is also the tip of `origin/master` at the time of writing.

Apply them in order:

```sh
git clone https://github.com/ps4-linux/ps4-linux-loader.git
git -C ps4-linux-loader am "$PWD"/patches/*.patch
```

| patch | contents |
|---|---|
| `0001-14.00-hand-off-to-Linux-by-hooking-kern_reboot.patch` | `hook_kern_reboot()` (wlanbt -> ACPI fixup -> CPU rendezvous), install from `sys_kexec` with `-DHOOK_KERN_REBOOT`, trigger with `-DAUTO_TRIGGER=0x0`, and the `diag()` file logger |
| `0002-Restore-the-shipped-14.00-kexec-diagnostics.patch` | restores the seven `kern.printf` diagnostics the shipped blob carries, which also makes the rebuilt 16,040-byte kexec blob byte-identical |

`build.sh` at the repository root assumes the clone is named
`ps4-linux-loader/` and sets `-DHOOK_KERN_REBOOT -DAUTO_TRIGGER=0x0
-DNO_REBOOT_WATCHDOG` itself, so no manual flags are needed after applying the
patches.

The patches are BSD-2-Clause like the upstream loader; see the file headers.
