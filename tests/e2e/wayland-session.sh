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

mkfifo "$WORK/pointer"
"$PWD/rust/target/release/examples/vpointer" 1024 768 < "$WORK/pointer" > "$WORK/pointer.out" 2>&1 &
exec 3> "$WORK/pointer"
wait_for "$WORK/pointer.out" '^ready' || { fail "a virtual pointer"; finish; }
start_gallery
wait_for "$LAYOUT" '^inc ' || { fail "the gallery reported its layout"; finish; }
sleep 1
expect_idle "an idle gallery does not wake"
# The window's top left on the output, from sway's tree.
ORIGIN=$(swaymsg -t get_tree | jq -r '.. | objects | select(.name? == "Paw gallery") |
  "\(.rect.x + .window_rect.x) \(.rect.y + .window_rect.y)"' | head -n 1)
set -- $ORIGIN
OX=$1
OY=$2

# A headless sway has no pointer of its own; vpointer adds a virtual one that stays connected,
# fed commands through a pipe.
click() {
  set -- $(center "$1")
  echo "move $((OX + $1)) $((OY + $2))" >&3
  echo "click" >&3
  sleep 0.3
}

click inc
click inc
expect "count=2" "clicks reach the app"
click name
sleep 0.6
wtype -s 200 -d 30 "Ada"
expect "name=Ada " "typing reaches a text field"
click agree
expect "agree=true" "a checkbox toggles"
click draft
sleep 0.6
wtype -s 200 -d 30 "plums"
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

# The menu opens a confirmation, which only real input can. Nothing beneath it can be reached, and
# Escape takes the safe choice.
click more
sleep 0.6
click clear
expect "dialog=true" "the menu opens a confirmation"
click inc
expect_still "count=2 .*dialog=true" "a click beneath the dialog reaches nothing"
wtype -s 200 -k Escape
expect "dialog=false" "Escape cancels the confirmation"
expect "plums" "and the list is kept"

# A task makes a picture, which the app hands to an image widget.
click load
expect "picture=true" "a task's picture is shown"

wtype -s 200 -M ctrl q -m ctrl
expect_exit "ctrl-q quits"
finish
