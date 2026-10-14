/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic
import Paw.Secret

/-! # Text fields

A one-line text field over a value from the model, as in Elm: the field keeps only its cursor and
selection, and reports each edit with `onChange`; the model decides the value. Editing is a set of
pure functions on `Edit`, tested on their own.

What is typed or pasted loses control characters, and line breaks and tabs become spaces, so a
paste cannot put a second line into a one-line field. What is shown is the value filtered, as any
text is. Copying needs the input to have designated the field (`Req.copy`).

A password field holds a `Secret`: it shows dots, has no selection, and never copies. -/

namespace Paw.Widgets

/-- A value being edited, with the cursor and, if text is selected, the other end of the selection. -/
structure Edit where
  value : List Char
  cursor : Nat := 0
  anchor : Option Nat := none
  deriving Repr, Inhabited

namespace Edit

def clamp (e : Edit) : Edit :=
  let n := e.value.length
  { e with cursor := min e.cursor n, anchor := e.anchor.map (min · n) }

/-- The selected range, if it is not empty. -/
def selection (e : Edit) : Option (Nat × Nat) :=
  e.anchor.bind fun a => if a == e.cursor then none else some (min a e.cursor, max a e.cursor)

def selected (e : Edit) : List Char :=
  match e.selection with
  | some (lo, hi) => (e.value.drop lo).take (hi - lo)
  | none => []

def deleteSelection (e : Edit) : Edit :=
  match e.selection with
  | some (lo, hi) => { value := e.value.take lo ++ e.value.drop hi, cursor := lo }
  | none => { e with anchor := none }

/-- `s` in place of the selection, or at the cursor; nothing past `maxLength`. -/
def insert (e : Edit) (s : List Char) (maxLength : Nat) : Edit :=
  let e := e.deleteSelection
  let s := s.take (maxLength - e.value.length)
  { value := e.value.take e.cursor ++ s ++ e.value.drop e.cursor, cursor := e.cursor + s.length }

def backspace (e : Edit) : Edit :=
  if e.selection.isSome then e.deleteSelection
  else if e.cursor == 0 then { e with anchor := none }
  else { value := e.value.take (e.cursor - 1) ++ e.value.drop e.cursor, cursor := e.cursor - 1 }

def delete (e : Edit) : Edit :=
  if e.selection.isSome then e.deleteSelection
  else { value := e.value.take e.cursor ++ e.value.drop (e.cursor + 1), cursor := e.cursor }

/-- The cursor at `to`, extending the selection if `extend`, else dropping it. -/
def moveTo (e : Edit) (to : Nat) (extend : Bool) : Edit :=
  let to := min to e.value.length
  if extend then { e with cursor := to, anchor := some (e.anchor.getD e.cursor) }
  else { e with cursor := to, anchor := none }

def left (e : Edit) (extend : Bool) : Edit :=
  match e.selection, extend with
  | some (lo, _), false => { e with cursor := lo, anchor := none }
  | _, _ => e.moveTo (e.cursor - 1) extend

def right (e : Edit) (extend : Bool) : Edit :=
  match e.selection, extend with
  | some (_, hi), false => { e with cursor := hi, anchor := none }
  | _, _ => e.moveTo (e.cursor + 1) extend

def selectAll (e : Edit) : Edit := { e with cursor := e.value.length, anchor := some 0 }

/-- A character of a word: a letter, a digit, an underscore, or anything beyond ASCII. -/
def wordChar (c : Char) : Bool := c.isAlphanum || c == '_' || c.toNat > 127

/-- The start of the word at or before `i`: back over what is not a word, then over the word. -/
def wordStart (cs : List Char) (i : Nat) : Nat :=
  let before := (cs.take i).reverse
  let gap := (before.takeWhile (!wordChar ·)).length
  i - gap - ((before.drop gap).takeWhile wordChar).length

/-- The end of the word at or after `i`: on over what is not a word, then over the word. -/
def wordEnd (cs : List Char) (i : Nat) : Nat :=
  let after := cs.drop i
  let gap := (after.takeWhile (!wordChar ·)).length
  min cs.length (i + gap + ((after.drop gap).takeWhile wordChar).length)

