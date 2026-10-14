# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Helpers for driving the gallery in a real window. Sourced with WORK set to a scratch directory.

LOG=$WORK/model.log
LAYOUT=$WORK/layout.txt
OPENED=$WORK/opened.txt
GALLERY=$PWD/.lake/build/bin/paw-gallery
FAILED=0

# Runs the gallery with the test hooks, and xdg-open replaced by a stub that records the link.
start_gallery() {
  : > "$LOG"
  env PAW_TEST_LOG="$LOG" PAW_TEST_LAYOUT="$LAYOUT" PAW_E2E_OPENED="$OPENED" \
    PATH="$PWD/tests/e2e/stubs:$PATH" "$GALLERY" &
  GALLERY_PID=$!
}

# Waits up to 10 s for a file to hold a line matching a pattern.
wait_for() {
  i=0
  while ! grep -q -- "$2" "$1" 2>/dev/null; do
    i=$((i + 1))
    if [ $i -gt 100 ]; then return 1; fi
    sleep 0.1
  done
}

# The middle of the widget with a key, in logical pixels from the window's top left.
center() {
  awk -v k="$1" '$1 == k { printf "%d %d\n", ($2 + $4) / 2, ($3 + $5) / 2 }' "$LAYOUT"
}

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAILED=1; }

# Checks that the model log's last line comes to match a pattern.
expect() {
  i=0
  while ! tail -n 1 "$LOG" | grep -q -- "$1"; do
    i=$((i + 1))
    if [ $i -gt 50 ]; then fail "$2 (last: $(tail -n 1 "$LOG"))"; return; fi
    sleep 0.1
  done
  ok "$2"
}

# Checks that, after a pause, the model log's last line still matches a pattern.
expect_still() {
  sleep 1
  if tail -n 1 "$LOG" | grep -q -- "$1"; then ok "$2"; else fail "$2 (last: $(tail -n 1 "$LOG"))"; fi
}

# Waits up to 5 s for the gallery to exit.
expect_exit() {
  i=0
  while kill -0 "$GALLERY_PID" 2>/dev/null; do
    i=$((i + 1))
    if [ $i -gt 50 ]; then fail "$1"; kill "$GALLERY_PID"; return; fi
    sleep 0.1
  done
  ok "$1"
}
