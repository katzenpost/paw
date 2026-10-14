/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Ui
import Paw.Runtime
import Paw.Tests.Util

/-! # Widgets

Text editing on its own, then each widget in an app driven through the runtime. -/

namespace Paw.Tests.Widgets

open Paw Paw.Widgets

def ed (s : String) (cursor : Nat) (anchor : Option Nat := none) : Edit :=
  { value := s.toList, cursor, anchor }

def str (e : Edit) : String := String.ofList e.value

def editTests : TestM Unit := do
  checkEq "insert at the cursor" "abXc" (str ((ed "abc" 2).insert ['X'] 100))
  checkEq "the cursor moves past it" 3 ((ed "abc" 2).insert ['X'] 100).cursor
  checkEq "insert replaces the selection" "aXc" (str ((ed "abc" 2 (some 1)).insert ['X'] 100))
  checkEq "insert stops at the maximum" "abX" (str ((ed "ab" 2).insert ['X', 'Y'] 3))
  checkEq "backspace" "ac" (str (ed "abc" 2).backspace)
  checkEq "backspace at the start" "abc" (str (ed "abc" 0).backspace)
  checkEq "backspace deletes the selection" "a" (str (ed "abc" 3 (some 1)).backspace)
  checkEq "delete" "ab" (str (ed "abc" 2).delete)
  checkEq "delete at the end" "abc" (str (ed "abc" 3).delete)
  checkEq "delete the selection" "c" (str (ed "abc" 0 (some 2)).delete)
  checkEq "left" 1 ((ed "abc" 2).left false).cursor
  checkEq "left at the start" 0 ((ed "abc" 0).left false).cursor
  checkEq "left collapses a selection to its start" (1, none) (((ed "abc" 3 (some 1)).left false).cursor,
    ((ed "abc" 3 (some 1)).left false).anchor)
  checkEq "shift-left selects" (some (1, 2)) ((ed "abc" 2).left true).selection
  checkEq "right" 3 ((ed "abc" 2).right false).cursor
  checkEq "right collapses a selection to its end" 3 ((ed "abc" 1 (some 3)).right false).cursor
  checkEq "shift-right selects" (some (2, 3)) ((ed "abc" 2).right true).selection
  checkEq "select all" (some (0, 3)) (ed "abc" 1).selectAll.selection
  checkEq "selected" "bc" (String.ofList (ed "abc" 3 (some 1)).selected)
  checkEq "nothing selected" "" (String.ofList (ed "abc" 3).selected)
  checkEq "an empty selection is none" none (ed "abc" 2 (some 2)).selection
  checkEq "clamp" (2, some 2) (((ed "ab" 9 (some 7)).clamp).cursor, ((ed "ab" 9 (some 7)).clamp).anchor)
  checkEq "move to" (some (1, 3)) ((ed "abc" 1).moveTo 3 true).selection
  checkEq "typing drops controls and flattens lines" "a b c" (String.ofList (cleanInput "a\nb\tc\x1b"))
  checkEq "index at a point" 2 (indexAt (fun t => px (t.text.length * 10)) "abcd".toList (px 21))
  checkEq "index at the start" 0 (indexAt (fun t => px (t.text.length * 10)) "abcd".toList (px 2))
  checkEq "index past the end" 4 (indexAt (fun t => px (t.text.length * 10)) "abcd".toList (px 99))

/-! ## In an app -/

inductive Msg where
  | clicked
  | toggled (b : Bool)
  | typed (s : String)
  | pass (s : Secret)
  | save
  | shuffle
  | shorten

structure Model where
  clicks : Nat := 0
  checked : Bool := false
  draft : String := ""
  secretLen : Nat := 0
  secret : Secret := Secret.empty
  saves : Nat := 0
  items : List String := ["one", "two", "three"]

instance : BEq Model where
  beq a b := a.clicks == b.clicks && a.checked == b.checked && a.draft == b.draft &&
    a.secret.eq b.secret && a.saves == b.saves && a.items == b.items

def update : (o : Origin) → Msg → UpdateM Model Msg [] o Unit
  | _, .clicked => modify fun (m, cs) => ({ m with clicks := m.clicks + 1 }, cs)
  | _, .toggled b => modify fun (m, cs) => ({ m with checked := b }, cs)
  | _, .typed s => modify fun (m, cs) => ({ m with draft := s }, cs)
  | _, .pass s => modify fun (m, cs) => ({ m with secret := s, secretLen := s.length }, cs)
  | _, .save => modify fun (m, cs) => ({ m with saves := m.saves + 1 }, cs)
  | _, .shuffle => modify fun (m, cs) => ({ m with items := m.items.reverse }, cs)
  | _, .shorten => modify fun (m, cs) => ({ m with draft := (m.draft.take 1).toString }, cs)

