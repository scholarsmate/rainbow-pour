# Android Build And Phone Testing

This project can be tested on an Android phone as a regular Godot Android export. The Godot editor binary can stay in `Downloads`; what matters is that the editor is configured with the Java and Android SDK paths.

References checked on 2026-06-04:

- Godot 4.6 Android export docs: https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html
- Android Developers Godot export guide: https://developer.android.com/games/engines/godot/godot-export

## Fast Path

Use this path when you just want the current game on your phone.

1. Install OpenJDK 17.
2. Install Android Studio, run it once, and install the Android SDK packages listed below.
3. Open this project in Godot 4.6.
4. In Godot, install the matching export templates: `Editor > Manage Export Templates`.
5. In Godot, set the Android paths in `Editor > Editor Settings > Export > Android`.
6. Add an Android export preset in `Project > Export`.
7. Export a debug APK.
8. Enable USB debugging on the phone.
9. Install with `adb install -r path\to\rainbow-pour-debug.apk`, or use Godot's deploy/run button with the phone connected.

## Required Tools

Godot 4.6 currently recommends these Android export components:

- OpenJDK 17.
- Android SDK Platform-Tools `35.0.0` or later.
- Android SDK Build-Tools `35.0.1`.
- Android SDK Platform `android-35`.
- Android SDK Command-line Tools, latest.
- CMake `3.10.2.4988404`.
- Android NDK r28b, version `28.1.13356709`.

Android Studio is the simplest way to install and update these. If using the SDK command-line tools directly on Windows, the equivalent install command is:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="$env:LOCALAPPDATA\Android\Sdk" "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmdline-tools;latest" "cmake;3.10.2.4988404" "ndk;28.1.13356709"
```

If the `sdkmanager.bat` path does not exist yet, install Android Studio first or install the Android command-line tools package manually from Google.

## Configure Godot

Open the editor from your Downloads install, for example:

```powershell
& "C:\Users\schol\Downloads\Godot_v4.6.3\Godot_v4.6.3-stable_win64_console.exe" --path D:\GitHub\rainbow-pour
```

Then configure:

1. `Editor > Manage Export Templates`: download/install templates for the exact Godot version you are running.
2. `Editor > Editor Settings > Export > Android`.
3. Set `Java SDK Path` to the OpenJDK 17 install directory.
4. Set `Android SDK Path` to the Android SDK directory, usually `%LOCALAPPDATA%\Android\Sdk` on Windows.

The Godot binary does not need to be installed system-wide.

## Create An Android Preset

In `Project > Export`:

1. Click `Add...`.
2. Choose `Android`.
3. Set the app name/package fields. A good development package name is `com.schol.rainbowpour`.
4. For phone testing, export format can be `APK`.
5. Keep debug export enabled for early device testing.
6. Under `Options > Screen`, set `Orientation` to `Sensor` so the APK can rotate between landscape and portrait.
7. Export to a local `builds/` or `exports/` folder.

`export_presets.cfg` is ignored by git in this repo because Android export presets can contain keystore paths and passwords. Keep signing credentials local.

## Versioning

`VERSION.txt` in the repo root is the source of truth for the app version. Before exporting, sync the Godot project metadata and local Android preset from that file:

```powershell
.\tools\sync_version.ps1
```

The main menu reads `VERSION.txt` directly, so the displayed version stays tied to the same source.

## Put It On The Phone

On the phone:

1. Enable Developer Options.
2. Enable USB debugging.
3. Plug the phone into the PC.
4. Accept the USB debugging prompt on the phone.

From PowerShell:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r .\builds\rainbow-pour-debug.apk
```

If the device is listed as `unauthorized`, unlock the phone and accept the USB debugging prompt.

## Capture A Crash Log

For random crashes, capture logcat while the game is running:

```powershell
.\tools\capture_android_log.ps1 -Launch
```

Play until the app crashes, then press `Ctrl+C` in PowerShell. The script writes a full log and a focused log under `logs/android/`. The focused log keeps the app package, Godot, Android runtime, native signal, low-memory, and ANR lines.

To snapshot the current device log without launching the app:

```powershell
.\tools\capture_android_log.ps1 -Snapshot -NoClear
```

## Play Store Builds Later

For Google Play, export an Android App Bundle (`.aab`) instead of an APK. You also need a release/upload keystore and a non-debug export.

Generate a release keystore with the JDK:

```powershell
& "C:\Path\To\jdk-17\bin\keytool.exe" -v -genkey -keystore rainbow-pour-upload.keystore -alias rainbow-pour -keyalg RSA -validity 10000
```

Store the keystore and passwords outside the repo. Losing the upload key can block future updates unless Play App Signing recovery is configured.

## Common Problems

- `Could not install to device`: uninstall the old app from the phone if it was signed with a different key.
- `adb` cannot see the phone: check USB debugging, cable mode, and the device authorization prompt.
- Export complains about SDK/NDK/CMake: install the exact versions listed above or update the paths in Godot editor settings.
- App installs but appears with a generic icon: add Android launcher icon assets before release. Godot can fall back to the project icon for development builds.
- APK is larger than expected: for local testing, select only the architecture your phone needs; for Play Store AABs, keep required 64-bit support enabled.
