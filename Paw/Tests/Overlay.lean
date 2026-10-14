/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Ui
import Paw.Tests.Util

/-! # Overlays

A popup and a confirm dialog in a small app: where overlays go, that they draw last, that while one
is open the pointer reaches only it, that a modal takes the keyboard too, and that only the user
opens a modal or confirms one. -/

namespace Paw.Tests.Overlay

open Paw

inductive Msg where
  | inc
  | openMenu
  | closeMenu
  | one
  | ask
  | yes
  | no
  /-- Opens the dialog again with the token kept from the last time, as a task's result might. -/
  | sneak
  deriving Repr, BEq, Inhabited

structure Model where
  count : Nat := 0
  menu : Bool := false
  confirming : Option Modal := none
  /-- The token the dialog was last opened with. -/
  kept : Option Modal := none
  ones : Nat := 0
  deleted : Bool := false
  deriving Repr, BEq, Inhabited

def update : (o : Origin) → Msg → UpdateM Model Msg [] o Unit
  | _, .inc => modify fun (m, cs) => ({ m with count := m.count + 1 }, cs)
  | _, .openMenu => modify fun (m, cs) => ({ m with menu := true }, cs)
  | _, .closeMenu => modify fun (m, cs) => ({ m with menu := false }, cs)
  | _, .one => modify fun (m, cs) => ({ m with ones := m.ones + 1, menu := false }, cs)
  | .user d, .ask => modify fun (m, cs) => ({ m with confirming := Modal.open d, kept := Modal.open d }, cs)
  | .other, .ask => pure ()
  | _, .yes => modify fun (m, cs) => ({ m with confirming := none, deleted := true }, cs)
  | _, .no => modify fun (m, cs) => ({ m with confirming := none }, cs)
  | _, .sneak => modify fun (m, cs) => ({ m with confirming := m.kept }, cs)

def view (m : Model) : Node Msg :=
  Ui.keystroke [({ key := .char 'q', ctrl := true }, .inc)] <| Ui.col ([
    Ui.popup m.menu (Ui.button "Menu" .openMenu "menu")
      (Ui.col [Ui.button "One" .one "one", Ui.button "Two" .one "two"]) .closeMenu "pop",
    Ui.button "+" .inc "inc",
    Ui.button "Delete" .ask "delete"] ++
    match m.confirming with
    | some t => [Ui.confirm t (SafeName.filter "Delete?") "Delete everything?" .yes .no]
    | none => [])

def app : App [] := { Model := Model, Msg := Msg, init := {}, update, view }

def window : Rect := Rect.ofXYWH 0 0 (px 300) (px 200)

def start : Runtime app := (Runtime.start app window 0 Env.mock.measure).1

def node? (rt : Runtime app) (k : String) : Option (Node Msg) := rt.tree.findKey? k

