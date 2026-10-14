/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Ui
import Paw.Runtime
import Paw.Tests.Util

/-! # A scroll that follows its end

Lines added to a following scroll stay in view while it is at its end; scrolled back, it stays put;
scrolled to the end again, it follows again. A scroll that does not follow starts at the top. -/

namespace Paw.Tests.Follow

open Paw

structure Model where
  lines : Nat := 5
  deriving Repr, BEq, Inhabited

inductive Msg where
  | more
  deriving Repr, BEq

def update : (o : Origin) → Msg → UpdateM Model Msg [] o Unit
  | _, .more => modify fun (m, cs) => ({ m with lines := m.lines + 3 }, cs)

/-- A 60-pixel scroll over 20-pixel lines. -/
def view (follow : Bool) (m : Model) : Node Msg :=
  Ui.col (spacing := 0) [
    Ui.height (px 60) (Ui.scroll (Ui.col (spacing := 0)
      ((List.range m.lines).map fun i => Ui.label s!"line {i}")) (follow := follow))
      |>.withInfo ({ · with key := some "sc" })]

def app (follow : Bool) : App [] := { Model := Model, Msg := Msg, init := {}, update, view := view follow }

def begin (follow : Bool) : Runtime (app follow) :=
  (Paw.Runtime.start (app follow) (Rect.ofXYWH 0 0 (px 200) (px 200)) 0 Env.mock.measure).1

def box {follow : Bool} (rt : Runtime (app follow)) : Rect :=
  (rt.tree.findKey? "sc").map (·.viewport) |>.getD default

/-- Where the line `i` is drawn, if it is. -/
def lineY {follow : Bool} (rt : Runtime (app follow)) (i : Nat) : Option Int :=
  (rt.tree.render rt.env).items.findSome? fun
    | (_, .text p t _) => if t.text == s!"line {i}" then some p.y else none
    | _ => none

def wheel {follow : Bool} (rt : Runtime (app follow)) (dy : Int) (t : Nat) : Runtime (app follow) :=
  let b := box rt
  (rt.step (.input { kind := .wheel ⟨b.x0 + px 10, b.y0 + px 5⟩ 0 dy, time := t }) t).1

def more {follow : Bool} (rt : Runtime (app follow)) (t : Nat) : Runtime (app follow) :=
  (rt.results [.more] t).1

def tests : TestM Unit := do
  let rt := begin true
  let sc := box rt
  let atEnd := some (sc.y1 - px 20)
  checkEq "a following scroll starts at its end" atEnd (lineY rt 4)
  let rt := more rt 1000
  checkEq "and follows lines added" atEnd (lineY rt 7)
  let rt := wheel rt (-1) 1100
  checkEq "the wheel scrolls it back" (some (sc.y0 + Widgets.scrollStep)) (lineY rt 5)
  let rt := more rt 1200
  checkEq "scrolled back, it stays put as lines are added" (some (sc.y0 + Widgets.scrollStep)) (lineY rt 5)
  let rt := wheel rt 99 1300
  checkEq "scrolled to the end again" atEnd (lineY rt 10)
  let rt := more rt 1400
  checkEq "it follows again" atEnd (lineY rt 13)
  let rt := begin false
  checkEq "a scroll that does not follow starts at the top" (some (box rt).y0) (lineY rt 0)
  let rt := more rt 1000
  checkEq "and stays there" (some (box rt).y0) (lineY rt 0)

end Paw.Tests.Follow