def wordLeft (e : Edit) (extend : Bool) : Edit := e.moveTo (wordStart e.value e.cursor) extend

def wordRight (e : Edit) (extend : Bool) : Edit := e.moveTo (wordEnd e.value e.cursor) extend

/-- The word before the cursor deleted, or the selection. -/
def deleteWordBack (e : Edit) : Edit :=
  if e.selection.isSome then e.deleteSelection
  else
    let s := wordStart e.value e.cursor
    { value := e.value.take s ++ e.value.drop e.cursor, cursor := s }

/-- The word after the cursor deleted, or the selection. -/
def deleteWordForward (e : Edit) : Edit :=
  if e.selection.isSome then e.deleteSelection
  else { value := e.value.take e.cursor ++ e.value.drop (wordEnd e.value e.cursor), cursor := e.cursor }

/-- The start of the line `i` is on, in text whose lines end with newlines. -/
def lineStart (cs : List Char) (i : Nat) : Nat :=
  i - ((cs.take i).reverse.takeWhile (· != '\n')).length

/-- The end of the line `i` is on, before its newline. -/
def lineEnd (cs : List Char) (i : Nat) : Nat := i + ((cs.drop i).takeWhile (· != '\n')).length

end Edit

/-- What an edit can go back to: earlier states, latest first, and states undone, to redo. At most
`History.limit` are kept. -/
structure History (α : Type) where
  past : List α := []
  future : List α := []
  deriving Inhabited

namespace History

variable {α : Type}

def limit : Nat := 100

/-- `s`, the state before a change, kept to go back to; what was undone can no longer be redone. -/
def record (h : History α) (s : α) : History α := { past := (s :: h.past).take limit, future := [] }

/-- The state before the last change, from `cur`, and the history after going back. -/
def undo (h : History α) (cur : α) : Option (α × History α) :=
  match h.past with
  | s :: ps => some (s, { past := ps, future := cur :: h.future })
  | [] => none

/-- The state last undone, from `cur`, and the history after going forward again. -/
def redo (h : History α) (cur : α) : Option (α × History α) :=
  match h.future with
  | s :: fs => some (s, { past := (cur :: h.past).take limit, future := fs })
  | [] => none

end History

/-- What typing or pasting may put in a one-line field: no control characters, and line breaks
and tabs as spaces. -/
def cleanInput (s : String) : List Char :=
  s.toList.filterMap fun c =>
    if c == '\n' || c == '\r' || c == '\t' then some ' '
    else if Text.control c.toNat then none
    else some c

structure TextFieldState where
  cursor : Nat := 0
  anchor : Option Nat := none
  /-- When the caret last moved or focus arrived: it shows from then, blinking. -/
  since : Nat := 0
  /-- Values and cursors to undo to. -/
  history : History (List Char × Nat) := {}
  /-- Text an input method is composing at the caret, and its cursor. -/
  preedit : Option (SafeText × Nat) := none
  deriving TypeName, Inhabited

/-- Text an input method is composing, drawn at `x` on the line in `v`, underlined. -/
def preeditDraw (env : Env) (v : Rect) (x : Int) (t : SafeText) (style : TextStyle) : List Draw :=
  let (w, h) := env.measure style t
  let y := v.y0 + (v.height - h) / 2
  [.text ⟨x, y⟩ t style, .fill (Rect.ofXYWH x (y + h - px 2) w (px 1)) style.color 0]

/-- How long the caret shows, then hides, while it blinks. -/
def blinkMs : Nat := 500

/-- The caret shows at `now`: the field and the window have focus, and the caret is in the shown
half of its blink, counted from `since`. -/
def caretShown (env : Env) (since : Nat) : Bool :=
  env.isFocused && env.windowFocused && ((env.now - since) / blinkMs) % 2 == 0

structure TextFieldCfg where
  maxLength : Nat := 10000
  placeholder : SafeText := SafeText.empty
  deriving Inhabited

/-- The cursor index nearest `x` units from the text's start. -/
def indexAt (measure : SafeText → Int) (value : List Char) (x : Int) : Nat := Id.run do
  let mut best := 0
  let mut bestD := x.natAbs
  for i in [1:value.length + 1] do
    let d := (measure (SafeText.filter (String.ofList (value.take i))) - x).natAbs
    if d < bestD then
      best := i
      bestD := d
  return best

