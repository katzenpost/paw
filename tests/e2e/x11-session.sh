#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Drives the gallery on an X11 display with xdotool, as a user would. Run by x11.sh inside Xvfb.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh

start_gallery
W=$(xdotool search --sync --name "Paw gallery" | head -n 1)
# Xvfb has no window manager to give the window keyboard focus.
xdotool windowfocus --sync "$W"
wait_for "$LAYOUT" '^inc ' || { fail "the gallery reported its layout"; exit 1; }
# Widgets must have been still for the router's 500 ms before a click designates them.
sleep 1
expect_idle "an idle gallery does not wake"

click() {
  set -- $(center "$1")
  xdotool mousemove --window "$W" "$1" "$2" click 1
  sleep 0.3
}

click inc
click inc
expect "count=2" "clicks reach the app"
click name
sleep 0.6
xdotool type --delay 30 "Ada"
expect "name=Ada " "typing reaches a text field"
click agree
expect "agree=true" "a checkbox toggles"
click draft
sleep 0.6
xdotool type --delay 30 "plums"
click add
expect "plums" "an item is added"
# The new row moved the link down. Clicking it at once does not count as the user's choice;
# a person takes longer than the router's 500 ms to find it again.
click link
expect_still "opened=0" "a click on a button that just moved opens nothing"
sleep 0.6
click link
expect "opened=1" "a real click opens the link"
if grep -q "https://github.com/katzenpost" "$OPENED" 2>/dev/null; then ok "the link reached the opener"
else fail "the link reached the opener"; fi

# A click another program sends with XSendEvent is not XInput2, which is how the window reads the
# pointer, so it never arrives.
set -- $(center inc)
xdotool mousemove --window "$W" "$1" "$2"
xdotool click --window "$W" 1
expect_still "count=2" "a click sent with XSendEvent is refused"
# Keys sent the same way do arrive: winit reads keys from core events and does not say which came
# from another program. X11 has no trusted path between programs; see DESIGN.md.
click name
sleep 0.6
xdotool type --window "$W" "zzz"
sleep 1
if tail -n 1 "$LOG" | grep -q "name=Adazzz"; then echo "note keys sent with XSendEvent arrive (X11 has no trusted path)"
else ok "keys sent with XSendEvent are refused"; fi

if command -v xclip > /dev/null; then
  click copy
  sleep 0.3
  name=$(tail -n 1 "$LOG" | sed 's/.*name=\([^ ]*\) .*/\1/')
  if [ "$(xclip -o -selection clipboard 2>/dev/null)" = "$name" ]; then ok "copy reaches the clipboard"
  else fail "copy reaches the clipboard (expected $name)"; fi
else
  echo "skip copy reaches the clipboard (no xclip)"
fi

# The menu opens a confirmation, which only real input can. Nothing beneath it can be reached, and
# Escape takes the safe choice.
click more
sleep 0.6
click clear
expect "dialog=true" "the menu opens a confirmation"
click inc
expect_still "count=2 .*dialog=true" "a click beneath the dialog reaches nothing"
xdotool key Escape
expect "dialog=false" "Escape cancels the confirmation"
expect "plums" "and the list is kept"

# Notes of many lines: Return puts a newline in a text area.
click notes
sleep 0.6
xdotool type --delay 30 "one"
xdotool key Return
xdotool type --delay 30 "two"
expect "notes=one|two" "typing reaches a text area, over two lines"

# A task makes a picture, which the app hands to an image widget.
click load
expect "picture=true" "a task's picture is shown"

# A producer started from a button ticks into the model while the gallery is otherwise idle,
# and does not keep the gallery from quitting.
click tab-Lists
sleep 1
click startClock
expect "ticks=2" "a producer's messages wake the loop"

xdotool key ctrl+q
expect_exit "ctrl-q quits"
exit $FAILED
