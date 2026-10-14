/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Ffi
import Paw.Tests.Util

namespace Paw.Tests.Ffi

def tests : TestM Unit := do
  checkEq "the Rust layer speaks our byte formats" Paw.Ffi.abiVersion (Paw.Ffi.rustAbiVersion ())
  check "abiMatches" Paw.Ffi.abiMatches

end Paw.Tests.Ffi
