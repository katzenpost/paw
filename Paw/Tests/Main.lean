/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tests.Ffi
import Paw.Tests.Geometry
import Paw.Tests.Text
import Paw.Tests.Secret
import Paw.Tests.Codec
import Paw.Tests.Scene
import Paw.Tests.Layout
import Paw.Tests.Tree
import Paw.Tests.Route
import Paw.Tests.Cmd
import Paw.Tests.Runtime
import Paw.Tests.Widgets
import Paw.Tests.Gallery
import Paw.Tests.Linux
import Paw.Tests.Overlay
import Paw.Tests.Time
import Paw.Tests.Style
import Paw.Tests.Image
import Paw.Tests.Wrap
import Paw.Tests.Edit
import Paw.Tests.Choice
import Paw.Tests.Input
import Paw.Tests.Slider
import Paw.Tests.List
import Paw.Tests.Split
import Paw.Tests.Drag
import Paw.Tests.Color

open Paw.Tests

def main : IO UInt32 := do
  let results ← [
    ("ffi", Ffi.tests),
    ("geometry", Geometry.tests),
    ("text", Text.tests),
    ("secret", Secret.tests),
    ("codec", Codec.tests),
    ("scene", Scene.tests),
    ("layout", Layout.tests),
    ("tree", Tree.tests),
    ("route", Route.tests),
    ("cmd", Cmd.tests),
    ("runtime", Runtime.tests),
    ("widgets", Widgets.tests),
    ("gallery", Gallery.tests),
    ("linux", Linux.tests),
    ("overlay", Overlay.tests),
    ("time", Time.tests),
    ("style", Style.tests),
    ("image", Image.tests),
    ("wrap", Wrap.tests),
    ("edit", Edit.tests),
    ("choice", Choice.tests),
    ("input", Input.tests),
    ("slider", Slider.tests),
    ("list", List.tests),
    ("split", Split.tests),
    ("link", Link.tests),
    ("drag", Drag.tests),
    ("color", Color.tests)].mapM fun (n, t) => runSuite n t
  return if results.all id then 0 else 1
