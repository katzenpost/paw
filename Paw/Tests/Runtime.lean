/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Tests.Util

/-! # The runtime

An app driven through `Runtime.step` as the platform would drive it, and the IO loop run against a
scripted fake platform. -/

namespace Paw.Tests.Runtime

open Paw

def sz (n : Nat) : Nat := (px n).toNat

inductive Msg where
  | inc
  | openIt
  | fetch
  | got (n : Nat)
  | bye
  deriving Repr, BEq, Inhabited

structure Model where
  count : Nat := 0
  opened : Nat := 0
  got : List Nat := []
  deriving Repr, BEq, Inhabited

/-- A button: a click emits `m`; a click with a copy request also asks to copy. -/
def clicker (m : Msg) (copy : Bool := false) : Widget Msg := Widget.Spec.build (σ := NoState) {
  kind := "clicker"
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz 40), SizeReq.fixedSize (sz 10))
  render := fun _ _ v => Scene.draw v (.fill v Color.black 0)
  render_within := fun _ _ v => Scene.draw_within _ (Rect.within_refl v)
  handle := fun _ st _ e => match e with
    | .click .. => some (st, [.emit m] ++ (if copy then [.copy (SafeText.trusted "copied")] else []))
    | _ => none
  focusable := true }

/-- Shows a number as the width of a bar. -/
def bar (n : Nat) : Widget Msg := Widget.Spec.build (σ := NoState) {
  kind := "bar"
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz n), SizeReq.fixedSize (sz 10))
  render := fun _ _ v => Scene.draw v (.fill v Color.white 0)
  render_within := fun _ _ v => Scene.draw_within _ (Rect.within_refl v) }

/-- A container that handles the wheel for its children, which do not. -/
def wheelCatcher : Widget Msg := Widget.Spec.build (σ := NoState) {
  kind := "wheels"
  init := {}
  sizeReq := fun _ _ => ({}, {})
  render := fun _ _ _ => Scene.empty
  render_within := fun _ _ v => Scene.empty_within v
  handle := fun _ st _ e => match e with
    | .wheel .. => some (st, [.emit .inc])
    | _ => none }

abbrev caps : List Cap := [.openUri, .io]

def update : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  | _, .inc => modify fun (m, cs) => ({ m with count := m.count + 1 }, cs)
  | .user d, .openIt => do
    if let some e := Effect.openUri? "link" "https://example.org" then
      if h : e.DesignatedBy d then
        emit (.effect d e (by decide) h)
        modify fun (m, cs) => ({ m with opened := m.opened + 1 }, cs)
  | .other, .openIt => pure ()
  | _, .fetch => emit (.task (pure (.got 7)) (by decide))
  | _, .got n => modify fun (m, cs) => ({ m with got := m.got ++ [n] }, cs)
  | _, .bye => emit .quit

/-- Rows 10 pixels tall: inc (y 0), link (y 10), fetch (y 20), copy (y 30), a bar as wide as the
count (y 40), and a wheel catcher around a bar (y 50). -/
def view (m : Model) : Node Msg :=
  Node.container vstack.toLayout [
    Node.leaf (clicker .inc) "inc",
    Node.leaf (clicker .openIt) "link",
    Node.leaf (clicker .fetch) "fetch",
    Node.leaf (clicker .bye (copy := true)) "copy",
    Node.leaf (bar m.count) "bar",
    Node.containerWith wheelCatcher vstack.toLayout [Node.leaf (bar 1)]]

def app : App caps := { Model := Model, Msg := Msg, init := {}, update, view }

def begin : Runtime app × List (Output Msg) :=
  Paw.Runtime.start app (Rect.ofXYWH 0 0 (px 100) (px 100)) 0 Env.mock.measure

def requests (outs : List (Output Msg)) : List Request :=
  outs.filterMap fun | .request r => some r | .task _ => none

def tasks (outs : List (Output Msg)) : Nat :=
  (outs.filter fun | .task _ => true | _ => false).length

def presents (outs : List (Output Msg)) : Nat :=
  (requests outs).filter (fun | .present _ => true | _ => false) |>.length

def input (k : InputKind) (t : Nat) (synthetic := false) : WindowEvent :=
  .input { kind := k, time := t, synthetic }

/-- Clicks at pixel `(x, y)` at time `t`, with the release 50 ms later. -/
def click (rt : Runtime app) (x y : Int) (t : Nat) (synthetic := false) :
    Runtime app × List (Output Msg) :=
  let p : Point := ⟨px x, px y⟩
  let (rt, o1) := rt.step (input (.press p .primary) t synthetic) t
  let (rt, o2) := rt.step (input (.release p .primary) (t + 50) synthetic) (t + 50)
  (rt, o1 ++ o2)

