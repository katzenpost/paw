/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Choices and tabs

The gallery's Choices page: radio buttons, option buttons and a toggle button, what assistive
technology is told of them, and tabs that keep each page's state. -/

namespace Paw.Tests.Choice

open Paw

abbrev App := _root_.Gallery.app
abbrev Msg := _root_.Gallery.Msg

def begin : Runtime App :=
  (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1

def at_ (rt : Runtime App) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1

def click (rt : Runtime App) (k : String) (t : Nat) : Runtime App :=
  let p := at_ rt k
  step (step rt (.press p .primary) t) (.release p .primary) (t + 50)

def access (rt : Runtime App) (k : String) : Option Access :=
  (rt.tree.findKey? k).bind fun n => (rt.tree.accessTree rt.env).find? (·.id == n.id.n) |>.map (·.access)

def tests : TestM Unit := do
  let rt := begin
  checkEq "the gallery opens on its first page" _root_.Gallery.Page.basics rt.model.page
  check "the Choices page is hidden" ((rt.tree.findKey? "page-Choices").any (!·.visible))
  checkEq "tabs are tabs to assistive technology, the first chosen" (some (Role.tab, some true))
    ((access rt "tab-Basics").map fun a => (a.role, a.checked))
  check "in a tab list" ((rt.tree.accessTree rt.env).any (·.access.role == .tabList))
  let rt := click rt "tab-Choices" 1000
  checkEq "a tab shows its page" _root_.Gallery.Page.choices rt.model.page
  check "and hides the others" ((rt.tree.findKey? "page-Basics").any (!·.visible))
  -- Radio buttons.
  checkEq "medium is chosen to start" (some (some true)) ((access rt "medium").map (·.checked))
  checkEq "a radio button is one to assistive technology" (some Role.radio) ((access rt "small").map (·.role))
  let rt := click rt "large" 2000
  checkEq "clicking one chooses it" _root_.Gallery.Size.large rt.model.size
  checkEq "and the others are not" (some (some false)) ((access rt "medium").map (·.checked))
  -- Option buttons, by keyboard.
  let rt := click rt "center" 3000
  checkEq "an option button chooses" _root_.Gallery.Align.center rt.model.align
  let rt := step rt (.key .tab {} true) 3100
  let rt := step rt (.key (.char ' ') {} true) 3200
  checkEq "Tab to the next and Space chooses it" _root_.Gallery.Align.right rt.model.align
  -- A toggle button.
  let rt := click rt "bold" 4000
  check "a toggle button turns on" rt.model.bold
  checkEq "and is pressed to assistive technology" (some (Role.toggle, some true))
    ((access rt "bold").map fun a => (a.role, a.checked))
  let rt := click rt "bold" 5000
  check "and off" (!rt.model.bold)
  check "separators are drawn" ((rt.tree.accessTree rt.env).any (·.access.role == .separator))
  check "the page draws within the window" (decide ((rt.tree.render rt.env).Within rt.window))
  -- Back to the first page: its state is kept.
  let rt := click rt "tab-Basics" 6000
  let rt := click rt "name" 7000
  let rt := step rt (.text "Ada") 7500
  let rt := click rt "tab-Choices" 8000
  let rt := click rt "tab-Basics" 9000
  checkEq "a page shown again keeps its state" "Ada" rt.model.name
  check "and its field's cursor" (((rt.tree.findKey? "name").bind (·.state? Widgets.TextFieldState)).any (·.cursor == 3))

end Paw.Tests.Choice
