/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Route
import Paw.Tests.Util

/-! # Routing input

Which widget each input reaches, and when a click or key counts as the user choosing it. -/

namespace Paw.Tests.Route

open Paw

def r (x y w h : Int) : Rect := Rect.ofXYWH (px x) (px y) (px w) (px h)

def sz (n : Nat) : Nat := (px n).toNat

def pt (x y : Int) : Point := ⟨px x, px y⟩

def box (focusable : Bool := true) (w h : Nat := 10) : Widget Unit := Widget.Spec.build (σ := NoState) {
  kind := "box"
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz w), SizeReq.fixedSize (sz h))
  render := fun _ _ _ => Scene.empty
  render_within := fun _ _ v => Scene.empty_within v
  focusable }

def env : Env := Env.mock

/-- Two focusable boxes side by side, a third that is not, and a hidden fourth, laid out in a
40 × 10 window: ids 1 (the row), 2, 3, 4 and 5. -/
def tree : Node Unit :=
  let row := Node.container hstack.toLayout
    [Node.leaf (box), Node.leaf (box), Node.leaf (box (focusable := false)), (Node.leaf (box)).hide]
  (row.init 1).1.resize env (r 0 0 40 10)

def press (x y : Int) (t : Nat) (synthetic := false) : Input :=
  { kind := .press (pt x y) .primary, time := t, synthetic }

def release (x y : Int) (t : Nat) (synthetic := false) (obscured := false) : Input :=
  { kind := .release (pt x y) .primary, time := t, synthetic, obscured }

def key (k : Key) (t : Nat) (synthetic := false) : Input :=
  { kind := .key k {} true, time := t, synthetic }

/-- Routes inputs in order from a router that has seen the tree since time 0. -/
def run (inputs : List Input) (rt : Router := {}) : Router × List Delivery :=
  inputs.foldl (fun (rt, ds) i => let (rt, ds') := rt.route tree i; (rt, ds ++ ds'))
    (rt.observe tree 0, [])

def targets (ds : List Delivery) : List (Nat × String) :=
  ds.map fun d => (d.target.n, match d.event with
    | .press .. => "press" | .release .. => "release" | .click _ _ n => s!"click{n}"
    | .move _ => "move" | .enter _ => "enter" | .leave _ => "leave" | .focus => "focus"
    | .blur => "blur" | .key .. => "key" | .text _ => "text" | .paste _ => "paste"
    | .wheel .. => "wheel" | .tick _ => "tick")

def clicks (ds : List Delivery) : List Delivery :=
  ds.filter fun d => match d.event with | .click .. => true | _ => false