/-- A platform that plays `script`, one list of events per poll, and records what it is asked. -/
def fakePlatform (script : IO.Ref (List (List WindowEvent))) (log : IO.Ref (Array Request))
    (clock : IO.Ref Nat) : Platform where
  poll := fun _ => do
    clock.modify (· + 100)
    match ← script.get with
    | evs :: rest => script.set rest; return evs
    | [] => return [.close]
  now := clock.get
  size := pure (px 100, px 100)
  measure := Env.mock.measure
  perform := fun r => log.modify (·.push r)

def tests : TestM Unit := do
  let (rt, outs) := begin
  checkEq "the first scene is drawn" 1 (presents outs)
  checkEq "the tree fills the window" (Rect.ofXYWH 0 0 (px 100) (px 100)) rt.tree.viewport
  -- A click on inc updates the model, rebuilds the view and draws.
  let (rt, outs) := click rt 5 5 1000
  checkEq "the click reaches update" 1 rt.model.count
  check "and the scene is drawn again" (presents outs ≥ 1)
  checkEq "the view was rebuilt: the bar asks to be as wide as the count"
    (SizeReq.fixedSize (sz 1)) ((rt.tree.children[4]!).sizeReq rt.env).1
  -- Designation: a stable, real click opens the link; others do not.
  let (rt, outs) := click rt 5 15 2000
  checkEq "a real click on the link opens it" [Request.openUri "https://example.org"]
    ((requests outs).filter fun | .openUri _ => true | _ => false)
  let (rt, outs) := click rt 5 15 3000 (synthetic := true)
  checkEq "a synthetic click opens nothing" [] ((requests outs).filter fun | .openUri _ => true | _ => false)
  checkEq "opened once" 1 rt.model.opened
  let (_, early) := click begin.1 5 15 100
  checkEq "a click before the link has been still opens nothing" []
    ((requests early).filter fun | .openUri _ => true | _ => false)
  -- Tasks: the result comes back with origin other.
  let (rt, outs) := click rt 5 25 4000
  checkEq "fetch starts a task" 1 (tasks outs)
  let (rt, outs) := rt.taskResult (.got 7) 4100
  checkEq "the result reaches update" [7] rt.model.got
  checkEq "and draws" 1 (presents outs)
  -- Bubbling: the wheel over the inner bar reaches the catcher around it.
  let before := rt.model.count
  let (rt, _) := rt.step (input (.wheel ⟨px 5, px 55⟩ 0 1) 4200) 4200
  checkEq "the wheel bubbles up to a widget that handles it" (before + 1) rt.model.count
  -- Nothing to do: no output.
  let (_, outs) := rt.step (input (.move ⟨px 5, px 5⟩) 4250) 4250
  check "a hover change draws" (presents outs == 1)
  check "but does not resend the accessibility tree"
    (!(requests outs).any fun | .access .. => true | _ => false)
  let (rt, _) := rt.step (input (.move ⟨px 99, px 99⟩) 4300) 4300
  let (rt, outs) := rt.step (input (.move ⟨px 98, px 98⟩) 4310) 4310
  checkEq "moving over the same empty place draws nothing" 0 outs.length
  -- Resize.
  let (rt, outs) := rt.step (.resize (px 50) (px 60)) 4400
  checkEq "a resize lays out again and draws" 1 (presents outs)
  checkEq "the tree takes the new size" (Rect.ofXYWH 0 0 (px 50) (px 60)) rt.tree.viewport
  -- Copy is honoured only for a designated click; this one also quits.
  let (rt', outs) := click rt 5 35 5000
  checkEq "a designated click copies" [Request.setClipboard (SafeText.trusted "copied")]
    ((requests outs).filter fun | .setClipboard _ => true | _ => false)
  check "and quits" rt'.quit
  let (_, outs) := click rt 5 35 6000 (synthetic := true)
  checkEq "a synthetic click copies nothing" []
    ((requests outs).filter fun | .setClipboard _ => true | _ => false)
  let (rt, _) := rt.step .close 7000
  check "closing the window quits" rt.quit
  -- Focus asked for by a widget.
  let (rt, _) := begin.1.applyReq .other (.focus ⟨2⟩)
  checkEq "a widget can ask for focus" (some ⟨2⟩) rt.router.focused
  let (_, outs) := begin.1.applyReq .other .render
  checkEq "a render request needs no output of its own" 0 outs.length
  -- The IO loop against a fake platform.
  let script ← IO.mkRef [
    [input (.press ⟨px 5, px 5⟩ .primary) 1000, input (.release ⟨px 5, px 5⟩ .primary) 1050],
    [input (.press ⟨px 5, px 25⟩ .primary) 2000, input (.release ⟨px 5, px 25⟩ .primary) 2050],
    [], [], []]
  let log ← IO.mkRef #[]
  let clock ← IO.mkRef 0
  Paw.Runtime.run app (fakePlatform script log clock)
  let reqs ← log.get
  check "the loop draws the first scene and after each change" (reqs.size ≥ 3)
  check "the loop stops when the window closes" ((← script.get).isEmpty)

end Paw.Tests.Runtime
