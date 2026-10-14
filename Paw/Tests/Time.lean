/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Ui
import Paw.Tests.Util

/-! # Time

Ticks, delayed messages, tooltips and animations, driven by a fake clock through `Runtime.advance`,
and the loop's waiting against a fake platform. -/

namespace Paw.Tests.Time

open Paw

inductive Msg where
  | ticked
  | later
  | ping
  | typed (s : String)
  | pressed
  deriving Repr, BEq, Inhabited

structure Model where
  ticks : Nat := 0
  pings : List Bool := []
  text : String := ""
  presses : Nat := 0
  deriving Repr, BEq, Inhabited

/-- Ticks every 100 ms, three times, then stops: how many times it ticks is its state. -/
def ticker : Widget Msg := Widget.Spec.build (σ := Nat) {
  kind := "ticker"
  init := 0
  sizeReq := fun _ _ => (SizeReq.fixedSize (px 10).toNat, SizeReq.fixedSize (px 10).toNat)
  render := fun _ _ _ => Scene.empty
  render_within := fun _ _ v => Scene.empty_within v
  handle := fun _ n _ e => match e with
    | .tick _ => some (n + 1, [.emit .ticked])
    | _ => none
  every := fun _ n => if n < 3 then some 100 else none }

def update : (o : Origin) → Msg → UpdateM Model Msg [] o Unit
  | _, .ticked => modify fun (m, cs) => ({ m with ticks := m.ticks + 1 }, cs)
  | _, .later => emit (.after 500 .ping)
  | o, .ping => modify fun (m, cs) => ({ m with pings := m.pings ++ [o.designation.isSome] }, cs)
  | _, .typed s => modify fun (m, cs) => ({ m with text := s }, cs)
  | _, .pressed => modify fun (m, cs) => ({ m with presses := m.presses + 1 }, cs)

/-- An app built from `view`, in a 300 × 200 window. -/
def appOf (view : Model → Node Msg) : App [] := { Model := Model, Msg := Msg, init := {}, update, view }

def window : Rect := Rect.ofXYWH 0 0 (px 300) (px 200)

def startOf (view : Model → Node Msg) (motion : Bool := true) : Runtime (appOf view) :=
  (Runtime.start (appOf view) window 0 Env.mock.measure motion).1

def tickerView (_ : Model) : Node Msg := Ui.col [Node.leaf ticker]

def fieldView (m : Model) : Node Msg :=
  Ui.col [Ui.textField m.text .typed {} "field", Ui.tooltip "Presses the button" (Ui.button "Go" .pressed "go")]

def fadeView (_ : Model) : Node Msg := Ui.col [Ui.fadeIn (Ui.button "Go" .pressed "go") (ms := 400)]

def slideView (_ : Model) : Node Msg := Ui.col [Ui.slideIn (Ui.button "Go" .pressed "go") ⟨0, px 40⟩ 400]

section
variable {view : Model → Node Msg}

def input (rt : Runtime (appOf view)) (k : InputKind) (t : Nat) : Runtime (appOf view) :=
  (rt.step (.input { kind := k, time := t }) t).1

def at_ (rt : Runtime (appOf view)) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def click (rt : Runtime (appOf view)) (k : String) (t : Nat) : Runtime (appOf view) × List Delivery :=
  let p := at_ rt k
  let rt := input rt (.press p .primary) t
  let ds := (rt.router.route rt.tree { kind := .release p .primary, time := t + 20 }).2
  let rt := input rt (.release p .primary) (t + 20)
  (rt, ds.filter fun d => match d.event with | .click .. => true | _ => false)

def presents (outs : List (Output (appOf view).Msg)) : Nat :=
  (outs.filter fun | .request (.present _) => true | _ => false).length

def texts (rt : Runtime (appOf view)) : List String :=
  match rt.present with
  | .request (.present s) => s.items.filterMap fun (_, d) => match d with
    | .text _ t _ => some t.text
    | _ => none
  | _ => []

/-- The alpha of the fill drawn for the button. -/
def buttonAlpha (rt : Runtime (appOf view)) : Option Nat :=
  match rt.present with
  | .request (.present s) => (s.items.filterMap fun (_, d) => match d with
      | .stroke _ c _ _ => some c.a.toNat
      | _ => none).head?
  | _ => none

end

