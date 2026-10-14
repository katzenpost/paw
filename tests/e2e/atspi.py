# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Reads the gallery as a screen reader would, over AT-SPI, and presses a button through it.
# Usage: atspi.py MODEL_LOG

import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

log = sys.argv[1]
failed = False


def ok(what):
    print(f"ok   {what}")


def fail(what):
    global failed
    print(f"FAIL {what}")
    failed = True


def walk(acc, depth=0):
    yield acc
    if depth > 40:
        return
    for i in range(acc.get_child_count()):
        child = acc.get_child_at_index(i)
        if child is not None:
            yield from walk(child, depth + 1)


def gallery_window():
    for _ in range(100):
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            if app is None:
                continue
            for acc in walk(app):
                if acc.get_role_name() in ("frame", "window") and acc.get_name() == "Paw gallery":
                    return acc
        time.sleep(0.1)
    return None


def last_line():
    with open(log) as f:
        lines = f.read().splitlines()
    return lines[-1] if lines else ""


window = gallery_window()
if window is None:
    fail("the gallery's window is on the accessibility bus")
    sys.exit(1)
ok("the gallery's window is on the accessibility bus")

nodes = list(walk(window))
by = {}
for n in nodes:
    by.setdefault((n.get_role_name(), n.get_name()), n)

if ("button", "+") in by:
    ok("a button is read with its caption")
else:
    fail("a button is read with its caption")
if ("check box", "I agree") in by:
    ok("a check box is read with its caption")
else:
    fail("a check box is read with its caption")
if any(n.get_role_name() == "label" and n.get_name().startswith("count:") for n in nodes):
    ok("a label is read")
else:
    fail("a label is read")

passwords = [n for n in nodes if n.get_role_name() == "password text"]
if not passwords:
    fail("the password field is announced as one")
else:
    ok("the password field is announced as one")
    text = passwords[0].get_text_iface()
    value = passwords[0].get_value_iface()
    leaked = (text is not None and text.get_text(0, -1)) or (value is not None and value.get_text())
    if leaked:
        fail("the password field tells no value")
    else:
        ok("the password field tells no value")

before = last_line()
button = by.get(("button", "+"))
action = button.get_action_iface() if button is not None else None
if action is None or action.get_n_actions() == 0:
    fail("a button can be pressed through AT-SPI")
else:
    action.do_action(0)
    for _ in range(50):
        if "count=1" in last_line():
            break
        time.sleep(0.1)
    if "count=1" in last_line():
        ok("a button can be pressed through AT-SPI")
    else:
        fail(f"a button can be pressed through AT-SPI (last: {last_line()}, before: {before})")

sys.exit(1 if failed else 0)
