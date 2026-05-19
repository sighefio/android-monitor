# Installation Guide

Step-by-step setup for the android-monitor project. Run each section in order. The whole flow is: **install tools → build host → build Android app → connect them**.

---

## 0. Disk space check

Before installing anything, confirm you have free space. The full toolchain (Xcode + Android Studio + SDK + emulator) needs roughly **25–30 GiB**.

```bash
df -h /
```

Look at the `Avail` column for `/`. If it's under ~30 GiB, free space first or pick the lighter install path (CLI-only Android tools + physical device instead of emulator — see steps 6 and 8).

Common space hogs:

```bash
du -sh ~/Library/Developer/Xcode/DerivedData ~/Library/Caches ~/Library/Android 2>/dev/null
```

---

## 1. Install prerequisites on macOS

Open Terminal and run these one at a time. If a tool is already installed, the command is a no-op.

```bash
# Homebrew (skip if you already have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Xcode command-line tools (gives you swift, git, clang)
xcode-select --install

# Android platform tools (gives you adb)
brew install --cask android-platform-tools

# (Optional) Android Studio — easiest way to get the Android SDK + emulator
brew install --cask android-studio

# Verify
swift --version          # should print Swift 5.10+
adb version              # should print Android Debug Bridge
```

> **macOS version:** the host daemon requires **macOS 13.0 or newer** (ScreenCaptureKit audio capture). Check with `sw_vers`.

---

## 2. Get the code

```bash
cd ~/myproject/aikofy/android-monitor
git status               # confirm you're on branch claude/add-claude-documentation-4Vayp
```

If you already have the repo, skip cloning.

---

## 3. Build the host daemon

```bash
cd ~/myproject/aikofy/android-monitor/host
swift build
```

First build downloads no external packages (the project has zero third-party dependencies), so it should finish in under a minute. The binary lands at `host/.build/debug/AndroidMonitorDaemon`.

If you see errors, the most likely cause is a missing macOS SDK — fix by opening Xcode once and accepting the license.

---

## 4. Grant Screen Recording permission

The daemon uses ScreenCaptureKit, which is gated behind a system permission. macOS will prompt automatically the first time you run it, but it's faster to grant it up front:

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Click the **+** button and add `Terminal.app` (or iTerm/whatever shell app you'll launch the daemon from).
3. Toggle it **on**. You'll be asked to quit and reopen the terminal — do that.

Later, when you ship a real signed binary, add `AndroidMonitorDaemon` itself here instead.

---

## 5. Run the host daemon

```bash
cd ~/myproject/aikofy/android-monitor
./host/.build/debug/AndroidMonitorDaemon --port 7878 --bitrate 8000 --mode both
```

Expected: the process stays running (it's a daemon — no output until a client connects). Leave this terminal open. Press **Ctrl-C** to stop it cleanly.

If you see "no displays available" or a permission error, recheck step 4.

---

## 6. Set up the Android build environment

### Option A: Android Studio (recommended)

1. Launch Android Studio once.
2. Go through the setup wizard — it'll install the Android SDK to `~/Library/Android/sdk`.
3. Add this to your `~/.zshrc`:
   ```bash
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
   ```
4. Reload: `source ~/.zshrc`

### Option B: CLI only (no Studio — saves ~5 GiB)

```bash
brew install --cask android-commandlinetools
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

Verify:

```bash
echo $ANDROID_HOME       # should print a non-empty path
sdkmanager --list | head # should not error
```

---

## 7. Build the Android APK

```bash
cd ~/myproject/aikofy/android-monitor/android
./gradlew assembleDebug
```

First run downloads Gradle + Android Gradle Plugin + Compose BOM — expect 3–5 minutes and ~1 GB of network traffic. Subsequent builds take seconds.

Output: `android/app/build/outputs/apk/debug/app-debug.apk`.

If Gradle complains about a missing `gradlew` wrapper jar:

```bash
brew install gradle
gradle wrapper --gradle-version 8.7
```

---

## 8. Connect an Android device

You need either a physical device or an emulator. **Physical device over USB is strongly preferred** — the whole point of this project is low-latency, and USB hits ~20 ms vs ~50 ms over WiFi.

### Option A: Physical device (USB mode)

1. On the phone: **Settings → About phone → tap "Build number" 7 times** to enable Developer options.
2. Then **Settings → Developer options → enable "USB debugging"**.
3. Plug the phone into the Mac. A dialog on the phone will ask "Allow USB debugging?" — tap **Allow**.
4. Verify:
   ```bash
   adb devices
   # Should list your device with status "device" (not "unauthorized")
   ```
5. Install the app and set up the port forward:
   ```bash
   cd ~/myproject/aikofy/android-monitor
   adb install -r android/app/build/outputs/apk/debug/app-debug.apk
   adb forward tcp:7878 tcp:7878
   adb shell am start -n com.androidmonitor/.MainActivity
   ```

The app launches on the phone. In its UI, select **USB mode** (it connects to `127.0.0.1:7878`, which adb forwards back to the Mac).

### Option B: Emulator (WiFi mode, no cable)

1. In Android Studio: **Tools → Device Manager → Create Device**, pick a Pixel, finish.
2. Start it.
3. Find your Mac's LAN IP:
   ```bash
   ipconfig getifaddr en0    # WiFi
   # or
   ipconfig getifaddr en1    # Ethernet
   ```
4. Install the APK to the emulator the same way (`adb install -r ...` works for emulators too).
5. In the app, choose **WiFi mode** and enter the IP from step 3, port `7878`.

> **Note:** for a real phone over WiFi, the phone must be on the same network as the Mac, and macOS's firewall must allow inbound TCP 7878 (**System Settings → Network → Firewall → Options**).

---

## 9. End-to-end test

With the daemon running (step 5) and the app launched (step 8):

1. In the Android app, tap **Connect**.
2. The phone screen should display the Mac's screen.
3. Tapping the phone should move/click the Mac cursor.

If video stays black:

- Check the daemon terminal for log lines (any errors during handshake?).
- Confirm `adb forward --list` shows `tcp:7878 → tcp:7878` (USB mode).
- Try `nc -v 127.0.0.1 7878` from the Mac — should connect instantly.

---

## 10. Daily workflow

Once everything works once, your loop is:

```bash
# Terminal 1 — host
cd ~/myproject/aikofy/android-monitor
swift build --package-path host && \
  ./host/.build/debug/AndroidMonitorDaemon --port 7878

# Terminal 2 — android (USB device plugged in)
cd ~/myproject/aikofy/android-monitor/android
./gradlew installDebug && \
  adb forward tcp:7878 tcp:7878 && \
  adb shell am start -n com.androidmonitor/.MainActivity
```

There's also a `scripts/run-e2e.sh` wrapper that bundles this — use it once the manual flow works end-to-end.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `swift build` fails with SDK error | Xcode license not accepted | Open Xcode.app once, click Agree |
| Daemon exits immediately | Screen Recording permission missing | Step 4 |
| `adb devices` shows `unauthorized` | USB debugging prompt not accepted | Replug, tap **Allow** on phone |
| App can't connect (USB) | `adb forward` not active | Re-run `adb forward tcp:7878 tcp:7878` |
| App can't connect (WiFi) | macOS firewall blocking port 7878 | System Settings → Network → Firewall → Options |
| Black screen, no video | Daemon crashed or no display selected | Check daemon terminal output |
| Gradle wrapper missing | Fresh clone without `gradle-wrapper.jar` | `gradle wrapper --gradle-version 8.7` |
