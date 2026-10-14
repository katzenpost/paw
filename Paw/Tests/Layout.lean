/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Layout
import Paw.Tests.Util

/-! # Layout

Cases from monomer's `StackSpec`, with sizes given as monomer's style combinators give them, and
results rounded to whole pixels as monomer's tests round them. -/

namespace Paw.Tests.Layout

open Paw Paw.SizeReq

def r (x y w h : Int) : Rect := Rect.ofXYWH (px x) (px y) (px w) (px h)

/-- Units to the nearest pixel. -/
def roundPx (u : Int) : Int := (u + 32) / 64

def roundRect (a : Rect) : Int × Int × Int × Int :=
  (roundPx a.x0, roundPx a.y0, roundPx a.x1 - roundPx a.x0, roundPx a.y1 - roundPx a.y0)

/-- `n` pixels, as a size. -/
def sz (n : Nat) : Nat := (px n).toNat

def item (w h : SizeReq) (visible := true) : Item := { w, h, visible }

def any : SizeReq := fixedSize (sz 10)

def assignPx (l : Layout) (v : Rect) (items : List Item) : List (Int × Int × Int × Int) :=
  (l.assign v items).map roundRect

def tests : TestM Unit := do
  -- monomer: resizeFlexibleH
  checkEq "expanding items share extra space by their size"
    [(0, 0, 112, 640), (112, 0, 256, 640), (368, 0, 112, 640)]
    (assignPx hstack.toLayout (r 0 0 480 640)
      [item (flexSize (sz 70)) any, item (flexSize (sz 160)) any, item (flexSize (sz 70)) any])
  -- monomer: resizeFlexibleV
  checkEq "equal flexible items split evenly"
    [(0, 0, 640, 160), (0, 160, 640, 160), (0, 320, 640, 160)]
    (assignPx vstack.toLayout (r 0 0 640 480)
      [item any (flexSize (sz 20)), item any (flexSize (sz 20)), item any (flexSize (sz 20))])
  -- monomer: resizeStrictFlexH
  checkEq "fixed items get their size and the rest goes to the flexible one"
    [(0, 0, 100, 480), (100, 0, 100, 480), (200, 0, 440, 480)]
    (assignPx hstack.toLayout (r 0 0 640 480)
      [item (fixedSize (sz 100)) any, item (fixedSize (sz 100)) any, item (flexSize (sz 70)) any])
  -- monomer: resizeMixedH
  checkEq "mixed expanding items"
    [(0, 0, 196, 20), (196, 0, 444, 20)]
    (assignPx hstack.toLayout (r 0 0 640 20)
      [item (flexSize (sz 110)) any, item (flexSize (sz 250)) any])
  -- monomer: resizeAllV
  checkEq "all kinds of size request"
    [(0, 0, 640, 50), (0, 50, 640, 115), (0, 165, 640, 135), (0, 300, 640, 80), (0, 380, 640, 100)]
    (assignPx vstack.toLayout (r 0 0 640 480)
      [item any (fixedSize (sz 50)), item any (flexSize (sz 60)), item any (minSize (sz 70)),
       item any (maxSize (sz 80)), item any (rangeSize (sz 90) (sz 100))])
  -- monomer: resizeSpacerFixedH
  checkEq "a filler takes what is left"
    [(0, 0, 100, 480), (100, 0, 340, 480), (440, 0, 200, 480)]
    (assignPx hstack.toLayout (r 0 0 640 480)
      [item (fixedSize (sz 100)) any, item filler any, item (fixedSize (sz 200)) any])
  -- monomer: resizeChildSpacing
  checkEq "spacing between children"
    [(0, 0, 640, 3), (0, 5, 640, 3)]
    (assignPx (vstack (spacing := px 2)).toLayout (r 0 0 640 480)
      [item any (fixedSize (sz 3)), item any (fixedSize (sz 3))])
  checkEq "no spacing after a hidden child"
    [(0, 0, 640, 3), (0, 3, 640, 0), (0, 5, 640, 3)]
    (assignPx (vstack (spacing := px 2)).toLayout (r 0 0 640 480)
      [item any (fixedSize (sz 3)), item any (fixedSize (sz 3)) false, item any (fixedSize (sz 3))])
  -- Where Paw differs from monomer: a stack never places a child outside its box.
  let tight := (vstack.toLayout).assign (r 0 0 640 480)
    [item any (fixedSize (sz 200)), item any (fixedSize (sz 200)), item any (flexSize (sz 200)),
     item any (fixedSize (sz 200)), item any (fixedSize (sz 200))]
  checkEq "without enough space, children are cut at the box"
    [(0, 0, 640, 200), (0, 200, 640, 200), (0, 400, 640, 0), (0, 400, 640, 80)]
    ((tight.take 4).map roundRect)
  check "and the last is empty" (tight.getLast!.isEmpty)
  check "all within the box" (tight.all fun a => decide (a.Within (r 0 0 640 480)))
  -- Shrinking flexible items.
  checkEq "flexible items shrink in proportion"
    [(0, 0, 50, 10), (50, 0, 100, 10)]
    (assignPx hstack.toLayout (r 0 0 150 10)
      [item (flexSize (sz 100)) any, item (flexSize (sz 200)) any])
  checkEq "a factor weighs extra space"
    [(0, 0, 100, 10), (100, 0, 200, 10)]
    (assignPx hstack.toLayout (r 0 0 300 10)
      [item { extra := sz 1, factor := 1 } any, item { extra := sz 1, factor := 2 } any])
  -- Grids.
  checkEq "an hgrid splits evenly"
    [(0, 0, 100, 10), (100, 0, 100, 10), (200, 0, 100, 10)]
    (assignPx hgrid.toLayout (r 0 0 300 10) [item any any, item any any, item any any])
  checkEq "a vgrid with spacing"
    [(0, 0, 10, 40), (0, 50, 10, 40)]
    (assignPx (vgrid (spacing := px 10)).toLayout (r 0 0 10 90) [item any any, item any any])
  checkEq "a hidden grid cell takes no space"
    [(0, 0, 150, 10), (150, 0, 0, 10), (150, 0, 150, 10)]
    (assignPx hgrid.toLayout (r 0 0 300 10) [item any any, item any any false, item any any])
  -- zstack and box.
  checkEq "a zstack gives every child the whole box"
    [r 0 0 30 30, r 0 0 30 30] (zstack.assign (r 0 0 30 30) [item any any, item any any])
  checkEq "a box centers its child"
    [r 45 20 10 10] ((box {}).assign (r 0 0 100 50) [item any any])
  checkEq "a box aligns its child"
    [r 90 0 10 10] ((box { alignH := .right, alignV := .top }).assign (r 0 0 100 50) [item any any])
  checkEq "a box can expand its child"
    [r 0 0 100 50] ((box { expand := true }).assign (r 0 0 100 50) [item any any])
  checkEq "a box never lets its child out"
    [r 0 0 100 50] ((box {}).assign (r 0 0 100 50) [item (fixedSize (sz 500)) (fixedSize (sz 500))])
  -- Size requests of containers.
  checkEq "an empty stack wants nothing" (({} : SizeReq), ({} : SizeReq)) (hstack.toLayout.sizeReq [])
  checkEq "a stack sums its main axis and takes the largest across"
    (fixedSize (sz 30), fixedSize (sz 20))
    (hstack.toLayout.sizeReq [item (fixedSize (sz 10)) (fixedSize (sz 20)), item (fixedSize (sz 20)) (fixedSize (sz 5))])
  checkEq "a stack adds spacing between visible children"
    (fixedSize (sz 10), fixedSize (sz 3))
    ((vstack (spacing := px 2)).toLayout.sizeReq [item any (fixedSize (sz 1)), item any (fixedSize (sz 1)) false,
      item any (fixedSize (sz 0))])
  checkEq "a grid wants its largest cell times the count"
    (fixedSize (sz 60), fixedSize (sz 20))
    (hgrid.toLayout.sizeReq [item (fixedSize (sz 10)) (fixedSize (sz 20)), item (fixedSize (sz 30)) (fixedSize (sz 5))])
  checkEq "a zstack wants its largest child"
    (fixedSize (sz 30), fixedSize (sz 20))
    (zstack.sizeReq [item (fixedSize (sz 10)) (fixedSize (sz 20)), item (fixedSize (sz 30)) (fixedSize (sz 5))])
  checkEq "a box wants its child's size"
    (fixedSize (sz 7), fixedSize (sz 8)) ((box {}).sizeReq [item (fixedSize (sz 7)) (fixedSize (sz 8))])
  checkEq "mergeSum" ({ fixed := 3, flex := 5, extra := 7, factor := 2 } : SizeReq)
    (mergeSum { fixed := 1, flex := 2, extra := 3 } { fixed := 2, flex := 3, extra := 4, factor := 2 })
  checkEq "mergeMax of two fixed" (fixedSize 5) (mergeMax (fixedSize 3) (fixedSize 5))
  checkEq "mergeMax of fixed and flexible" ({ fixed := 3, flex := 7 } : SizeReq)
    (mergeMax (fixedSize 3) (maxSize 10))
  checkEq "mergeMax keeps the larger flex of a fixed item" ({ fixed := 3, flex := 10 } : SizeReq)
    (mergeMax { fixed := 3, flex := 10 } (maxSize 4))
  checkEq "mergeMax keeps the other's larger flex" ({ fixed := 3, flex := 10 } : SizeReq)
    (mergeMax (maxSize 4) { fixed := 3, flex := 10 })
  checkEq "maxSize" ({ flex := 4 } : SizeReq) (maxSize 4)
  -- The laws, on random items and boxes.
  let mut g : Rng := ⟨3⟩
  let mut ok := true
  let mut fits := true
  for _ in [0:400] do
    let (n, g1) := g.next 6
    let mut g' := g1
    let mut items : List Item := []
    for _ in [0:n] do
      let (a, g2) := g'.next 4000
      let (b, g3) := g2.next 4000
      let (c, g4) := g3.next 4000
      let (f, g5) := g4.next 3
      let (vis, g6) := g5.next 5
      g' := g6
      items := items ++ [item { fixed := a, flex := b, extra := c, factor := f } { fixed := b } (vis != 0)]
    let (w, g7) := g'.next 20000
    let (s, g8) := g7.next 300
    g := g8
    let v := Rect.ofXYWH 100 (-50) w w
    for l in [(hstack (spacing := s)).toLayout, (vstack (spacing := s)).toLayout,
              (hgrid (spacing := s)).toLayout, (vgrid (spacing := s)).toLayout, zstack, box {}] do
      let rs := l.assign v items
      if rs.length != items.length then ok := false
      if !rs.all (fun a => decide (a.Within v)) then ok := false
    for (isStack, l) in [(true, (hstack (spacing := s)).toLayout), (false, (hgrid (spacing := s)).toLayout)] do
      let rs := l.assign v items
      if !(rs.zip rs.tail).all (fun (a, b) => decide (a.Disjoint b)) then ok := false
      -- When the rigid sizes and spacing fit, nothing is cut. An item with factor 0 never
      -- resizes, so its flexible size is rigid too.
      let fixed := (items.filter (·.visible)).foldl
        (fun acc i => acc + i.w.fixed + (if i.w.factor = 0 then i.w.flex else 0)) 0
      let gaps := s * ((items.filter (·.visible)).length - 1)
      if isStack && fixed + gaps ≤ w then
        let used : Int := rs.foldl (fun acc a => acc + a.width) 0
        if used + gaps > (w : Int) then fits := false
  check "length, within and disjoint hold on random items" ok
  check "a stack fits its children when their rigid sizes fit" fits

end Paw.Tests.Layout
