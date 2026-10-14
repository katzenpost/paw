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
  let (rt, outs) := step rt (.key (.char 'q') { ctrl := true } true) 9000
  check "ctrl-q quits" (rt.quit && (requests outs).contains .quit)

end Paw.Tests.Gallery
