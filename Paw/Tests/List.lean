/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Lists and dropdowns

The gallery's Lists page: choosing in a select list by pointer and keys, scrolling to the item
chosen, and dropdowns opened, chosen in and closed. -/

namespace Paw.Tests.List

open Paw

abbrev App := _root_.Gallery.app

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1

def at_ (rt : Runtime App) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def click (rt : Runtime App) (k : String) (t : Nat) : Runtime App :=
  let p := at_ rt k
  step (step rt (.press p .primary) t) (.release p .primary) (t + 50)

def focusOn (rt : Runtime App) (k : String) (t : Nat) : Runtime App :=
  ((rt.tree.findKey? k).map fun n => (rt.step (.access n.id .focus) t).1).getD rt

def key (rt : Runtime App) (k : Key) (t : Nat) : Runtime App := step rt (.key k {} true) t

def offset (rt : Runtime App) : Int :=
  (((rt.tree.findKey? "fruits").bind (·.state? Widgets.ScrollState)).map (·.offset)).getD (-1)

def tests : TestM Unit := do
  let rt := click (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1 "tab-Lists" 100
  checkEq "the Lists tab" _root_.Gallery.Page.lists rt.model.page
  let rt := click rt "banana" 1000
  checkEq "clicking a row chooses it" "banana" rt.model.fruit
  let acc := rt.tree.accessTree rt.env
  check "a list of items, the chosen one checked" (acc.any (·.access.role == .list) &&
    acc.any fun a => a.access.role == .listItem && a.access.name.text == "banana" && a.access.checked == some true)
  let rt := focusOn rt "fruits" 2000
  let rt := key rt .down 2100
  checkEq "Down chooses the next" "blackberry" rt.model.fruit
  let rt := key rt .end_ 2200
  checkEq "End the last" "pear" rt.model.fruit
  check "and scrolls to it" (offset rt > 0)
  let rt := key rt .home 2300
  checkEq "Home the first" "apple" rt.model.fruit
  checkEq "and scrolls back" 0 (offset rt)
  let rt := key rt .up 2400
  checkEq "and no further" "apple" rt.model.fruit
  -- A dropdown.
  let rt := click rt "country" 3000
  check "clicking a dropdown opens it" rt.model.countryOpen
  check "as a popup" rt.router.overlay.isSome
  let rt := click rt "ke" 4000
  checkEq "choosing an item" ("ke", "Kenya") rt.model.country
  check "closes it" (!rt.model.countryOpen && rt.router.overlay.isNone)
  checkEq "and the button shows it" (some (some "Kenya"))
    (((rt.tree.accessTree rt.env).find? (·.access.role == .comboBox)).map fun a => a.access.value.map (·.text))
  let rt := focusOn rt "country" 5000
  let rt := key rt .down 5100
  check "Down opens a focused dropdown" rt.model.countryOpen
  let rt := key rt .down 5200
  checkEq "and then chooses the next" ("pe", "Peru") rt.model.country
  let rt := key rt .up 5300
  checkEq "Up the one before" ("ke", "Kenya") rt.model.country
  let rt := key rt .escape 5400
  check "Escape closes it" (!rt.model.countryOpen)
  let rt := click rt "color" 6000
  let rt := click rt "orange" 7000
  checkEq "a dropdown of text" "orange" rt.model.color
  check "the page draws within the window" (decide ((rt.tree.render rt.env).Within rt.window))

end Paw.Tests.List
