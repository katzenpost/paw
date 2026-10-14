/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Ffi
import Paw.Scene
import Paw.Tests.Util

/-! # The Rust layer

Lean and Rust agree on the byte formats: scenes Lean encodes, Rust decodes and encodes back to the
same bytes. -/

namespace Paw.Tests.Ffi

open Paw

def randomInt (g : Rng) : Int × Rng :=
  let (n, g) := g.next 2000000
  ((n : Int) - 1000000, g)

def randomRect (g : Rng) : Rect × Rng :=
  let (a, g) := randomInt g
  let (b, g) := randomInt g
  let (c, g) := randomInt g
  let (d, g) := randomInt g
  (⟨a, b, c, d⟩, g)

def randomColor (g : Rng) : Color × Rng :=
  let (r, g) := g.next 256
  let (gr, g) := g.next 256
  let (b, g) := g.next 256
  let (a, g) := g.next 256
  (⟨r.toUInt8, gr.toUInt8, b.toUInt8, a.toUInt8⟩, g)

def randomText (g : Rng) : SafeText × Rng := Id.run do
  let (len, g) := g.next 12
  let mut g := g
  let mut s := ""
  for _ in [0:len] do
    let (n, g') := g.next 0x1FFFF
    g := g'
    s := s.push (Char.ofNat n)
  return (SafeText.filter s, g)

def randomDraw (g : Rng) : Draw × Rng :=
  let (kind, g) := g.next 5
  let (r, g) := randomRect g
  let (c, g) := randomColor g
  let (i, g) := randomInt g
  let (j, g) := randomInt g
  match kind with
  | 0 => (.fill r c i, g)
  | 1 => (.stroke r c i j, g)
  | 2 => (.image r j.natAbs c.a, g)
  | 3 =>
    let (n, g) := g.next 6
    let pts : List Point := (List.range n).map fun (k : Nat) => ⟨i + Int.ofNat k, j - Int.ofNat k⟩
    let (f, g) := g.next 2
    let (st, g) := g.next 2
    (.path pts (f == 1) (if f == 1 then some c else none) (if st == 1 then some (c, i) else none), g)
  | _ =>
    let (t, g) := randomText g
    let (b, g) := g.next 2
    (.text ⟨i, j⟩ t { size := i, color := c, bold := b == 1 }, g)

def randomScene (g : Rng) : Scene × Rng := Id.run do
  let (n, g) := g.next 8
  let mut g := g
  let mut items := []
  for _ in [0:n] do
    let (r, g') := randomRect g
    let (d, g'') := randomDraw g'
    g := g''
    items := items ++ [(r, d)]
  return (Scene.ofList items, g)

def echoes (s : Scene) : Bool :=
  let bytes := Scene.codec.bytes s
  Ffi.sceneEcho bytes == bytes

def tests : TestM Unit := do
  checkEq "the Rust layer speaks our byte formats" Ffi.abiVersion (Ffi.rustAbiVersion ())
  Ffi.wake
  check "a wake with no window open does nothing" true
  check "abiMatches" Ffi.abiMatches
  check "an empty scene echoes" (echoes Scene.empty)
  checkEq "malformed bytes echo as nothing" 0 (Ffi.sceneEcho ⟨#[1, 0, 0, 0, 0, 9]⟩).size
  let mut g : Rng := ⟨99⟩
  let mut ok := true
  for _ in [0:300] do
    let (s, g') := randomScene g
    g := g'
    if !echoes s then ok := false
  check "random scenes echo byte for byte" ok

end Paw.Tests.Ffi