def center (r : Rect) : Point := ⟨(r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2⟩

def at_ (rt : Runtime app) (k : String) : Point :=
  ((node? rt k).map (center ·.viewport)).getD ⟨-1, -1⟩

def input (rt : Runtime app) (k : InputKind) (t : Nat) : Runtime app :=
  (rt.step (.input { kind := k, time := t }) t).1

def click (rt : Runtime app) (k : String) (t : Nat) : Runtime app :=
  let p := at_ rt k
  input (input rt (.press p .primary) t) (.release p .primary) (t + 20)

def deliveries (rt : Runtime app) (k : InputKind) (t : Nat) : List Delivery :=
  (rt.router.route rt.tree { kind := k, time := t }).2

def key (k : Key) (m : Mods := {}) : InputKind := .key k m true

def tests : TestM Unit := do
  -- Placement.
  let anchor := Rect.ofXYWH (px 10) (px 10) (px 50) (px 20)
  let req : SizeReq × SizeReq := (SizeReq.fixedSize (px 80).toNat, SizeReq.fixedSize (px 40).toNat)
  checkEq "a popup goes below its anchor" (Rect.ofXYWH (px 10) (px 30) (px 80) (px 40))
    (Overlay.popup.place window anchor req)
  let low := Rect.ofXYWH (px 10) (px 170) (px 50) (px 20)
  checkEq "with no room below, above" (Rect.ofXYWH (px 10) (px 130) (px 80) (px 40))
    (Overlay.popup.place window low req)
  let right := Rect.ofXYWH (px 280) (px 10) (px 20) (px 20)
  checkEq "kept within the window on the right" (px 220) (Overlay.popup.place window right req).x0
  let narrow : SizeReq × SizeReq := (SizeReq.fixedSize (px 5).toNat, SizeReq.fixedSize (px 5).toNat)
  checkEq "at least as wide as its anchor" (px 50) (Overlay.popup.place window anchor narrow).width
  let huge : SizeReq × SizeReq := (SizeReq.fixedSize (px 900).toNat, SizeReq.fixedSize (px 900).toNat)
  check "a popup larger than the window stays within it"
    (decide ((Overlay.popup.place window anchor huge).Within window))
  checkEq "a modal is the window" window (Overlay.modal.place window anchor req)
  -- Closed: no overlay.
  let rt := start
  checkEq "nothing open" none rt.router.overlay
  checkEq "no overlays" 0 rt.tree.overlays.length
  -- Open the menu.
  let rt := click rt "menu" 1000
  check "the menu opened" rt.model.menu
  checkEq "one overlay" 1 rt.tree.overlays.length
  check "the router knows it" rt.router.overlay.isSome
  let menuBox := ((node? rt "menu").map (·.viewport)).getD default
  let oneBox := ((node? rt "one").map (·.viewport)).getD default
  check "the popup's content is below the menu button" (oneBox.y0 ≥ menuBox.y1)
  check "and overlaps the + button beneath it"
    (decide (¬ oneBox.Disjoint (((node? rt "inc").map (·.viewport)).getD default)))
  checkEq "the base layout gives the popup no room" menuBox.height
    ((rt.tree.findKey? "pop").map (·.viewport.height)).get!
  -- Drawing: the base leaves the popup out; overlays draw last.
  let base := rt.tree.render rt.env
  let over := rt.overlayScene
  checkEq "the router draws the overlays the tree has" (rt.tree.overlays.map (·.id))
    (rt.router.shown.toList.map (·.1))
  check "the base draws none of the popup"
    (base.items.all fun (_, d) => match d with
      | .text _ t _ => t.text != "One" | _ => true)
  check "the overlays draw the popup"
    (over.items.any fun (_, d) => match d with | .text _ t _ => t.text == "One" | _ => false)
  check "overlays are within the window" (decide (over.Within window))
  match rt.present with
  | .request (.present s) =>
    checkEq "the scene ends with the overlays" over.items (s.items.drop (s.items.length - over.items.length))
  | _ => check "present draws" false
  -- Pointer: within the overlay, a hit is in it.
  let incAt := at_ rt "inc"
  checkEq "the + button is under the popup: the popup is hit"
    (some "one") ((rt.router.hitAt rt.tree incAt).bind (·.key))
  -- A click 100 ms after opening is not the user's choice.
  let ds := deliveries rt (.release (at_ rt "one") .primary) 1100
  let ds := (deliveries rt (.press (at_ rt "one") .primary) 1080) ++ ds
  let rtp := (rt.router.route rt.tree { kind := .press (at_ rt "one") .primary, time := 1080 }).1
  let clicked := ({ rt with router := rtp }.router.route rt.tree
    { kind := .release (at_ rt "one") .primary, time := 1100 }).2
  check "a click on the popup 100 ms after it opened is delivered"
    (clicked.any fun d => match d.event with | .click .. => true | _ => false)
  check "but designates nothing" (clicked.all (·.designation.isNone))
  check "the press reached the popup's button" (ds.any fun d => some d.target == (node? rt "one").map (·.id))
  let later := ({ rt with router := (rt.router.route rt.tree
    { kind := .press (at_ rt "one") .primary, time := 2000 }).1 }.router.route rt.tree
    { kind := .release (at_ rt "one") .primary, time := 2020 }).2
  check "a click once it has been still for stableMs is designated"
    (later.any fun d => d.designation.isSome)
  -- A press outside dismisses and reaches nothing else.
  let outside : Point := ⟨px 250, px 150⟩
  checkEq "a press outside goes only to the overlay, as a dismissal"
    (rt.router.overlay.toList.map fun (o, _) => (o, Event.dismiss))
    ((deliveries rt (.press outside .primary) 1500).map fun d => (d.target, d.event))
  let rt2 := input rt (.press outside .primary) 1500
  check "and closes it" (!rt2.model.menu)
  checkEq "the router knows it closed" none rt2.router.overlay
  checkEq "nothing beneath was pressed" 0 rt2.model.count
  -- Escape, with focus outside the popup, reaches the popup.
  let rt3 := input rt (key .escape) 1500
  check "Escape closes the popup" (!rt3.model.menu)
  -- Focus is trapped in the popup.
  let rt4 := input rt (key .tab) 1500
  checkEq "Tab moves into the popup" ((node? rt "one").map (·.id)) rt4.router.focused
  let rt4 := input rt4 (key .tab) 1600
  checkEq "and on within it" ((node? rt "two").map (·.id)) rt4.router.focused
  let rt4 := input rt4 (key .tab) 1700
  checkEq "and wraps around inside it" ((node? rt "one").map (·.id)) rt4.router.focused
  let rt4 := input rt4 (key .enter) 2500
  checkEq "Enter on a popup button acts" 1 rt4.model.ones
  -- A popup leaves the keyboard alone: text and keys go to the focused widget beneath it.
  let menuId := (node? rt "menu").map (·.id)
  checkEq "text goes to the focused widget beneath a popup" (menuId.toList.map (·, Event.text "x"))
    ((deliveries rt (.text "x") 1500).map fun d => (d.target, d.event))
  let rt5 := input rt (key (.char 'q') { ctrl := true }) 2000
  checkEq "a binding around the view still works with a popup open" 1 rt5.model.count
  -- Nothing bubbles out of an overlay: a key on a popup's button that it does not handle stops there.
  let inPopup := input rt (key .tab) 1500
  let rt6 := input inPopup (key (.char 'q') { ctrl := true }) 2000
  checkEq "a key unhandled inside a popup does not reach the view around it" 0 rt6.model.count
  -- A confirm dialog.
  let rt := click start "delete" 1000
  check "the dialog opened" rt.model.confirming.isSome
  let dlg := rt.tree.overlays
  checkEq "one overlay, the window's size" [window] (dlg.map (·.viewport))
  let rt7 := click rt "inc" 2000
  checkEq "a click on + beneath the dialog does nothing" 0 rt7.model.count
  check "and leaves the dialog open" rt7.model.confirming.isSome
  -- A modal takes the keyboard: text and bindings beneath it are not reached.
  let incFocused := input (click start "inc" 500) (key .tab) 600
  let withDialog := click incFocused "delete" 1000
  check "the dialog opened over a focused widget" withDialog.model.confirming.isSome
  checkEq "text for a widget beneath the dialog is dropped" [] (deliveries withDialog (.text "x") 1500)
  let rt5 := input withDialog (key (.char 'q') { ctrl := true }) 2000
  checkEq "a binding beneath the dialog is not reached" withDialog.model.count rt5.model.count
  let acc := rt.tree.accessTree rt.env
  check "assistive technology sees a dialog named by its title"
    (acc.any fun n => n.access.role == .dialog && n.access.name.text == "Delete?")
  let incId := ((node? rt "inc").map (·.id)).get!
  let (rt8, outs) := rt.step (.access incId .press) 2000
  checkEq "assistive technology cannot press beneath it" 0 rt8.model.count
  checkEq "and nothing is drawn for trying" 0 outs.length
  let rt9 := input rt (key .escape) 2000
  check "Escape cancels" (rt9.model.confirming.isNone && !rt9.model.deleted)
  checkEq "and the dialog is gone" 0 rt9.tree.overlays.length
  let rt9 := input rt (key .enter) 2000
  check "Enter takes the safe choice" (rt9.model.confirming.isNone && !rt9.model.deleted)
  let early := click rt "accept" 1100
  check "OK clicked 100 ms after the dialog appeared does not confirm" (!early.model.deleted)
  let rt10 := click rt "accept" 2000
  check "OK clicked once it has been still for stableMs accepts" (rt10.model.confirming.isNone && rt10.model.deleted)
  checkEq "focus on the dialog's button goes with it" none rt10.router.focused
  let synth := (input rt (.press (at_ rt "accept") .primary) 2000).step
    (.input { kind := .release (at_ rt "accept") .primary, time := 2020, synthetic := true }) 2020
  check "a synthetic click on OK does not confirm" (!synth.1.model.deleted)
  let acceptId := ((node? rt "accept").map (·.id)).get!
  check "nor does assistive technology pressing it" (!(rt.step (.access acceptId .press) 2000).1.model.deleted)
  -- Only the user opens a modal: one opened by anything else is refused and dismissed.
  let closed := input rt (key .escape) 2000
  check "the token was kept" closed.model.kept.isSome
  let (sneaked, outs) := closed.taskResult .sneak 3000
  checkEq "a dialog opened by a task's result is dismissed at once" none sneaked.model.confirming
  let drawsTitle (o : Output Msg) : Bool := match o with
    | .request (.present s) => s.items.any fun (_, d) => match d with
      | .text _ t _ => t.text == "Delete?"
      | _ => false
    | _ => false
  checkEq "and never drawn" 0 (outs.filter drawsTitle).length
  check "though the same dialog opened by the user is" ((click closed "delete" 4000).present |> drawsTitle)
  checkEq "nothing is open" none sneaked.router.overlay
  let again := click closed "delete" 4000
  check "the user can open it again" again.model.confirming.isSome
  -- The proofs, checked on this tree.
  match rt.router.overlayNode rt.tree with
  | some o =>
    let pts := [⟨px 5, px 5⟩, at_ rt "accept", at_ rt "inc", ⟨px 299, px 199⟩]
    check "every hit while the dialog is open is in it"
      (pts.all fun p => ((rt.router.hitAt rt.tree p).map fun m => o.ids.contains m.id).getD true)
  | none => check "the dialog is the router's overlay" false

end Paw.Tests.Overlay
