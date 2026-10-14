#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Drives the gallery under sway with sway's own pointer and wtype's virtual keyboard. Run by
# wayland.sh as sway's startup command; writes its result to $WORK/result and stops sway.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh

finish() {
  echo "$FAILED" > "$WORK/result"
  swaymsg exit > /dev/null 2>&1
  exit 0
}

command -v wlrctl > /dev/null || { fail "wlrctl is needed for a virtual pointer"; finish; }
start_gallery
wait_for "$LAYOUT" '^inc ' || { fail "the gallery reported its layout"; finish; }
sleep 1
# The window's top left on the output, from sway's tree.
ORIGIN=$(swaymsg -t get_tree | jq -r '.. | objects | select(.name? == "Paw gallery") |
  "\(.rect.x + .window_rect.x) \(.rect.y + .window_rect.y)"' | head -n 1)
set -- $ORIGIN
OX=$1
OY=$2

# A headless sway has no pointer of its own; wlrctl adds a virtual one. It moves relative to
# where it is, so it goes to the top left corner first.
click() {
  set -- $(center "$1")
  wlrctl pointer move -10000 -10000
  wlrctl pointer move $((OX + $1)) $((OY + $2))
  wlrctl pointer click left
  sleep 0.3
}

click inc
click inc
expect "count=2" "clicks reach the app"
click name
sleep 0.6
wtype "Ada"
expect "name=Ada " "typing reaches a text field"
click agree
expect "agree=true" "a checkbox toggles"
click draft
sleep 0.6
wtype "plums"
click add
expect "plums" "an item is added"
click link
expect_still "opened=0" "a click on a button that just moved opens nothing"
sleep 0.6
click link
expect "opened=1" "a real click opens the link"
if grep -q "https://github.com/katzenpost" "$OPENED" 2>/dev/null; then ok "the link reached the opener"
else fail "the link reached the opener"; fi

if command -v wl-paste > /dev/null; then
  click copy
  if [ "$(wl-paste -n 2>/dev/null)" = "Ada" ]; then ok "copy reaches the clipboard"
  else fail "copy reaches the clipboard"; fi
else
  echo "skip copy reaches the clipboard (no wl-paste)"
fi

wtype -M ctrl q -m ctrl
expect_exit "ctrl-q quits"
finish
