/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Secret
import Paw.Tests.Util

namespace Paw.Tests.Secret

open Paw

def tests : TestM Unit := do
  let s := Secret.ofString "hunter2"
  checkEq "length counts characters" 7 s.length
  checkEq "shown as dots" "•••••••" s.dots.text
  checkEq "dots are capped" 32 (Secret.ofString (String.ofList (List.replicate 100 'x'))).dots.text.length
  checkEq "use reveals the bytes to the caller" "hunter2".toUTF8.toList (s.use (·.toList))
  check "equal secrets" (s.eq (Secret.ofString "hunter2"))
  check "different secrets" (!s.eq (Secret.ofString "hunter3"))
  check "different lengths" (!s.eq (Secret.ofString "hunter22"))
  checkEq "push a character" 8 (s.push '!').length
  checkEq "pop a character" 6 s.pop.length
  checkEq "pop a multibyte character" "pa".toUTF8.toList ((Secret.ofString "paß").pop.use (·.toList))
  checkEq "pop empty" 0 (Secret.empty.pop).length
  checkEq "empty" 0 Secret.empty.length

end Paw.Tests.Secret
