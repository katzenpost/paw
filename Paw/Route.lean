/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tree
import Std.Data.HashMap

/-! # Routing input

The router turns platform input into events for widgets, as monomer's handlers do: keys, text and
pastes go to the focused widget; presses, moves and the wheel to the widget under the pointer; a
release to the widget pressed, followed by a click if the pointer is still on it.

It also decides when a click or a key counts as the user choosing the widget it reaches. Only then
does the delivery carry a `Designation`, which only this module can make, and which effects that
use authority require. A click or key designates nothing when:

- the platform says it was synthetic, sent by another program rather than typed or clicked;
- the platform says another app's window covered the widget;
- the widget appeared or moved less than `stableMs` before, so it may have slid under a pointer
  aimed at something else;
- for a key, focus reached the widget less than `stableMs` before, so typing meant for elsewhere
  may have followed it. -/

namespace Paw

/-- That the user chose `target` with the input numbered `serial`. Only the router makes these. -/
structure Designation where
  private mk ::
  serial : Nat
  target : WidgetId
  time : Nat
  deriving Repr, DecidableEq

inductive InputKind where
  | press (p : Point) (b : MouseButton)
  | release (p : Point) (b : MouseButton)
  | move (p : Point)
  | wheel (p : Point) (dx dy : Int)
  | key (k : Key) (m : Mods) (pressed : Bool)
  | text (s : String)
  | paste (s : String)
  /-- The pointer left the window. -/
  | leaveWindow
  deriving Repr, DecidableEq, Inhabited

/-- Input from the platform. -/
structure Input where
  kind : InputKind
  /-- Milliseconds since the app started. -/
  time : Nat
  /-- Sent by another program, such as an X11 `SendEvent`. -/
  synthetic : Bool := false
  /-- Another app's window covered ours where this happened. -/
  obscured : Bool := false
  deriving Repr, DecidableEq, Inhabited

/-- An event for a widget. -/
structure Delivery where
  target : WidgetId
  event : Event
  designation : Option Designation := none
  deriving Repr, DecidableEq

structure Router where
  focused : Option WidgetId := none
  /-- When focus last moved. -/
  focusedAt : Nat := 0
  hovered : Option WidgetId := none
  pressed : Option WidgetId := none
  /-- The last click: its widget, time and count. -/
  lastClick : Option (WidgetId × Nat × Nat) := none
  /-- Each visible widget's box, and since when it has had it. -/
  placed : Std.HashMap WidgetId (Rect × Nat) := {}
  /-- Inputs routed so far. -/
  serial : Nat := 0
  stableMs : Nat := 500
  doubleClickMs : Nat := 400

namespace Router

variable {Msg : Type}