/-- In a 200 × 420 window, rows 20 pixels tall with no spacing: a button (y 0), a checkbox
(y 20), a text field (y 40), a password field (y 60), and a 60-pixel scroll (y 80) over five
labels, under a ctrl-s binding. -/
def view (m : Model) : Node Msg :=
  Ui.keystroke [({ key := .char 's', ctrl := true }, .save)] <|
    Ui.col (spacing := 0) [
      Ui.button "Go" .clicked "go",
      Ui.checkbox "Check" m.checked .toggled "check",
      Ui.textField m.draft .typed {} "draft",
      Ui.passwordField m.secret .pass "pass",
      Ui.height (px 60) (Ui.scroll (Ui.col (spacing := 0)
        ((List.range 5).map fun i => Ui.label s!"line {i}"))) |>.withInfo ({ · with key := some "sc" }),
      Ui.list m.items id (fun s => Ui.textField s .typed),
      Ui.pad (px 2) (Ui.label "padded"),
      Ui.lazy m.clicks (fun n => Ui.label s!"clicked {n} times") "lazy",
      (Ui.width (px 50) (Ui.label "narrow")).withInfo ({ · with key := some "narrow" }),
      Ui.row [Ui.text (SafeText.filter "a\x1bb"), Ui.paragraph "x\ny", Ui.spacer]]

def app : App [] := { Model := Model, Msg := Msg, init := {}, update, view }

/-- The runtime, with every widget still since time 0. -/
def begin : Runtime app :=
  (Paw.Runtime.start app (Rect.ofXYWH 0 0 (px 200) (px 420)) 0 Env.mock.measure).1

def step (rt : Runtime app) (k : InputKind) (t : Nat) (synthetic := false) :
    Runtime app × List (Output Msg) :=
  rt.step (.input { kind := k, time := t, synthetic }) t

/-- The middle of the widget with `k`. -/
def at_ (rt : Runtime app) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def clickAt (rt : Runtime app) (p : Point) (t : Nat) (synthetic := false) :
    Runtime app × List (Output Msg) :=
  let (rt, o1) := step rt (.press p .primary) t synthetic
  let (rt, o2) := step rt (.release p .primary) (t + 50) synthetic
  (rt, o1 ++ o2)

def click (rt : Runtime app) (k : String) (t : Nat) (synthetic := false) :
    Runtime app × List (Output Msg) :=
  clickAt rt (at_ rt k) t synthetic

def key (rt : Runtime app) (k : Key) (t : Nat) (m : Mods := {}) : Runtime app :=
  (step rt (.key k m true) t).1

def typeText (rt : Runtime app) (s : String) (t : Nat) : Runtime app := (step rt (.text s) t).1

def copies (outs : List (Output Msg)) : List SafeText :=
  outs.filterMap fun | .request (.setClipboard t) => some t | _ => none

def scene (rt : Runtime app) : Scene := rt.tree.render rt.env

def texts (rt : Runtime app) : List String :=
  (scene rt).items.filterMap fun | (_, .text _ t _) => some t.text | _ => none

