/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Sliders and dials

The gallery's sliders and dial: the value under the pointer, dragging past the ends, keys and the
wheel, and assistive technology's steps. -/

namespace Paw.Tests.Slider

open Paw

abbrev App := _root_.Gallery.app

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1

def box (rt : Runtime App) (k : String) : Rect := ((rt.tree.findKey? k).map (·.viewport)).getD default

def begin : Runtime App :=
  let rt := (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1
  let r := box rt "tab-Choices"
  let p : Point := ⟨r.x0 + px 4, r.y0 + px 4⟩
  step (step rt (.press p .primary) 100) (.release p .primary) 150

def tests : TestM Unit := do
  let rt := begin
  let v := box rt "volume"
  let mid : Int := (v.y0 + v.y1) / 2
  -- The track runs from half a thumb in from each end.
  let x (frac : Int) : Int := v.x0 + px 8 + (v.width - px 16) * frac / 100
  let rt := step rt (.press ⟨x 75, mid⟩ .primary) 1000
  checkEq "pressing on the track takes the value there" 75 rt.model.volume.val
  let rt := step rt (.move ⟨x 20, mid⟩) 1050
  checkEq "dragging follows the pointer" 20 rt.model.volume.val
  let rt := step rt (.move ⟨v.x1 + px 200, mid + px 300⟩) 1100
  checkEq "dragging past the end stops at the greatest" 100 rt.model.volume.val
  let rt := step rt (.release ⟨v.x1 + px 200, mid⟩ .primary) 1150
  let rt := step rt (.move ⟨x 10, mid⟩) 1200
  checkEq "after release, moving changes nothing" 100 rt.model.volume.val
  let rt := step rt (.key .left {} true) 1300
  checkEq "Left steps down" 99 rt.model.volume.val
  let rt := step rt (.key .pageDown {} true) 1400
  checkEq "Page Down by a tenth" 89 rt.model.volume.val
  let rt := step rt (.key .home {} true) 1500
  checkEq "Home: the least" 0 rt.model.volume.val
  let rt := step rt (.key .down {} true) 1600
  checkEq "and no lower" 0 rt.model.volume.val
  let rt := step rt (.key .end_ {} true) 1700
  checkEq "End: the greatest" 100 rt.model.volume.val
  let rt := step rt (.wheel ⟨x 50, mid⟩ 0 3) 1800
  checkEq "the wheel steps" 97 rt.model.volume.val
  -- A vertical slider: up is more.
  let t := box rt "treble"
  let rt := step (step rt (.press ⟨(t.x0 + t.x1) / 2, t.y0⟩ .primary) 2000) (.release ⟨(t.x0 + t.x1) / 2, t.y0⟩ .primary) 2050
  checkEq "the top of a vertical slider is its greatest" 10 rt.model.treble.val
  -- A dial turns as it is dragged up.
  let d := box rt "bass"
  let c : Point := ⟨(d.x0 + d.x1) / 2, (d.y0 + d.y1) / 2⟩
  let rt := step rt (.press c .primary) 3000
  let rt := step rt (.move ⟨c.x, c.y - px 40⟩) 3050
  checkEq "a dial dragged up turns up" 7 rt.model.bass.val
  let rt := step rt (.move ⟨c.x, c.y + px 400⟩) 3100
  checkEq "and down, no lower than its least" 0 rt.model.bass.val
  let rt := step rt (.release c .primary) 3150
  -- Assistive technology.
  let vid := ((rt.tree.findKey? "volume").map (·.id)).get!
  let (rt, _) := rt.step (.access vid .decrement) 4000
  checkEq "assistive technology steps down" 96 rt.model.volume.val
  let (rt, _) := rt.step (.access vid .increment) 4100
  checkEq "and up" 97 rt.model.volume.val
  let acc := (rt.tree.accessTree rt.env).find? (·.id == vid.n)
  checkEq "a slider with its range" (some (Role.slider, some (0, 100, 97))) (acc.map fun a => (a.access.role, a.access.range))
  check "the page draws within the window" (decide ((rt.tree.render rt.env).Within rt.window))

end Paw.Tests.Slider
