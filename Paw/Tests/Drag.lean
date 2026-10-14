/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Dragging and dropping

The gallery's Drag page: tasks dragged between columns, the drag drawn under the pointer, drops
designated only as clicks are, and drags cancelled. -/

namespace Paw.Tests.Drag

open Paw

abbrev App := _root_.Gallery.app

def step (rt : Runtime App) (k : InputKind) (t : Nat) (synthetic := false) : Runtime App :=
  (rt.step (.input { kind := k, time := t, synthetic }) t).1

def center (rt : Runtime App) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def begin : Runtime App :=
  let rt := (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1
  let p := center rt "tab-Drag"
  step (step rt (.press p .primary) 100) (.release p .primary) 150

/-- `task` pressed at 1000, moved over `to`, and the deliveries of the release there. -/
def dragTo (rt : Runtime App) (task to : String) (synthetic := false) : Runtime App × List Delivery :=
  let a := center rt task
  let b := center rt to
  let rt := step rt (.press a .primary) 1000
  let rt := step rt (.move ⟨a.x + px 10, a.y⟩) 1050
  let rt := step rt (.move b) 1100
  let ds := (rt.router.route rt.tree { kind := .release b .primary, time := 1150, synthetic }).2
  (step rt (.release b .primary) 1150 synthetic, ds)

def tests : TestM Unit := do
  let rt := begin
  checkEq "the Drag tab" _root_.Gallery.Page.drag rt.model.page
  -- Mid-drag.
  let a := center rt "Test it"
  let mid := step (step (step rt (.press a .primary) 1000) (.move ⟨a.x + px 10, a.y⟩) 1050) (.move (center rt "done")) 1100
  check "a press and a move is a drag" (mid.router.drag.any (·.active))
  check "drawn faint under the pointer" (!mid.dragScene.items.isEmpty &&
    mid.dragScene.items.all fun (_, d) => match d with
      | .fill _ c _ => c.a < 255 | .stroke _ c _ _ => c.a < 255 | .text _ _ s => s.color.a < 255 | _ => true)
  check "and within the window" (decide (mid.dragScene.Within mid.window))
  checkEq "a drop target under it lights up" (some (Theme.light.accent))
    (((mid.tree.findKey? "done").map fun n => (n.render mid.env).items.findSome? fun (_, d) => match d with
      | .stroke _ c _ _ => some c | _ => none)).join
  -- The drop.
  let (rt1, ds) := dragTo rt "Test it" "done"
  checkEq "dropped on Done, the task is done" ["Test it"] rt1.model.done
  checkEq "and not to do" ["Write the plan", "Ship it"] rt1.model.todo
  check "the drop is the user's choice" (ds.any fun d => d.event matches .drop _ && d.designation.isSome)
  check "and is no click" (!ds.any fun d => d.event matches .click ..)
  checkEq "the drag is over" none rt1.router.drag
  let (_, ds) := dragTo rt "Test it" "done" (synthetic := true)
  check "a synthetic release drops, but designates nothing" (ds.any fun d => d.event matches .drop _ && d.designation.isNone)
  let (rt2, _) := dragTo rt1 "Test it" "todo"
  checkEq "dragged back" ["Write the plan", "Ship it", "Test it"] rt2.model.todo
  -- Not drops.
  let (rt3, _) := dragTo rt "Test it" "tab-Basics"
  checkEq "dropped on what takes no drops, nothing happens" ([] : List String) rt3.model.done
  let p := center rt "Write the plan"
  let rt4 := step (step (step rt (.press p .primary) 1000) (.move ⟨p.x + px 2, p.y⟩) 1050) (.release p .primary) 1100
  checkEq "a press that barely moves is a click, not a drag" 1 rt4.model.count
  let esc := step (step mid (.key .escape {} true) 1120) (.release (center rt "done") .primary) 1150
  checkEq "Escape cancels a drag" ([] : List String) esc.model.done
  -- A target takes only its own type.
  let target : Widget Unit := Widgets.dropTarget (α := Nat) fun _ => ()
  let env := { Env.mock with dragged := some (Dynamic.mk "words") }
  check "a drop of another type goes on to the targets around" (target.handle env target.init default (.drop ⟨0, 0⟩)).isNone

end Paw.Tests.Drag