/-- A one-line field showing `value`, reporting edits with `onChange`. -/
def textField {Msg : Type} (value : String) (onChange : String → Msg) (cfg : TextFieldCfg := {}) :
    Widget Msg :=
  let chars := value.toList
  let edit (st : TextFieldState) : Edit := Edit.clamp { value := chars, cursor := st.cursor, anchor := st.anchor }
  let result (st : TextFieldState) (now : Nat) (e : Edit) (extra : List (Req Msg) := []) :
      Option (TextFieldState × List (Req Msg)) :=
    let same := e.value == chars
    let changed := if same then [] else [Req.emit (onChange (String.ofList e.value))]
    let history := if same then st.history else st.history.record (chars, st.cursor)
    some ({ cursor := e.cursor, anchor := e.anchor, since := now, history, preedit := none }, extra ++ changed)
  -- Going back or forward in the history: the value it holds, and its cursor.
  let travel (st : TextFieldState) (now : Nat) (to : Option ((List Char × Nat) × History (List Char × Nat))) :
      Option (TextFieldState × List (Req Msg)) :=
    match to with
    | some ((v, c), history) =>
      some ({ st with cursor := c, anchor := none, since := now, history }, [Req.emit (onChange (String.ofList v))])
    | none => some (st, [])
  Widget.Spec.build (σ := TextFieldState) {
    kind := "textField"
    init := { cursor := chars.length }
    merge := fun st =>
      { st with cursor := min st.cursor chars.length, anchor := st.anchor.map (min · chars.length) }
    sizeReq := fun env _ =>
      let (_, h) := env.measure (textStyle env) (SafeText.trusted "M")
      (SizeReq.minSize (px 120).toNat, SizeReq.fixedSize (h + 2 * env.theme.textField.padding.2).toNat)
    render := fun env st v =>
      let t := env.theme
      let s := env.look t.textField
      let (padX, padY) := t.textField.padding
      let style := { textStyle env with color := s.fg }
      let e := edit st
      let width (n : Nat) := (env.measure style (SafeText.filter (String.ofList (chars.take n)))).1
      let inner := v.width - 2 * padX
      let caretX := width e.cursor
      let shift := max 0 (caretX - inner + px 2)
      let x0 := v.x0 + padX - shift
      let shown := if chars.isEmpty then [centeredText env v x0 cfg.placeholder { style with color := t.muted }]
        else [centeredText env v x0 (SafeText.filter value) style]
      let sel := match e.selection with
        | some (lo, hi) => [Draw.fill (Rect.ofXYWH (x0 + width lo) (v.y0 + padY) (width hi - width lo)
            (v.height - 2 * padY)) (Color.rgba t.accent.r t.accent.g t.accent.b 80) 0]
        | none => []
      let caret := if caretShown env st.since then
          [Draw.fill (Rect.ofXYWH (x0 + caretX) (v.y0 + padY) (px 1) (v.height - 2 * padY)) s.fg 0]
        else []
      let composing := match st.preedit with
        | some (p, _) => Draw.fill (Rect.ofXYWH (x0 + caretX) (v.y0 + padY) (env.measure style p).1
            (v.height - 2 * padY)) s.bg 0 :: preeditDraw env v (x0 + caretX) p style
        | none => []
      Scene.inBox v (frame v s ++ sel ++ shown ++ caret ++ composing)
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v ev =>
      let e := edit st
      let result (e : Edit) (extra : List (Req Msg) := []) := result st env.now e extra
      match ev with
      | .text s | .paste s => result (e.insert (cleanInput s) cfg.maxLength)
      | .key .backspace m true => result (if m.ctrl then e.deleteWordBack else e.backspace)
      | .key .delete m true => result (if m.ctrl then e.deleteWordForward else e.delete)
      | .key .left m true => result (if m.ctrl then e.wordLeft m.shift else e.left m.shift)
      | .key .right m true => result (if m.ctrl then e.wordRight m.shift else e.right m.shift)
      | .key (.char 'z') m true =>
        if !m.ctrl then none
        else if m.shift then travel st env.now (st.history.redo (chars, st.cursor))
        else travel st env.now (st.history.undo (chars, st.cursor))
      | .key (.char 'Z') m true | .key (.char 'y') m true =>
        if m.ctrl then travel st env.now (st.history.redo (chars, st.cursor)) else none
      | .key .home m true => result (e.moveTo 0 m.shift)
      | .key .end_ m true => result (e.moveTo chars.length m.shift)
      | .key (.char 'a') m true => if m.ctrl then result e.selectAll else none
      | .key (.char 'c') m true =>
        if m.ctrl then result e [.copy (SafeText.filter (String.ofList e.selected))] else none
      | .key (.char 'x') m true =>
        if m.ctrl then result e.deleteSelection [.copy (SafeText.filter (String.ofList e.selected))]
        else none
      | .press p .primary =>
        let measure (t : SafeText) := (env.measure (textStyle env) t).1
        result (e.moveTo (indexAt measure chars (p.x - v.x0 - env.theme.textField.padding.1)) false)
      | .preedit p c => some ({ st with preedit := if p.text.isEmpty then none else some (p, c) }, [])
      | .focus => some ({ st with since := env.now }, [])
      | .blur => some ({ st with preedit := none }, [])
      | .tick _ | .enter _ | .leave _ => some (st, [])
      | _ => none
    focusable := true
    every := some fun env _ => if env.isFocused && env.windowFocused then some blinkMs else none
    cursor := fun env _ => (env.look env.theme.textField).cursor
    ime := some fun env st v =>
      let (padX, padY) := env.theme.textField.padding
      let inner := v.width - 2 * padX
      let width (n : Nat) := (env.measure (textStyle env) (SafeText.filter (String.ofList (chars.take n)))).1
      let caretX := width (min st.cursor chars.length)
      let x := v.x0 + padX - max 0 (caretX - inner + px 2) + caretX
      Rect.ofXYWH x (v.y0 + padY) (px 1) (v.height - 2 * padY)
    access := fun _ _ =>
      some { role := .textInput, name := cfg.placeholder, value := some (SafeText.filter value) } }

