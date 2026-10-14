/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Scrolls and splits

The gallery's Layout page: a split whose divider is dragged and moved by keys, a scroll down, and a
grid scrolled both ways. -/

namespace Paw.Tests.Split

open Paw

abbrev App := _root_.Gallery.app

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1
def box (rt : Runtime App) (k : String) : Rect := ((rt.tree.findKey? k).map (·.viewport)).getD default

def tests : TestM Unit := do
  let rt := (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1
  let tab := box rt "tab-Layout"
  let rt := step (step rt (.press ⟨tab.x0 + px 4, tab.y0 + px 4⟩ .primary) 100) (.release ⟨tab.x0 + px 4, tab.y0 + px 4⟩ .primary) 150
  let s := box rt "split"
  let items := box rt "items"
  let grid := box rt "grid"
  checkEq "the first side takes its share, up to the divider's line"
    ((s.width - Widgets.dividerWidth) * 350 / 1000 + Widgets.dividerWidth / 2) items.width
  checkEq "and the second the rest, after the divider" s.x1 grid.x1
  check "with the divider's line between" (grid.x0 - items.x1 == px 1)
  checkEq "which is where the line is drawn" (Widgets.dividerLine false 350 s).x0 items.x1
  -- Dragging the divider.
  let d := Widgets.dividerRect false 350 s
  let mid : Point := ⟨(d.x0 + d.x1) / 2, (d.y0 + d.y1) / 2⟩
  let (rt1, outs) := rt.step (.input { kind := .move mid, time := 1000 }) 1000
  check "the pointer takes the resize shape over the divider"
    (outs.any fun | .request (.cursor .resizeH) => true | _ => false)
  let rt := step rt1 (.press mid .primary) 1100
  let rt := step rt (.move ⟨s.x0 + s.width / 2, mid.y⟩) 1150
  check "dragging it shares the room anew" (480 ≤ rt.model.share && rt.model.share ≤ 520)
  let rt := step rt (.move ⟨s.x1 + px 100, mid.y⟩) 1200
  checkEq "no further than the end" 1000 rt.model.share
  let rt := step rt (.release mid .primary) 1250
  let rt := step rt (.key .left {} true) 1300
  checkEq "Left moves it back a twentieth, while it has focus" 950 rt.model.share
  -- The grid scrolls both ways.
  let rt := step (step rt (.key .left {} true) 1400) (.key .left {} true) 1500
  let g := box rt "grid"
  let over : Point := ⟨g.x0 + px 20, g.y0 + px 20⟩
  let rt := step rt (.wheel over 2 3) 1600
  let st := (rt.tree.findKey? "grid").bind (·.state? Widgets.ScrollState)
  check "the wheel scrolls the grid down and across" (st.any fun s => s.offset > 0 && s.offsetX > 0)
  let content := ((rt.tree.findKey? "grid").map (·.info.content)).getD default
  check "its content is wider than it" (content.width > g.width)
  -- A scroll across: wide content, its own height.
  let strip : Node Unit := Ui.col [Ui.hscroll (Ui.row ((List.range 20).map fun i => Ui.label s!"Column {i}")) "strip"]
  let t := (strip.init 1).1.resize Env.mock (Rect.ofXYWH 0 0 (px 200) (px 100))
  let sv := ((t.findKey? "strip").map (·.viewport)).getD default
  let sc := ((t.findKey? "strip").map (·.info.content)).getD default
  check "a scroll across lays its content out wider than itself" (sc.width > sv.width)
  checkEq "and as tall as itself, less its gutter" (sv.height - Widgets.gutter) sc.height
  check "the page draws within the window" (decide ((rt.tree.render rt.env).Within rt.window))
  let acc := (rt.tree.accessTree rt.env).find? fun a => a.access.role == .separator && a.access.range.isSome
  check "the divider is a separator to assistive technology, with its share" (acc.isSome)

end Paw.Tests.Split