def tests : TestM Unit := do
  -- Hit-testing.
  checkEq "a point on the first box" (some 2) ((tree.hit? (pt 5 5)).map (·.id.n))
  checkEq "a point on the second box" (some 3) ((tree.hit? (pt 15 5)).map (·.id.n))
  checkEq "a point on the row past the boxes" (some 1) ((tree.hit? (pt 35 5)).map (·.id.n))
  checkEq "outside the window" none ((tree.hit? (pt 50 5)).map (·.id.n))
  let stacked := ((Node.container zstack [Node.leaf (box), Node.leaf (box)]).init 1).1.resize env (r 0 0 10 10)
  checkEq "the later of overlapping children is on top" (some 3) ((stacked.hit? (pt 5 5)).map (·.id.n))
  checkEq "focus order skips the unfocusable and the hidden" [2, 3] (tree.focusables.map (·.n))
  -- A click: press and release on one widget.
  let (rt, ds) := run [press 5 5 1000, release 5 5 1100]
  checkEq "press, focus, release, click"
    [(2, "focus"), (2, "press"), (2, "release"), (2, "click1")] (targets ds)
  check "a click on a widget that has been still counts as the user's choice"
    ((clicks ds).all (·.designation.isSome))
  check "the designation names the widget clicked"
    ((clicks ds).all fun d => d.designation.map (·.target) == some d.target)
  checkEq "focus follows the click" (some 2) (rt.focused.map (·.n))
  -- Press on one widget and release on another: no click.
  let (_, ds) := run [press 5 5 1000, release 15 5 1100]
  checkEq "no click across widgets" [] (targets (clicks ds))
  checkEq "the release goes to the pressed widget" [(2, "release")]
    ((targets ds).filter (·.2 == "release"))
  -- Double click.
  let (_, ds) := run [press 5 5 1000, release 5 5 1050, press 5 5 1200, release 5 5 1250]
  checkEq "a second click soon after is a double click" [(2, "click1"), (2, "click2")] (targets (clicks ds))
  let (_, ds) := run [press 5 5 1000, release 5 5 1050, press 5 5 2000, release 5 5 2050]
  checkEq "a later click is a single click" [(2, "click1"), (2, "click1")] (targets (clicks ds))
  -- When a click does not count as the user's choice.
  let (_, ds) := run [press 5 5 1000 (synthetic := true), release 5 5 1100 (synthetic := true)]
  check "a synthetic click is delivered" ((clicks ds).length == 1)
  check "but designates nothing" ((clicks ds).all (·.designation.isNone))
  let (_, ds) := run [press 5 5 1000, release 5 5 1100 (obscured := true)]
  check "an obscured click designates nothing" ((clicks ds).all (·.designation.isNone))
  let (_, ds) := run [press 5 5 200, release 5 5 300]
  check "a widget that just appeared is not yet designated" ((clicks ds).all (·.designation.isNone))
  let moved := ((Node.container hstack.toLayout [Node.leaf (box (w := 5)), Node.leaf (box)]).init 1).1.resize env (r 0 0 40 10)
  let rt0 := ({} : Router).observe tree 0 |>.observe moved 900
  let (rt1, ds1) := rt0.route moved (press 7 5 1000)
  let (_, ds2) := rt1.route moved (release 7 5 1100)
  let ds := ds1 ++ ds2
  check "a widget that just moved under the pointer is not designated" ((clicks ds).all (·.designation.isNone))
  checkEq "and the click went to what is there now" [(3, "click1")] (targets (clicks ds))
  -- A disabled widget gets nothing, and the click does not fall through to its parent.
  let off := ((Node.container hstack.toLayout [(Node.leaf (box)).disable, Node.leaf (box)]).init 1).1.resize env (r 0 0 40 10)
  let rt0 := ({} : Router).observe off 0
  let (rt1, ds1) := rt0.route off (press 5 5 1000)
  let (_, ds2) := rt1.route off (release 5 5 1100)
  checkEq "a disabled widget gets no press or click" [] (targets (ds1 ++ ds2))
  check "and cannot take focus" (off.focusables.map (·.n) == [3])
  -- Hover.
  let (rt, ds) := run [{ kind := .move (pt 5 5), time := 10 }, { kind := .move (pt 15 5), time := 20 }]
  checkEq "enter, move, leave, enter, move"
    [(2, "enter"), (2, "move"), (2, "leave"), (3, "enter"), (3, "move")] (targets ds)
  checkEq "hovered" (some 3) (rt.hovered.map (·.n))
  let (_, ds) := run [{ kind := .move (pt 15 5), time := 10 }, { kind := .leaveWindow, time := 20 }]
  checkEq "leaving the window leaves the widget" [(3, "enter"), (3, "move"), (3, "leave")] (targets ds)
  -- Keys and focus.
  let (rt, ds) := run [key .tab 1000]
  checkEq "tab focuses the first focusable" [(2, "focus")] (targets ds)
  let (rt, ds) := run [key .tab 1100] rt
  checkEq "tab again moves on" [(2, "blur"), (3, "focus")] (targets ds)
  let (rt, ds) := run [key .tab 1200] rt
  checkEq "and wraps around" [(3, "blur"), (2, "focus")] (targets ds)
  let (_, ds) := run [{ kind := .key .tab { shift := true } true, time := 1300 }] rt
  checkEq "shift-tab goes back" [(2, "blur"), (3, "focus")] (targets ds)
  let (_, ds) := run [key .enter 1250] rt
  check "a key right after focus moved is delivered" ((targets ds) == [(2, "key")])
  check "but designates nothing" (ds.all (·.designation.isNone))
  let (_, ds) := run [key .enter 1900] rt
  check "a key once focus has stayed designates the focused widget"
    (ds.all fun d => d.designation.map (·.target) == some d.target && d.designation.isSome)
  let (_, ds) := run [key .enter 1900 (synthetic := true)] rt
  check "a synthetic key designates nothing" (ds.all (·.designation.isNone))
  let (_, ds) := run [key .enter 1000]
  checkEq "a key with nothing focused goes nowhere" [] (targets ds)
  let (_, ds) := run [{ kind := .text "hé", time := 1900 }, { kind := .paste "x", time := 1901 }] rt
  checkEq "text and paste go to the focused widget" [(2, "text"), (2, "paste")] (targets ds)
  check "and designate nothing" (ds.all (·.designation.isNone))
  let (_, ds) := run [{ kind := .wheel (pt 15 5) 0 (px 3), time := 10 }]
  checkEq "the wheel goes to the widget under the pointer" [(3, "wheel")] (targets ds)
  -- Serials.
  let (rt, ds) := run [press 5 5 1000, release 5 5 1100, press 5 5 1500, release 5 5 1600]
  let serials := (clicks ds).filterMap (·.designation.map (·.serial))
  check "each designation has its own serial" (serials.length == 2 && serials[0]! < serials[1]!)
  checkEq "the router counts inputs" 4 rt.serial
  -- Random input: designations always name their delivery's widget, and focus only ever lands
  -- on a focusable widget.
  let mut g : Rng := ⟨5⟩
  let mut rt : Router := ({} : Router).observe tree 0
  let mut agree := true
  let mut focusOk := true
  for step in [0:2000] do
    let (kind, g1) := g.next 9
    let (x, g2) := g1.next 45
    let (y, g3) := g2.next 12
    let (flags, g4) := g3.next 4
    g := g4
    let p := pt x y
    let k : InputKind := match kind with
      | 0 => .press p .primary | 1 => .release p .primary | 2 => .move p
      | 3 => .key .tab { shift := flags == 1 } true | 4 => .key .enter {} true
      | 5 => .text "a" | 6 => .wheel p 0 1 | 7 => .leaveWindow | _ => .paste "b"
    let input : Input :=
      { kind := k, time := 1000 + step * 37, synthetic := (flags == 2), obscured := (flags == 3) }
    let (rt', ds) := rt.route tree input
    rt := rt'
    if !Router.designationsAgree ds then agree := false
    if !(rt.focused.all fun f => tree.focusables.contains f) then focusOk := false
  check "designations always name the widget they reach" agree
  check "focus only lands on focusable widgets" focusOk

end Paw.Tests.Route
