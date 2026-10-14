/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Ui
import Paw.Tests.Util

/-! # Editing text

Moving by words and lines, undo and redo, the text area's rows and keys, and input methods. -/

namespace Paw.Tests.Edit

open Paw Widgets

def e (s : String) (cursor : Nat) : Edit := { value := s.toList, cursor }
def str (x : Edit) : String × Nat := (String.ofList x.value, x.cursor)

inductive Msg where
  | name (s : String)
  | notes (s : String)
  | pass (s : Secret)
  deriving Inhabited

structure Model where
  name : String := ""
  notes : String := ""
  pass : Secret := Secret.empty

instance : BEq Model := ⟨fun a b => a.name == b.name && a.notes == b.notes && a.pass.eq b.pass⟩

def view (m : Model) : Node Msg :=
  Ui.col [Ui.textField m.name .name {} "name", Ui.passwordField m.pass .pass "pass",
    -- In a row, so that it keeps its width: 80 pixels inside its padding.
    Ui.row [Ui.width (px 96) (Ui.textArea m.notes .notes { rows := 3 } "notes")]]

def update : (o : Origin) → Msg → UpdateM Model Msg [] o Unit
  | _, .name s => modify fun (m, cs) => ({ m with name := s }, cs)
  | _, .notes s => modify fun (m, cs) => ({ m with notes := s }, cs)
  | _, .pass s => modify fun (m, cs) => ({ m with pass := s }, cs)

def app : App [] := { Model := Model, Msg := Msg, init := {}, view, update }

def start : Runtime app := (Runtime.start app (Rect.ofXYWH 0 0 (px 300) (px 300)) 0 Env.mock.measure).1

def input (rt : Runtime app) (k : InputKind) (t : Nat) : Runtime app × List (Output Msg) :=
  rt.step (.input { kind := k, time := t }) t

def key (rt : Runtime app) (k : Key) (t : Nat) (m : Mods := {}) : Runtime app := (input rt (.key k m true) t).1
def type (rt : Runtime app) (s : String) (t : Nat) : Runtime app := (input rt (.text s) t).1

def focus (rt : Runtime app) (k : String) (t : Nat) : Runtime app :=
  match rt.tree.findKey? k with
  | some n =>
    let p : Point := ⟨n.viewport.x0 + px 2, n.viewport.y0 + px 2⟩
    (input (input rt (.press p .primary) t).1 (.release p .primary) (t + 10)).1
  | none => rt

def texts (rt : Runtime app) : List String :=
  match rt.present with
  | .request (.present s) => s.items.filterMap fun (_, d) => match d with
    | Draw.text _ t _ => some t.text
    | _ => none
  | _ => []

def imeRequests (outs : List (Output Msg)) : List (Option Rect) :=
  outs.filterMap fun | .request (.ime a) => some a | _ => none

