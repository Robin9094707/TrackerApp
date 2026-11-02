#!/usr/bin/env bash
# Runs inside the emulator job: installs the APK, opens a school link served by
# a local backend (10.0.2.2 = CI host) and captures screenshots of each screen.
set -uo pipefail
APK="$1"; TOKEN="$2"; OUT="$3"
mkdir -p "$OUT"
PKG=eu.rjuhas.rjtracker.android
shot() { adb exec-out screencap -p > "$OUT/$1.png"; echo "screenshot $1"; }
tap_text() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1
  local bounds
  bounds=$(python3 - "$OUT/ui.xml" "$1" <<'PY'
import re, sys
xml = open(sys.argv[1], encoding="utf-8").read()
for match in re.finditer(r'<node [^>]*?text="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
    if match.group(1) == sys.argv[2]:
        x1, y1, x2, y2 = map(int, match.groups()[1:])
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
)
  if [ -n "$bounds" ]; then adb shell input tap $bounds; echo "tapped $1"; else echo "text $1 not found"; fi
}
adb install -r "$APK"
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb logcat -c
adb shell am start -W -a android.intent.action.VIEW -d "rjtracker://school/$TOKEN?server=http://10.0.2.2:5000" $PKG
sleep 1.2; shot 01-greeting
sleep 2.4; shot 02-connect
sleep 1.4; shot 03-success
sleep 8; shot 04-dashboard
adb shell input swipe 540 1500 540 500 600; sleep 3; shot 05-today-expanded
tap_text "Verlauf"; sleep 6; shot 06-history
tap_text "Protokoll"; sleep 5; shot 07-protocol
tap_text "Orte"; sleep 4; shot 08-places
tap_text "Heute"; sleep 2
adb shell input swipe 540 600 540 1700 600; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 3; shot 09-home
adb logcat -d > "$OUT/logcat.txt"
if grep -q "FATAL EXCEPTION" "$OUT/logcat.txt"; then
  grep -A30 "FATAL EXCEPTION" "$OUT/logcat.txt" | head -60
  echo "App crashed"; exit 1
fi
adb shell pidof $PKG >/dev/null && echo "App running without crash" || { echo "App process missing"; exit 1; }
