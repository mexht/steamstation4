/*
 * steambt-shim: enable Steam's real BlueZ backend on a non-SteamOS host.
 *
 * Steam's UI picks its Bluetooth backend once, at startup:
 *
 *   steamui.so  CSystemBluetoothControllerLinux  (real: org.bluez over GDBus)
 *               CSystemBluetoothControllerStub   (no-op)
 *
 * The selector is `Plat_IsSteamOSManagementEnabled()` (libtier0_s.so, which
 * returns true for the command-line flags -steamos3 / -holo).  Passing
 * -steamos3 also makes Plat_IsSteamOS() true and starts the SteamOS first-run
 * OOBE ("Select your audio configuration" / "Waiting for network..."), which is
 * why the flag is not used.  This shim overrides only the management gate:
 *
 *   int Plat_IsSteamOSManagementEnabled(void) { return 1; }
 *
 * Plat_IsSteamOS() stays false, so the OOBE/update paths stay off while Big
 * Picture exposes Settings -> System -> Bluetooth.
 *
 * Must be 32-bit: the Steam UI (ubuntu12_32/steamui.so) runs inside the 32-bit
 * `steam` process.  Build/install with build-steambt.sh.
 */
int Plat_IsSteamOSManagementEnabled(void) { return 1; }
