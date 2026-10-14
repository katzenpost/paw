/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tests.Ffi

open Paw.Tests

def main : IO UInt32 := do
  let results ← [
    ("ffi", Ffi.tests)].mapM fun (n, t) => runSuite n t
  return if results.all id then 0 else 1
