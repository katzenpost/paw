#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# The gallery on a virtual X11 display.
set -eu
cd "$(dirname "$0")/../.."
WORK=$(mktemp -d "${TMPDIR:-/tmp}/paw-e2e.XXXXXX")
export WORK
trap 'rm -rf "$WORK"' EXIT
env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 1024x768x24" sh tests/e2e/x11-session.sh
