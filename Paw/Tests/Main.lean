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

open Paw.Tests

def main : IO UInt32 := do
  let results ← [
    ("ffi", Ffi.tests),
    ("geometry", Geometry.tests),
    ("text", Text.tests),
    ("secret", Secret.tests),
    ("codec", Codec.tests),
    ("scene", Scene.tests),
    ("layout", Layout.tests)].mapM fun (n, t) => runSuite n t
  return if results.all id then 0 else 1
