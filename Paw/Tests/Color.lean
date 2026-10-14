/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Colors, shadows and theme switches

The gallery's Colors page: a color picker's sliders and fields, a color popup, a shadow drawn
within its own box, and a part of the window in the other theme. -/

namespace Paw.Tests.Color

open Paw

abbrev App := _root_.Gallery.app

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1

def center (rt : Runtime App) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def click (rt : Runtime App) (k : String) (t : Nat) : Runtime App :=
  let p := center rt k
  step (step rt (.press p .primary) t) (.release p .primary) (t + 50)

def tests : TestM Unit := do
  checkEq "a color as hex" "#2A6FDB" (Widgets.Color.hex (Color.rgb 0x2A 0x6F 0xDB))
  checkEq "with its alpha if it is not opaque" "#C03060C8" (Widgets.Color.hex (Color.rgba 0xC0 0x30 0x60 200))
  let rt := click (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1 "tab-Colors" 100
  checkEq "the Colors tab" _root_.Gallery.Page.colors rt.model.page
  -- The picker.
  let r := ((rt.tree.findKey? "RField").map (·.viewport)).get!
  let q : Point := ⟨r.x0 + px 4, r.y0 + px 4⟩
  let rt := step (step (step (step rt (.press q .primary) 1000) (.release q .primary) 1010)
    (.key (.char 'a') { ctrl := true } true) 1100) (.text "255") 1200
  checkEq "the red field sets red" 255 rt.model.paint.r.toNat
  check "and nothing else" (rt.model.paint.g.toNat == 0x6F && rt.model.paint.b.toNat == 0xDB)
  let rt := step rt (.key .up {} true) 1300
  checkEq "and no higher than 255" 255 rt.model.paint.r.toNat
  let g := ((rt.tree.findKey? "GSlider").map (·.viewport)).get!
  let rt := step (step rt (.press ⟨g.x0, (g.y0 + g.y1) / 2⟩ .primary) 2000) (.release ⟨g.x0, (g.y0 + g.y1) / 2⟩ .primary) 2010
  checkEq "the green slider at its start sets green to nothing" 0 rt.model.paint.g.toNat
  check "a swatch is a color well, telling its color" ((rt.tree.accessTree rt.env).any fun a =>
    a.access.role == .colorWell && a.access.value.map (·.text) == some "#FF00DB")
  -- The popup.
  let rt := click rt "ink" 3000
  check "clicking the ink swatch opens a picker" (rt.model.inkOpen && rt.router.overlay.isSome)
  check "with an alpha slider" (rt.tree.findKey? "ASlider").isSome
  let a := ((rt.tree.findKey? "ASlider").map (·.viewport)).get!
  let rt := step (step rt (.press ⟨a.x1 - px 1, (a.y0 + a.y1) / 2⟩ .primary) 4000) (.release ⟨a.x1 - px 1, (a.y0 + a.y1) / 2⟩ .primary) 4010
  checkEq "and the alpha slider at its end makes it opaque" 255 rt.model.ink.a.toNat
  let rt := step rt (.key .escape {} true) 4100
  check "Escape closes it" (!rt.model.inkOpen)
  -- The shadow.
  let card := ((rt.tree.findKey? "card").map (·.viewport)).get!
  match rt.tree.find? ((rt.tree.findKey? "card").map (·.id)).get! with
  | some _ =>
    let shadowNode := rt.tree.index Env.mock |>.nodes.toList.find? fun (_, r, _, _) => r.x0 < card.x0 && card.Within r
    check "a shadow keeps room around what it shadows" shadowNode.isSome
  | none => check "the card" false
  check "and draws within its own box, as everything does" (decide ((rt.tree.render rt.env).Within rt.window))
  -- A part of the window in the other theme.
  let preview := (rt.tree.findKey? "previewToggle").map (·.viewport)
  check "the preview is drawn dark" (match rt.present with
    | .request (.present s) => s.items.any fun (_, d) => match d with
      | .fill _ c _ => c == Theme.dark.background | _ => false
    | _ => false)
  let rt := click rt "previewToggle" 5000
  check "and switched, light" (!rt.model.previewDark && preview.isSome)

end Paw.Tests.Color