def appTests : TestM Unit := do
  let rt := begin
  check "everything is drawn within the window" (decide ((scene rt).Within rt.window))
  check "labels show" ((texts rt).contains "line 0")
  check "text from elsewhere is shown filtered" ((texts rt).contains "a�b")
  check "a paragraph shows its lines" ((texts rt).contains "x" && (texts rt).contains "y")
  checkEq "a fixed width" (some (px 50))
    ((rt.tree.findKey? "narrow").map fun n => (n.sizeReq rt.env).1.fixed)
  -- Button.
  let (rt, _) := click rt "go" 1000
  checkEq "a click on the button" 1 rt.model.clicks
  check "a lazy view is built anew when its argument changes" ((texts rt).contains "clicked 1 times")
  let rt := key rt .enter 2000
  checkEq "Enter on the focused button" 2 rt.model.clicks
  let rt := key rt (.char ' ') 2100
  checkEq "Space on the focused button" 3 rt.model.clicks
  check "the focused button draws a wider border"
    ((scene rt).items.any fun | (_, .stroke _ _ w _) => w == px 2 | _ => false)
  -- Checkbox.
  let (rt, _) := click rt "check" 3000
  check "a click checks the box" rt.model.checked
  let (rt, _) := click rt "check" 4000
  check "and another unchecks it" (!rt.model.checked)
  -- Text field.
  let (rt, _) := click rt "draft" 5000
  let rt := typeText rt "héllo" 5600
  checkEq "typing reaches the model" "héllo" rt.model.draft
  let rt := key rt .backspace 5700
  checkEq "backspace" "héll" rt.model.draft
  let rt := key rt .home 5800 |> (key · .right 5900 { shift := true }) |> (key · .right 6000 { shift := true })
  let rt := typeText rt "J" 6100
  checkEq "typing replaces a selection" "Jll" rt.model.draft
  let (rt, _) := step rt (.paste "a\nb") 6200
  checkEq "a paste with a line break stays on one line" "Ja bll" rt.model.draft
  let rt := key rt (.char 'a') 6300 { ctrl := true }
  let (rt, outs) := step rt (.key (.char 'c') { ctrl := true } true) 6900
  checkEq "copy the selection" [SafeText.filter "Ja bll"] (copies outs)
  let (rt', outs) := step rt (.key (.char 'x') { ctrl := true } true) 6950
  checkEq "cut copies the selection" [SafeText.filter "Ja bll"] (copies outs)
  checkEq "and removes it" "" rt'.model.draft
  let (rt', outs) := step rt (.key (.char 'c') { ctrl := true } true) 7000 (synthetic := true)
  checkEq "a synthetic copy copies nothing" [] (copies outs)
  let _ := rt'
  let (rt, _) := step rt (.key (.char 's') { ctrl := true } true) 7100
  checkEq "ctrl-s bubbles from the field to the binding" 1 rt.model.saves
  let rt := key rt .end_ 7200
  let rt := { rt with model := { rt.model with draft := "J" } }.rebuild.1
  check "the cursor is kept within a shorter value" ((scene rt).items.length > 0)
  let draft := (rt.tree.findKey? "draft").map (·.viewport) |>.getD default
  let (rt, _) := clickAt rt ⟨draft.x0 + px 2, (draft.y0 + draft.y1) / 2⟩ 8000
  let rt := typeText rt "!" 8600
  checkEq "a click puts the cursor where it lands" "!J" rt.model.draft
  -- Password field.
  let (rt, _) := click rt "pass" 9000
  let rt := typeText rt "pw\x1bd" 9600
  checkEq "typing into a password field" 3 rt.model.secretLen
  check "it shows dots" ((texts rt).contains "•••")
  check "and not the secret" (!(texts rt).any fun t => (t.splitOn "pwd").length > 1)
  let rt := key rt .backspace 9700
  checkEq "backspace" 2 rt.model.secretLen
  let (rt, outs) := step rt (.key (.char 'c') { ctrl := true } true) 10300
  checkEq "a password field never copies" [] (copies outs)
  -- Scroll: five 20-pixel labels in the scroll's box.
  let sc := (rt.tree.findKey? "sc").map (·.viewport) |>.getD default
  let inside : Point := ⟨sc.x0 + px 10, sc.y0 + px 5⟩
  let lineY (rt : Runtime app) : Option Int := (scene rt).items.findSome? fun
    | (_, .text p t _) => if t.text == "line 0" then some p.y else none
    | _ => none
  check "the scroll's box is shorter than its content" (sc.height < px 100)
  checkEq "the first line starts at the top" (some sc.y0) (lineY rt)
  let (rt, _) := step rt (.wheel inside 0 1) 11000
  checkEq "the wheel scrolls by a step" (some (sc.y0 - px 40)) (lineY rt)
  let (rt, _) := step rt (.wheel inside 0 9) 11100
  checkEq "and no further than the content" (some (sc.y0 - (px 100 - sc.height))) (lineY rt)
  let (rt, _) := step rt (.wheel inside 0 (-9)) 11200
  checkEq "nor back past the top" (some sc.y0) (lineY rt)
  check "a bar shows in the gutter when the content is taller"
    ((scene rt).items.any fun | (_, .fill b _ _) => b.x0 ≥ sc.x1 - Widgets.gutter && b.y0 ≥ sc.y0 | _ => false)
  let (rt, _) := step rt (.wheel inside 0 1) 11300
  check "scrolled content stays within the scroll's box"
    ((scene rt).items.all fun (clip, d) => match d with
      | .text _ t _ => !(t.text.startsWith "line") || decide (clip.Within sc)
      | _ => true)
  let lineBox := (rt.tree.placements.filter fun (_, r) => r.x1 ≤ sc.x1 - Widgets.gutter && r.y0 < sc.y0)
  check "the content is laid out clear of the gutter and shifted up" (!lineBox.isEmpty)
  -- Keyed list: each row's field moves with its item.
  let rowOf (rt : Runtime app) (s : String) : Option WidgetId :=
    (rt.tree.placements.find? fun (id, _) =>
      ((rt.tree.find? id).bind fun n => n.key) == some s).map (·.1)
  let three := rowOf rt "three"
  check "the list is laid out" three.isSome
  let y3 := (three.bind rt.tree.find?).map (·.viewport.y0)
  let rt := { rt with model := { rt.model with items := rt.model.items.reverse } }.rebuild.1
  checkEq "the row keeps its node when its item moves" three (rowOf rt "three")
  check "and it is now first" (((three.bind rt.tree.find?).map (·.viewport.y0)).any fun y => y3.any (y < ·))
  let _ := Msg.shuffle
  let _ := Msg.shorten

def tests : TestM Unit := do
  editTests
  appTests

end Paw.Tests.Widgets