/-- Notes where every widget is at `now`, after a layout. -/
def observe (rt : Router) (tree : Node Msg) (now : Nat) : Router :=
  let placed := tree.placements.foldl (init := {}) fun (m : Std.HashMap WidgetId (Rect × Nat)) (id, r) =>
    match rt.placed[id]? with
    | some (r', t) => if r' == r then m.insert id (r', t) else m.insert id (r, now)
    | none => m.insert id (r, now)
  { rt with placed }

/-- The widget has kept its box since `stableMs` before `now`. -/
def stable (rt : Router) (id : WidgetId) (now : Nat) : Bool :=
  match rt.placed[id]? with
  | some (_, t) => now ≥ t + rt.stableMs
  | none => false

/-- A designation of `target` by input `i`, numbered `serial`, if the checks pass. -/
def designate (rt : Router) (serial : Nat) (i : Input) (target : WidgetId) (isKey : Bool) :
    Option Designation :=
  let focusHeld := !isKey || i.time ≥ rt.focusedAt + rt.stableMs
  if !i.synthetic && !i.obscured && rt.stable target i.time && focusHeld then
    some ⟨serial, target, i.time⟩
  else none

/-- Moves focus to `to`, with blur and focus events. -/
def moveFocus (rt : Router) (to : Option WidgetId) (now : Nat) : Router × List Delivery :=
  if to == rt.focused then (rt, [])
  else
    let blur := rt.focused.toList.map fun id => { target := id, event := .blur }
    let focus := to.toList.map fun id => { target := id, event := .focus }
    ({ rt with focused := to, focusedAt := now }, blur ++ focus)

/-- The id after `current` in `order`, wrapping around, or the first. -/
def pick (order : List WidgetId) (current : Option WidgetId) : Option WidgetId :=
  match current.bind (order.idxOf? ·) with
  | some i => order[(i + 1) % order.length]?
  | none => order.head?

theorem pick_mem {order : List WidgetId} {current : Option WidgetId} {id : WidgetId}
    (h : pick order current = some id) : id ∈ order := by
  unfold pick at h
  split at h
  · exact List.mem_of_getElem? h
  · exact List.mem_of_mem_head? h

/-- The focusable after (or before) the focused one, wrapping around. -/
def nextFocus (order : List WidgetId) (current : Option WidgetId) (back : Bool) : Option WidgetId :=
  pick (if back then order.reverse else order) current

/-- Focus only ever moves to a widget in the focus order: visible, enabled and focusable. -/
theorem nextFocus_mem {order : List WidgetId} {current : Option WidgetId} {back : Bool}
    {id : WidgetId} (h : nextFocus order current back = some id) : id ∈ order := by
  have := pick_mem h
  split at this
  · exact List.mem_reverse.mp this
  · exact this

def hover (rt : Router) (to : Option WidgetId) (p : Point) : Router × List Delivery :=
  if to == rt.hovered then (rt, [])
  else
    let leave := rt.hovered.toList.map fun id => { target := id, event := .leave p }
    let enter := to.toList.map fun id => { target := id, event := .enter p }
    ({ rt with hovered := to }, leave ++ enter)

/-- Routes one input through `tree`: the router after it, and the events it gives widgets. -/
def route (rt : Router) (tree : Node Msg) (i : Input) : Router × List Delivery :=
  let serial := rt.serial
  let rt := { rt with serial := rt.serial + 1 }
  let at? (p : Point) := (tree.hit? p).filter (·.enabled)
  match i.kind with
  | .press p b =>
    match at? p with
    | some n =>
      let (rt, focus) := if n.focusable then rt.moveFocus (some n.id) i.time else (rt, [])
      ({ rt with pressed := some n.id }, focus ++ [{ target := n.id, event := .press p b }])
    | none => ({ rt with pressed := none }, [])
  | .release p b =>
    match rt.pressed with
    | some id =>
      let rel : Delivery := { target := id, event := .release p b }
      let rt := { rt with pressed := none }
      if (at? p).map (·.id) == some id then
        let count := match rt.lastClick with
          | some (last, t, c) => if last == id && i.time ≤ t + rt.doubleClickMs then c + 1 else 1
          | none => 1
        let click : Delivery :=
          { target := id, event := .click p b count, designation := rt.designate serial i id false }
        ({ rt with lastClick := some (id, i.time, count) }, [rel, click])
      else (rt, [rel])
    | none => (rt, [])
  | .move p =>
    let target := (at? p).map (·.id)
    let (rt, hov) := rt.hover target p
    let moveTo := rt.pressed.orElse fun _ => target
    (rt, hov ++ moveTo.toList.map fun id => { target := id, event := .move p })
  | .leaveWindow =>
    let (rt, hov) := rt.hover none ⟨0, 0⟩
    (rt, hov)
  | .wheel p dx dy =>
    (rt, ((at? p).map (·.id)).toList.map fun id => { target := id, event := .wheel p dx dy })
  | .key .tab m true =>
    let to := nextFocus tree.focusables rt.focused m.shift
    rt.moveFocus to i.time
  | .key k m pressed =>
    (rt, rt.focused.toList.map fun id =>
      { target := id, event := .key k m pressed, designation := rt.designate serial i id true })
  | .text s => (rt, rt.focused.toList.map fun id => { target := id, event := .text s })
  | .paste s => (rt, rt.focused.toList.map fun id => { target := id, event := .paste s })

/-- Every designation the router gives names the widget its delivery goes to. -/
def designationsAgree (ds : List Delivery) : Bool :=
  ds.all fun d => d.designation.all (·.target == d.target)

end Router

end Paw
