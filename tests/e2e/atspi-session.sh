#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# The gallery read over AT-SPI. Run by atspi.sh inside Xvfb and a private session bus.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh

/usr/libexec/at-spi-bus-launcher --launch-immediately &
LAUNCHER=$!
sleep 0.5
# Tell applications that assistive technology is running, as a desktop does when a screen reader starts.
gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus \
  --method org.freedesktop.DBus.Properties.Set org.a11y.Status IsEnabled '<true>' > /dev/null

start_gallery
wait_for "$LAYOUT" '^inc ' || { fail "the gallery reported its layout"; exit 1; }
sleep 1
python3 tests/e2e/atspi.py "$LOG" || FAILED=1
# A confirmation opens only on real input; then a screen reader reads it as a dialog, and cannot
# confirm it.
W=$(xdotool search --sync --name "Paw gallery" | head -n 1)
for k in more clear; do
  set -- $(center "$k")
  xdotool mousemove --window "$W" "$1" "$2" click 1
  sleep 0.9
done
wait_for "$LOG" 'dialog=true' || fail "the menu opens a confirmation"
python3 tests/e2e/atspi.py "$LOG" dialog || FAILED=1
kill "$GALLERY_PID" "$LAUNCHER" 2>/dev/null
exit $FAILED
