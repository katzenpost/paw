/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Geometry
import Paw.Tests.Util

namespace Paw.Tests.Geometry

open Paw

def r (x y w h : Int) : Rect := Rect.ofXYWH (px x) (px y) (px w) (px h)

def tests : TestM Unit := do
  checkEq "px is 64 units" 640 (px 10)
  checkEq "ofXYWH corners" { x0 := 64, y0 := 128, x1 := 256, y1 := 384 : Rect } (r 1 2 3 4)
  checkEq "width" (px 3) (r 1 2 3 4).width
  checkEq "height" (px 4) (r 1 2 3 4).height
  checkEq "width of an inverted rect is zero" 0 ({ x0 := 5, y0 := 0, x1 := 1, y1 := 0 } : Rect).width
  check "a rect lies within itself" (decide ((r 0 0 10 10).Within (r 0 0 10 10)))
  check "inner within outer" (decide ((r 2 2 3 3).Within (r 0 0 10 10)))
  check "overhanging is not within" (!decide ((r 8 8 3 3).Within (r 0 0 10 10)))
  checkEq "intersection" (r 5 5 5 5) ((r 0 0 10 10).inter (r 5 5 10 10))
  check "intersection lies within both"
    (decide (((r 0 0 10 10).inter (r 5 5 10 10)).Within (r 0 0 10 10)) &&
     decide (((r 0 0 10 10).inter (r 5 5 10 10)).Within (r 5 5 10 10)))
  check "disjoint intersection is empty" ((r 0 0 2 2).inter (r 5 5 2 2)).isEmpty
  check "a rect with area is not empty" (!(r 0 0 1 1).isEmpty)
  check "contains its top-left point" ((r 1 1 2 2).contains ⟨px 1, px 1⟩)
  check "does not contain its bottom-right corner" (!(r 1 1 2 2).contains ⟨px 3, px 3⟩)
  check "side by side are disjoint" (decide ((r 0 0 5 5).Disjoint (r 5 0 5 5)))
  check "overlapping are not disjoint" (!decide ((r 0 0 5 5).Disjoint (r 4 4 5 5)))
  checkEq "add points" ({ x := 4, y := 6 } : Point) (⟨1, 2⟩ + ⟨3, 4⟩)
  check "a rect is valid" (decide ((r 0 0 2 2).Valid))
  check "an inverted rect is not" (!decide (({ x0 := 5, y0 := 0, x1 := 1, y1 := 0 } : Rect).Valid))
  checkEq "translate" (r 3 4 2 2) ((r 1 1 2 2).translate ⟨px 2, px 3⟩)
  checkEq "shrink by padding" (r 1 2 8 6) ((r 0 0 10 10).shrink (px 1) (px 2) (px 1) (px 2))
  checkEq "shrink past empty stays empty" 0 (((r 0 0 2 2).shrink (px 3) 0 (px 3) 0).width)
  -- The laws, on random rectangles.
  let mut g : Rng := ⟨7⟩
  let mut ok := true
  for _ in [0:500] do
    let mut v : Array Int := #[]
    for _ in [0:12] do
      let (n, g') := g.next 200
      v := v.push (n - 100)
      g := g'
    let a : Rect := ⟨v[0]!, v[1]!, v[2]!, v[3]!⟩
    let b : Rect := ⟨v[4]!, v[5]!, v[6]!, v[7]!⟩
    let c : Rect := ⟨v[8]!, v[9]!, v[10]!, v[11]!⟩
    if !decide ((a.inter b).Within b) then ok := false
    if decide (a.Within b) && decide (b.Within c) && !decide (a.Within c) then ok := false
    if decide (a.Disjoint b) != decide (b.Disjoint a) then ok := false
  check "laws hold on random rectangles" ok

end Paw.Tests.Geometry
