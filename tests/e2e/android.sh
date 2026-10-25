#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Drives the gallery on an Android emulator with adb, as a user would: taps, typing, the back key,
# leaving the app and coming back. Needs the APK from `make apk`, and `adb root`, as on an
# emulator's google_apis image, to read the test hooks' files from the app's private directory.
set -u
cd "$(dirname "$0")/../.."
APK=${APK:-.lake/android/paw-gallery-x86_64.apk}
PKG=org.katzenpost.paw.gallery
ACTIVITY=$PKG/com.google.androidgamesdk.GameActivity
FILES=/data/data/$PKG/files
WORK=$(mktemp -d "${TMPDIR:-/tmp}/paw-e2e.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FAILED=0

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAILED=1; }

adb root >/dev/null
adb wait-for-device
adb install -r "$APK" >/dev/null || { fail "the APK installs"; exit 1; }
adb shell am force-stop $PKG
adb shell rm -f $FILES/model.log $FILES/layout.txt
adb shell setprop debug.paw.test_log model.log
adb shell setprop debug.paw.test_layout layout.txt
adb shell setprop debug.paw.reduce_motion 1
adb logcat -c
adb shell am start -n $ACTIVITY >/dev/null

last() { adb exec-out cat $FILES/model.log 2>/dev/null | tail -n 1; }

# Checks that the model log's last line comes to match a pattern.
expect() {
  i=0
  while ! last | grep -q -- "$1"; do
    i=$((i + 1))
    if [ $i -gt 50 ]; then fail "$2 (last: $(last))"; return; fi
    sleep 0.1
  done
  ok "$2"
}

# Checks that, after a pause, the model log's last line still matches a pattern.
expect_still() {
  sleep 1
  if last | grep -q -- "$1"; then ok "$2"; else fail "$2 (last: $(last))"; fi
}

i=0
until adb exec-out cat $FILES/layout.txt 2>/dev/null | grep -q '^inc '; do
  i=$((i + 1))
  if [ $i -gt 100 ]; then fail "the gallery reported its layout"; exit 1; fi
  sleep 0.1
done
ok "the gallery reported its layout"

# Where the window's area starts on the screen, from the accessibility tree the gallery gives
# Android, and how many pixels a logical pixel is.
adb shell uiautomator dump /sdcard/paw-ui.xml >/dev/null 2>&1
adb exec-out cat /sdcard/paw-ui.xml > "$WORK/ui.xml"
for name in "Paw gallery" "+" "Katzenpost on GitHub" "I agree"; do
  if grep -q "content-desc=\"$name\"" "$WORK/ui.xml"; then ok "Android's accessibility tree has \"$name\""
  else fail "Android's accessibility tree has \"$name\""; fi
done
# Reads where the window's area starts from the accessibility tree again, as turning the screen
# moves it.
origin() {
  adb shell uiautomator dump /sdcard/paw-ui.xml >/dev/null 2>&1
  adb exec-out cat /sdcard/paw-ui.xml > "$WORK/ui.xml"
  set -- $(sed -n 's/.*content-desc="Paw gallery"[^>]*bounds="\[\([0-9]*\),\([0-9]*\)\].*/\1 \2/p' "$WORK/ui.xml")
  OX=${1:-0}
  OY=${2:-0}
}
origin
SCALE=$(adb shell wm density | awk '{ d = $NF } END { print d / 160 }')

# Taps the middle of the widget with a key.
tap() {
  adb exec-out cat $FILES/layout.txt > "$WORK/layout.txt"
  set -- $(awk -v k="$1" -v s="$SCALE" -v ox="$OX" -v oy="$OY" \
    '$1 == k { printf "%d %d\n", ox + ($2 + $4) / 2 * s, oy + ($3 + $5) / 2 * s }' "$WORK/layout.txt")
  adb shell input tap "$1" "$2"
  sleep 0.3
}

# Widgets must have been still for the router's 500 ms before a tap designates them.
sleep 1
tap inc
tap inc
expect "count=2" "taps reach the app"
tap name
sleep 0.6
adb shell input text Ada
expect "name=Ada " "typing reaches a text field"
tap agree
expect "agree=true" "a checkbox toggles"
tap draft
sleep 0.6
adb shell input text plums
tap add
expect "plums" "an item is added"
# Over adb a tap takes longer than the router's 500 ms, so that a tap on a widget that just moved
# designates nothing is tested in process and on X11 instead.
sleep 0.6
tap link
expect "opened=1" "a real tap opens the link"
if adb logcat -d | grep -q "act=android.intent.action.VIEW dat=https://github.com/"; then
  ok "the link reached the browser"
else
  fail "the link reached the browser"
fi
# Back from the browser, once it has come up.
sleep 3
adb shell am force-stop com.android.chrome
adb shell am start -n $ACTIVITY >/dev/null
sleep 2

# Copy the name, then paste it into the notes, where Enter starts a new line.
tap copy
tap notes
sleep 0.6
adb shell input keycombination KEYCODE_CTRL_LEFT KEYCODE_V
expect "notes=Ada" "copy and paste go through the clipboard"
adb shell input keyevent KEYCODE_ENTER
adb shell input text two
expect "notes=Ada|two" "Enter starts a new line in a text area"

# The menu opens a confirmation. Nothing beneath it can be reached, and the back key takes the
# safe choice, as Escape does.
tap more
sleep 0.6
tap clear
expect "dialog=true" "the menu opens a confirmation"
tap inc
expect_still "count=2 .*dialog=true" "a tap beneath the dialog reaches nothing"
adb shell input keyevent KEYCODE_BACK
expect "dialog=false" "the back key cancels the confirmation"
expect "plums" "and the list is kept"

# Leaving the app takes its surface away; coming back draws it again, with the model kept.
PID=$(adb shell pidof $PKG)
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am start -n $ACTIVITY >/dev/null
sleep 2
if [ "$(adb shell pidof $PKG)" = "$PID" ]; then ok "the app lives on in the background"
else fail "the app lives on in the background"; fi
adb exec-out screencap -p > "$WORK/back.png"
colours=$(python3 -c 'import sys,zlib,struct
d=open(sys.argv[1],"rb").read(); print(len(set(d[i] for i in range(len(d)//2, len(d), 97))))' "$WORK/back.png")
if [ "$colours" -gt 4 ]; then ok "it draws again when it comes back"; else fail "it draws again when it comes back"; fi
expect "count=2 .*plums" "with its model kept"

tap load
expect "picture=true" "a task's picture is shown"
# The Lists tab is wider than a phone held upright; turning it lays the gallery out again.
tap tab-Lists
AUTO_ROTATE=$(adb shell settings get system accelerometer_rotation)
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
sleep 2
origin
tap startClock
expect "ticks=2" "a producer's messages wake the loop"
adb shell settings put system user_rotation 0
adb shell settings put system accelerometer_rotation "$AUTO_ROTATE"
# Turning the screen moves the window's focus, and a key counts only once focus has held for the
# router's 500 ms.
sleep 1.5

adb shell input keycombination KEYCODE_CTRL_LEFT KEYCODE_Q
i=0
while [ -n "$(adb shell pidof $PKG)" ]; do
  i=$((i + 1))
  if [ $i -gt 50 ]; then fail "ctrl-q quits"; break; fi
  sleep 0.1
done
[ $i -le 50 ] && ok "ctrl-q quits"
adb shell setprop debug.paw.test_log "''"
adb shell setprop debug.paw.test_layout "''"
adb shell setprop debug.paw.reduce_motion "''"
exit $FAILED
