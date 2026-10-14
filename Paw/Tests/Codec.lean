/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Codec
import Paw.Tests.Util

namespace Paw.Tests.Codec

open Paw Paw.Codec

def tests : TestM Unit := do
  -- The byte layouts the Rust layer must match.
  checkEq "nat 0" [0] (nat.enc 0)
  checkEq "nat 127" [127] (nat.enc 127)
  checkEq "nat 128" [0x80, 1] (nat.enc 128)
  checkEq "nat 300" [0xAC, 2] (nat.enc 300)
  checkEq "int 0" [0] (int.enc 0)
  checkEq "int -1" [1] (int.enc (-1))
  checkEq "int 1" [2] (int.enc 1)
  checkEq "int -64" [127] (int.enc (-64))
  checkEq "int 64" [0x80, 1] (int.enc 64)
  checkEq "bool" [0, 1] (bool.enc false ++ bool.enc true)
  checkEq "u8" [7] (u8.enc 7)
  checkEq "char" [0xE9, 1] (char.enc 'é')
  checkEq "string" [2, 104, 105] (string.enc "hi")
  checkEq "list" [3, 2, 4, 6] ((list int).enc [1, 2, 3])
  checkEq "pair" [1, 2] ((pair nat nat).enc (1, 2))
  -- Decoding refuses what is not well formed.
  checkEq "empty input" none (nat.decodeAll [])
  checkEq "a varint cut short" none (nat.decodeAll [0x80])
  checkEq "trailing bytes" none (nat.decodeAll [1, 2])
  checkEq "bool 2" none (bool.decodeAll [2])
  checkEq "a surrogate is no char" none (char.decodeAll (nat.enc 0xD800))
  checkEq "past the last char" none (char.decodeAll (nat.enc 0x110000))
  checkEq "a list shorter than its count" none ((list nat).decodeAll [3, 1, 2])
  checkEq "u8 of nothing" none (u8.decodeAll [])
  -- Round trips through ByteArray, on random values.
  let mut g : Rng := ⟨11⟩
  let mut ok := true
  for _ in [0:500] do
    let (n, g') := g.next 1000000
    let (k, g'') := g'.next 20
    g := g''
    let i : Int := (n : Int) - 500000
    let xs : List Int := (List.range k).map fun (j : Nat) => (j : Int) * i
    if int.decodeAll (ofBytes (toBytes (int.enc i))) != some i then ok := false
    if (list int).decodeAll ((list int).enc xs) != some xs then ok := false
    if nat.decodeAll (nat.enc (n * n * n)) != some (n * n * n) then ok := false
  check "random round trips" ok
  checkEq "string round trip" (some "héllo 🚀") (string.decodeAll (string.enc "héllo 🚀"))

end Paw.Tests.Codec