def tests : TestM Unit := do
  -- Words.
  checkEq "back over a word" ("hello world", 6) (str ((e "hello world" 11).wordLeft false))
  checkEq "back over spaces, then the word" ("hello   world", 0) (str ((e "hello   world" 8).wordLeft false))
  checkEq "on over a word" ("hello world", 5) (str ((e "hello world" 0).wordRight false))
  checkEq "on over spaces, then the word" ("hello world", 11) (str ((e "hello world" 5).wordRight false))
  checkEq "punctuation is not a word" 5 (Edit.wordStart "a.b, cd".toList 7)
  checkEq "Ctrl-Backspace deletes the word before" ("hello ", 6) (str (e "hello world" 11).deleteWordBack)
  checkEq "Ctrl-Delete the word after" ("hello", 5) (str (e "hello world" 5).deleteWordForward)
  checkEq "a selection goes first" ("hello", 5)
    (str ({ e "hello world" 11 with anchor := some 5 }).deleteWordBack)
  checkEq "words of other scripts" ("слово ", 6) (str ((e "слово слово" 11).deleteWordBack))
  -- Lines.
  checkEq "the start of the line" 4 (Edit.lineStart "abc\ndef".toList 6)
  checkEq "the end" 7 (Edit.lineEnd "abc\ndef".toList 5)
  checkEq "on the first line" (0, 3) (Edit.lineStart "abc\ndef".toList 2, Edit.lineEnd "abc\ndef".toList 2)
  -- History.
  let h : History Nat := ({} : History Nat).record 1 |>.record 2
  checkEq "undo goes back" (some (2, [1], [3])) ((h.undo 3).map fun (s, h) => (s, h.past, h.future))
  checkEq "redo forward" (some 3) (((h.undo 3).bind fun (_, h) => h.redo 2).map (·.1))
  checkEq "a change after undo drops what was undone" ([] : List Nat) (((h.undo 3).map fun (_, h) => (h.record 9).future).getD [1])
  checkEq "at most a hundred steps" 100 (((List.range 150).foldl (fun h i => h.record i) ({} : History Nat)).past.length)
  checkEq "nothing to undo" none ((({} : History Nat).undo 0).map (·.1))
  -- Undo and redo in a field.
  let rt := focus start "name" 1000
  let rt := type rt "ab" 1100
  let rt := type rt "c" 1200
  checkEq "typed" "abc" rt.model.name
  let rt := key rt (.char 'z') 1300 { ctrl := true }
  checkEq "Ctrl-Z undoes the last change" "ab" rt.model.name
  let rt := key rt (.char 'z') 1400 { ctrl := true }
  checkEq "and the one before" "" rt.model.name
  let rt := key rt (.char 'Z') 1500 { ctrl := true, shift := true }
  checkEq "Ctrl-Shift-Z redoes" "ab" rt.model.name
  let rt := key rt (.char 'y') 1600 { ctrl := true }
  checkEq "and Ctrl-Y" "abc" rt.model.name
  let rt := key rt .backspace 1700 { ctrl := true }
  checkEq "Ctrl-Backspace deletes a word" "" rt.model.name
  -- A password field's history is forgotten when it loses focus.
  let rt := focus start "pass" 1000
  let rt := type rt "se" 1100
  let rt := type rt "cret" 1200
  let rt := key rt (.char 'z') 1300 { ctrl := true }
  checkEq "Ctrl-Z in a password field" 2 rt.model.pass.length
  let rt := focus rt "name" 1400
  let rt := focus rt "pass" 1500
  let rt := key rt (.char 'z') 1600 { ctrl := true }
  checkEq "after leaving it, nothing is left to undo" 2 rt.model.pass.length
  -- A text area: newlines, rows, Up and Down.
  let rt := focus start "notes" 1000
  let rt := type rt "one two three" 1100
  let rt := key rt .enter 1200
  let rt := type rt "four" 1300
  checkEq "Enter puts a newline" "one two three\nfour" rt.model.notes
  let rt := type rt "\ttab\x1b" 1400
  checkEq "typing keeps newlines but no other controls, and tabs as spaces" "one two three\nfour tab"
    rt.model.notes
  let ws : Widths := Widths.of Env.mock {} [SafeText.trusted "one two three", SafeText.trusted "four tab"]
  let rs := rows ws (px 80) "one two three\nfour tab".toList
  checkEq "each line wrapped to rows, each with where it starts"
    [(0, "one two "), (8, "three"), (14, "four tab")] (rs.map fun r => (r.start, String.ofList r.chars))
  checkEq "the row of a position" [0, 1, 1, 2] ([3, 8, 13, 14].map (rowOf rs ·))
  let up := key rt .up 1500
  checkEq "Up moves to the row above, as near the same x as it has" 13 ((up.tree.findKey? "notes").bind
    (·.state? TextAreaState) |>.map (·.cursor) |>.getD 0)
  let rt2 := key (key rt .home 1500) .up 1600
  checkEq "Home then Up: the start of the row above" 8 ((rt2.tree.findKey? "notes").bind (·.state? TextAreaState)
    |>.map (·.cursor) |>.getD 0)
  let rt3 := key rt .home 1500 { ctrl := true }
  checkEq "Ctrl-Home: the start" 0 ((rt3.tree.findKey? "notes").bind (·.state? TextAreaState) |>.map (·.cursor) |>.getD 1)
  let rt4 := key rt3 .end_ 1600
  checkEq "End: the end of the line" 13 ((rt4.tree.findKey? "notes").bind (·.state? TextAreaState) |>.map (·.cursor) |>.getD 0)
  let rt5 := key rt4 .down 1700
  checkEq "Down: the row below, near the same x" 19 ((rt5.tree.findKey? "notes").bind (·.state? TextAreaState) |>.map (·.cursor) |>.getD 0)
  -- A long text scrolls to keep the caret in view.
  let long := type (focus start "notes" 1000) (String.intercalate "\n" ((List.range 20).map toString)) 1100
  let off := (long.tree.findKey? "notes").bind (·.state? TextAreaState) |>.map (·.offset) |>.getD 0
  check "typing past the bottom scrolls" (off > 0)
  let top := key long .home 1200 { ctrl := true }
  checkEq "going to the start scrolls back" (some 0) ((top.tree.findKey? "notes").bind (·.state? TextAreaState) |>.map (·.offset))
  check "the area draws within its box" ((long.tree.findKey? "notes").all fun n => decide ((n.render long.env).Within n.viewport))
  -- Input methods.
  let (rt, outs) := input start (.press ⟨px 2, px 2⟩ .primary) 1000
  checkEq "focusing a text field turns an input method on, at its caret" 1 ((imeRequests outs).filter (·.isSome)).length
  let (rt, _) := input rt (.release ⟨px 2, px 2⟩ .primary) 1010
  let (rt, _) := input rt (.preedit "にほ" 2) 1100
  check "composing text is drawn" ((texts rt).contains "にほ")
  checkEq "but is not the value yet" "" rt.model.name
  let (rt, _) := input rt (.text "日本") 1200
  checkEq "what the input method commits arrives as text" "日本" rt.model.name
  check "and the composing text goes" (!(texts rt).contains "にほ")
  let (_, outs) := input (input rt (.press ⟨px 2, px 36⟩ .primary) 1300).1 (.release ⟨px 2, px 36⟩ .primary) 1310
  let pw := focus start "pass" 1000
  checkEq "a password field turns the input method off" none pw.ime
  checkEq "moving to it from a field asks it off" [none] (imeRequests (outs ++ (input (focus rt "name" 1400) (.press ⟨px 2, px 36⟩ .primary) 1500).2) |>.take 1)
  let (blurred, outs) := (focus start "name" 1000).step (.focus false) 1100
  checkEq "and so does the window losing focus" [none] (imeRequests outs)
  checkEq "composed text is not delivered while the window lacks focus" "" (input blurred (.preedit "x" 1) 1200).1.model.name

end Paw.Tests.Edit