/-- A platform that plays `script`, one list of events per poll, and records how long each poll
was allowed to wait. -/
def fakePlatform (script : IO.Ref (List (List WindowEvent))) (waits : IO.Ref (Array (Option Nat)))
    (clock : IO.Ref Nat) : Platform where
  poll := fun w => do
    waits.modify (·.push w)
    clock.modify (· + 100)
    match ← script.get with
    | evs :: rest => script.set rest; return evs
    | [] => return [.close]
  now := clock.get
  size := pure (px 300, px 200)
  measure := Env.mock.measure
  perform := fun _ => pure ()

def tests : TestM Unit := do
  -- Ticks: every 100 ms, three times, then none.
  let rt := startOf tickerView
  checkEq "a ticker's first tick is due a period after it appears" (some 100) rt.nextDeadline
  let (rt, outs) := rt.advance 50
  checkEq "nothing before it is due" (0, 0) (rt.model.ticks, outs.length)
  let (rt, outs) := rt.advance 100
  checkEq "a tick when due" 1 rt.model.ticks
  check "and a frame" (presents outs == 1)
  checkEq "the next a period later" (some 200) rt.nextDeadline
  let (rt, _) := rt.advance 200
  let (rt, _) := rt.advance 300
  checkEq "three ticks" 3 rt.model.ticks
  checkEq "then it stops, by its state" none rt.nextDeadline
  let (rt, _) := rt.advance 1000
  checkEq "and ticks no more" 3 rt.model.ticks
  -- Hidden: ticks pause.
  let rt := startOf tickerView
  let (rt, outs) := rt.step (.visible false) 50
  checkEq "hiding draws nothing" 0 outs.length
  checkEq "nothing is due while hidden" none rt.nextDeadline
  let (rt, _) := rt.advance 500
  checkEq "no ticks while hidden" 0 rt.model.ticks
  let (rt, outs) := rt.step (.visible true) 600
  check "shown again, it draws" (presents outs == 1)
  let (rt, _) := rt.advance 600
  checkEq "and the tick that was due comes" 1 rt.model.ticks
  checkEq "then a period after" (some 700) rt.nextDeadline
  -- Delayed messages: origin other, even from the user's click.
  let rt := startOf fieldView
  let (rt, _) := rt.applyMsg .other .later
  checkEq "Cmd.after is kept, not sent to the platform" 1 rt.delayed.size
  checkEq "and is the next deadline" (some 500) rt.nextDeadline
  let (rt, _) := rt.advance 499
  checkEq "not before it is due" [] rt.model.pings
  let (rt, outs) := rt.advance 500
  checkEq "then with origin other" [false] rt.model.pings
  check "and drawn" (presents outs == 1)
  checkEq "and gone" none rt.nextDeadline
  -- The deadline is never in the past.
  let rt := startOf tickerView
  let (late, _) := { rt with now := 5000 }.advance 5000
  check "a late runtime's deadline is not before now" (late.nextDeadline.all (5000 ≤ ·))
  -- How long the loop waits.
  let idle := startOf fieldView
  checkEq "an idle app waits for the platform with no timeout" none (idle.waitFor 0 false)
  checkEq "with a task running, 16 ms" (some 16) (idle.waitFor 0 true)
  let ticking := startOf tickerView
  checkEq "until the next tick" (some 70) (ticking.waitFor 30 false)
  checkEq "or 16 ms with a task running" (some 16) (ticking.waitFor 30 true)
  checkEq "a deadline passed: no wait" (some 0) (ticking.waitFor 150 false)
  -- The loop: an idle app asks the platform to wait without a timeout.
  let script ← IO.mkRef [[], []]
  let waits ← IO.mkRef #[]
  let clock ← IO.mkRef 0
  Paw.Runtime.run (appOf fieldView) (fakePlatform script waits clock)
  checkEq "the loop of an idle app never wakes on its own" #[none, none, none] (← waits.get)
  let script ← IO.mkRef [[], []]
  let waits ← IO.mkRef #[]
  let clock ← IO.mkRef 0
  Paw.Runtime.run (appOf tickerView) (fakePlatform script waits clock)
  checkEq "a ticking app's loop wakes for its ticks" #[some 100, some 100, some 100] (← waits.get)
  -- Keys while the window lacks focus reach nothing.
  let rt := startOf fieldView
  let (rt, _) := click rt "field" 1000
  let (blurred, _) := rt.step (.focus false) 1100
  let typed := input blurred (.text "x") 1200
  checkEq "text while the window lacks focus is dropped" "" typed.model.text
  let typed := input blurred (.key (.char 'a') { ctrl := true } true) 1200
  checkEq "and keys" "" typed.model.text
  let (back, _) := blurred.step (.focus true) 1300
  checkEq "with focus back, typing works" "x" (input back (.text "x") 1400).model.text
  -- The caret blinks while the field and the window have focus.
  let fieldId := ((rt.tree.findKey? "field").map (·.id)).get!
  checkEq "a focused field ticks every 500 ms" (some 500) (rt.router.ticks[fieldId]?.map (·.1))
  checkEq "an unfocused window's field does not" none (blurred.router.ticks[fieldId]?)
  let caret (rt : Runtime (appOf fieldView)) : Bool := match rt.present with
    | .request (.present s) => s.items.any fun (_, d) => match d with
      | .fill r _ _ => r.width == px 1
      | _ => false
    | _ => false
  check "the caret shows when focus arrives" (caret rt)
  let (r1, _) := rt.advance 1500
  check "and is hidden 500 ms later" (!caret r1)
  let (r2, _) := r1.advance 2000
  check "and shows again" (caret r2)
  let r3 := input r1 (.text "y") 1600
  check "typing shows it at once" (caret r3)
  -- A tooltip shows after the pointer rests a second, and takes no input.
  let rt := startOf fieldView
  let rt := input rt (.move (at_ rt "go")) 1000
  check "no tip as the pointer arrives" (!(texts rt).contains "Presses the button")
  checkEq "the tip is the next deadline" (some 2000) rt.nextDeadline
  let (r1, outs) := rt.advance 1999
  checkEq "nothing before" 0 outs.length
  let (r1, outs) := r1.advance 2000
  check "after a second, the tip shows" ((texts r1).contains "Presses the button")
  check "with a frame" (presents outs == 1)
  checkEq "and is not an overlay that takes input" none r1.router.overlay
  checkEq "the button is still what the pointer is on" ((r1.tree.findKey? "go").map (·.id)) r1.router.hovered
  let r2 := input r1 (.move ⟨px 290, px 190⟩) 2100
  check "the tip goes when the pointer leaves" (!(texts r2).contains "Presses the button")
  let hiddenTip := (r2.tree.accessTree r2.env).any fun n => n.access.name.text == "Presses the button"
  check "a tip not showing is in the tree for assistive technology" hiddenTip
  match r2.accessOut with
  | .request (.access _ nodes) =>
    check "but not sent to it" (!nodes.any fun n => n.access.name.text == "Presses the button")
  | _ => check "the accessibility tree is sent" false
  let r3 := input (input rt (.key .tab {} true) 1000) (.key .tab {} true) 1001
  check "a tip shows at once when focus reaches it" ((texts r3).contains "Presses the button")
  -- Fading in: transparent, then opaque; moving while it runs.
  let rt := startOf fadeView
  checkEq "a fade starts transparent" (some 0) (buttonAlpha rt)
  let (rt, _) := rt.advance 16
  let (rt, _) := rt.advance 216
  check "half way, half opaque" ((buttonAlpha rt).any fun a => 100 < a && a < 155)
  let (rt', ds) := click rt "go" 300
  checkEq "a click on it while it fades is delivered" 1 ds.length
  check "but designates nothing" (ds.all (·.designation.isNone))
  checkEq "and acts" 1 rt'.model.presses
  let (rt, _) := rt.advance 416
  checkEq "at the end, opaque" (some 255) (buttonAlpha rt)
  checkEq "and it stops ticking" none rt.nextDeadline
  let (_, ds) := click rt "go" 680
  check "less than 500 ms after its last moving frame, a click designates nothing" (ds.all (·.designation.isNone))
  let (_, ds) := click rt "go" 1000
  check "once still for 500 ms, a click designates" (ds.any (·.designation.isSome))
  let calm := startOf fadeView (motion := false)
  checkEq "with reduced motion, opaque at once" (some 255) (buttonAlpha calm)
  checkEq "and no ticks" none calm.nextDeadline
  -- Sliding in: from the offset to its place.
  let rt := startOf slideView
  let y0 := ((rt.tree.findKey? "go").map (·.viewport.y0)).get!
  let (rt, _) := rt.advance 16
  let (rt, _) := rt.advance 216
  let yMid := ((rt.tree.findKey? "go").map (·.viewport.y0)).get!
  let (rt, _) := rt.advance 416
  let yEnd := ((rt.tree.findKey? "go").map (·.viewport.y0)).get!
  checkEq "a slide starts at its offset" (px 40) (y0 - yEnd)
  check "half way, half way" (yEnd < yMid && yMid < y0)
  checkEq "and ends in place" 0 yEnd

end Paw.Tests.Time
