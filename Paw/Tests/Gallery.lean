/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # The gallery, in process

The example app driven through the runtime as a user would drive it. -/

namespace Paw.Tests.Gallery

open Paw

abbrev App := _root_.Gallery.app

def begin : Runtime App :=
  (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 480)) 0 Env.mock.measure).1

def at_ (rt : Runtime App) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App × List (Output _root_.Gallery.Msg) :=
  rt.step (.input { kind := k, time := t }) t

def click (rt : Runtime App) (k : String) (t : Nat) : Runtime App × List (Output _root_.Gallery.Msg) :=
  let p := at_ rt k
  let (rt, o1) := step rt (.press p .primary) t
  let (rt, o2) := step rt (.release p .primary) (t + 50)
  (rt, o1 ++ o2)

def requests (outs : List (Output _root_.Gallery.Msg)) : List Request :=
  outs.filterMap fun | .request r => some r | _ => none

def tests : TestM Unit := do
  let rt := begin
  check "the gallery draws within its window" (decide ((rt.tree.render rt.env).Within rt.window))
  let (rt, _) := click rt "inc" 1000
  let (rt, _) := click rt "inc" 1500
  let (rt, _) := click rt "dec" 2000
  checkEq "the counter" 1 rt.model.count
  let (rt, _) := click rt "name" 3000
  let (rt, _) := step rt (.text "Ada") 3600
  checkEq "a name typed" "Ada" rt.model.name
  let (rt, _) := click rt "draft" 4000
  let (rt, _) := step rt (.text "plums") 4600
  let (rt, _) := click rt "add" 5000
  checkEq "an item added" ["apples", "pears", "plums"] (rt.model.items.map (·.2))
  let (rt, _) := click rt "remove-1" 6000
  checkEq "an item removed" ["pears", "plums"] (rt.model.items.map (·.2))
  let (rt, outs) := click rt "link" 7000
  checkEq "the link opens" [Request.openUri "https://github.com/katzenpost"]
    ((requests outs).filter fun | .openUri _ => true | _ => false)
  let (rt, outs) := click rt "copy" 8000
  checkEq "the name is copied" [Request.setClipboard (SafeText.filter "Ada")]
    ((requests outs).filter fun | .setClipboard _ => true | _ => false)
  -- Assistive technology.
  let tree := rt.tree.accessTree rt.env
  let named (r : Role) (n : String) := tree.any fun a => a.access.role == r && a.access.name.text == n
  check "the window is the root" ((tree.head?.map (·.access.role)) == some .window)
  check "buttons by their captions" (named .button "Add" && named .button "Copy name")
  check "a link by its caption, with where it goes"
    (tree.any fun a => a.access.role == .link && a.access.name.text == "Katzenpost on GitHub" &&
      a.access.value.map (·.text) == some "https://github.com/katzenpost")
  check "a check box with its state" (tree.any fun a => a.access.role == .checkBox && a.access.checked == some false)
  check "a text field with its value" (tree.any fun a => a.access.role == .textInput &&
    a.access.value.map (·.text) == some "Ada")
  check "a password field" (tree.any fun a => a.access.role == .passwordInput)
  check "every node's children are nodes of the tree"
    (tree.all fun a => a.children.all fun c => tree.any (·.id == c))
  check "frames carry the tree" ((requests (rt.step (.resize (px 640) (px 560)) 8500).2).any
    fun | .access .. => true | _ => false)
  let linkId := (rt.tree.findKey? "link").map (·.id) |>.getD ⟨0⟩
  let incId := (rt.tree.findKey? "inc").map (·.id) |>.getD ⟨0⟩
  let before := rt.model.count
  let (rt, _) := rt.step (.access incId .press) 8600
  checkEq "a screen reader can press a button" (before + 1) rt.model.count
  let (rt, outs) := rt.step (.access linkId .press) 8700
  checkEq "but its press designates nothing, so the link stays closed" []
    ((requests outs).filter fun | .openUri _ => true | _ => false)
  let nameId := (rt.tree.findKey? "name").map (·.id) |>.getD ⟨0⟩
  let (rt, _) := rt.step (.access nameId .focus) 8800
  checkEq "a screen reader can move focus" (some nameId) rt.router.focused
  let (rt, outs) := rt.step (.access ⟨99999⟩ .press) 8850
  checkEq "an unknown widget is ignored" 0 outs.length
  -- The menu, the alert and the confirmation.
  let (rt, _) := click rt "more" 9000
  check "the menu opens" rt.model.menu
  let (rt, _) := click rt "about" 10000
  check "About opens an alert and closes the menu" (rt.model.about.isSome && !rt.model.menu)
  let (rt, _) := click rt "ok" 11000
  check "OK closes it" rt.model.about.isNone
  let (rt, _) := click rt "more" 12000
  let (rt, _) := click rt "clear" 13000
  check "Clear list asks first" rt.model.clearing.isSome
  let (rt, _) := step rt (.key .escape {} true) 13500
  check "Escape keeps the list" (rt.model.clearing.isNone && rt.model.items.length == 2)
  let (rt, _) := click rt "more" 14000
  let (rt, _) := click rt "clear" 15000
  let (rt, _) := click rt "accept" 16000
  check "Clear empties it" (rt.model.clearing.isNone && rt.model.items.isEmpty)
  let (rt, outs) := step rt (.key (.char 'q') { ctrl := true } true) 9000
  check "ctrl-q quits" (rt.quit && (requests outs).contains .quit)

end Paw.Tests.Gallery

namespace Paw.Tests.Link

open Paw

abbrev App := _root_.Gallery.app

def texts (rt : Runtime App) : List String :=
  match rt.present with
  | .request (.present s) => s.items.filterMap fun (_, d) => match d with
    | .text _ t _ => some t.text
    | _ => none
  | _ => []

def tests : TestM Unit := do
  checkEq "a link's destination: its scheme and host" "https://github.com"
    (Uri.destination "https://github.com/katzenpost?tab=repositories")
  checkEq "a port is part of the host" "http://example.org:8080" (Uri.destination "http://example.org:8080/a#b")
  checkEq "a mail link: its address" "mailto:ada@example.org" (Uri.destination "mailto:ada@example.org")
  check "a link Paw does not open is no link" (Link.parse? "javascript:alert(1)").isNone
  let rt := Paw.Tests.Gallery.begin
  let p := Paw.Tests.Gallery.at_ rt "link"
  let rt := (rt.step (.input { kind := .move p, time := 1000 }) 1000).1
  check "the destination is not shown at once" (!(texts rt).contains "https://github.com")
  let rt := (rt.advance 2000).1
  check "but once the pointer has rested on the link" ((texts rt).contains "https://github.com")
  let linkId := ((rt.tree.findKey? "link").map (·.id)).get!
  let (rt2, _) := (rt.step (.input { kind := .move ⟨0, 0⟩, time := 2100 }) 2100)
  let (rt2, _) := rt2.step (.access linkId .focus) 2200
  check "and while the link has focus" ((texts rt2).contains "https://github.com")
  let (_, outs) := rt.step (.input { kind := .move p, time := 2300 }) 2300
  check "the pointer is a hand over a link" (outs.all fun | .request (.cursor c) => c == .pointer | _ => true)

end Paw.Tests.Link