/-- What a password field keeps: the secrets it held, to undo to. They are forgotten when the
field loses focus, so no earlier secret outlives the editing of it. -/
structure PasswordState where
  history : History Secret := {}
  deriving TypeName, Inhabited

/-- A field for a secret: dots, no selection, no copying. -/
def passwordField {Msg : Type} (value : Secret) (onChange : Secret → Msg) : Widget Msg :=
  let change (st : PasswordState) (s : Secret) : Option (PasswordState × List (Req Msg)) :=
    some ({ history := st.history.record value }, [.emit (onChange s)])
  let travel (st : PasswordState) (to : Option (Secret × History Secret)) : Option (PasswordState × List (Req Msg)) :=
    match to with
    | some (s, history) => some ({ history }, [.emit (onChange s)])
    | none => some (st, [])
  Widget.Spec.build (σ := PasswordState) {
    kind := "passwordField"
    init := {}
    sizeReq := fun env _ =>
      let (_, h) := env.measure (textStyle env) (SafeText.trusted "M")
      (SizeReq.minSize (px 120).toNat, SizeReq.fixedSize (h + 2 * env.theme.textField.padding.2).toNat)
    render := fun env _ v =>
      let s := env.look env.theme.textField
      Scene.inBox v (frame v s ++ [centeredText env v (v.x0 + env.theme.textField.padding.1) value.dots
        { textStyle env with color := s.fg }])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .text s | .paste s =>
        let cs := cleanInput s
        if cs.isEmpty then some (st, []) else change st (cs.foldl Secret.push value)
      | .key .backspace _ true => change st value.pop
      | .key (.char 'z') m true =>
        if !m.ctrl then none else if m.shift then travel st (st.history.redo value) else travel st (st.history.undo value)
      | .key (.char 'Z') m true | .key (.char 'y') m true => if m.ctrl then travel st (st.history.redo value) else none
      | .blur => some ({}, [])
      | .focus | .enter _ | .leave _ => some (st, [])
      | _ => none
    focusable := true
    cursor := fun env _ => (env.look env.theme.textField).cursor
    access := fun _ _ => some { role := .passwordInput } }

end Paw.Widgets
