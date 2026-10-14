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

end Edit

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
  deriving TypeName, Repr, Inhabited

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
  let result (e : Edit) (extra : List (Req Msg) := []) : Option (TextFieldState × List (Req Msg)) :=
    let changed := if e.value == chars then [] else [Req.emit (onChange (String.ofList e.value))]
    some ({ cursor := e.cursor, anchor := e.anchor }, extra ++ changed)
  Widget.Spec.build (σ := TextFieldState) {
    kind := "textField"
    init := { cursor := chars.length }
    merge := fun st => { cursor := min st.cursor chars.length, anchor := st.anchor.map (min · chars.length) }
    sizeReq := fun env _ =>
      let (_, h) := env.measure (textStyle env) (SafeText.trusted "M")
      (SizeReq.minSize (px 120).toNat, SizeReq.fixedSize (h + 2 * padY).toNat)
    render := fun env st v =>
      let t := env.theme
      let style := textStyle env
      let e := edit st
      let width (n : Nat) := (env.measure style (SafeText.filter (String.ofList (chars.take n)))).1
      let inner := v.width - 2 * padX
      let caretX := width e.cursor
      let shift := max 0 (caretX - inner + px 2)
      let x0 := v.x0 + padX - shift
      let (border, bw) := if env.isFocused then (t.accent, px 2) else (t.border, px 1)
      let shown := if chars.isEmpty then [centeredText env v x0 cfg.placeholder { style with color := t.border }]
        else [centeredText env v x0 (SafeText.filter value) style]
      let sel := match e.selection with
        | some (lo, hi) => [Draw.fill (Rect.ofXYWH (x0 + width lo) (v.y0 + padY) (width hi - width lo)
            (v.height - 2 * padY)) (Color.rgba t.accent.r t.accent.g t.accent.b 80) 0]
        | none => []
      let caret := if env.isFocused then
          [Draw.fill (Rect.ofXYWH (x0 + caretX) (v.y0 + padY) (px 1) (v.height - 2 * padY)) t.text 0]
        else []
      Scene.inBox v ([.fill v t.surface (px 3), .stroke v border bw (px 3)] ++ sel ++ shown ++ caret)
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v ev =>
      let e := edit st
      match ev with
      | .text s | .paste s => result (e.insert (cleanInput s) cfg.maxLength)
      | .key .backspace _ true => result e.backspace
      | .key .delete _ true => result e.delete
      | .key .left m true => result (e.left m.shift)
      | .key .right m true => result (e.right m.shift)
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
        result (e.moveTo (indexAt measure chars (p.x - v.x0 - padX)) false)
      | .focus | .blur | .enter _ | .leave _ => some (st, [])
      | _ => none
    focusable := true
    access := fun _ _ =>
      some { role := .textInput, name := cfg.placeholder, value := some (SafeText.filter value) } }

/-- A field for a secret: dots, no selection, no copying. -/
def passwordField {Msg : Type} (value : Secret) (onChange : Secret → Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "passwordField"
    init := {}
    sizeReq := fun env _ =>
      let (_, h) := env.measure (textStyle env) (SafeText.trusted "M")
      (SizeReq.minSize (px 120).toNat, SizeReq.fixedSize (h + 2 * padY).toNat)
    render := fun env _ v =>
      let t := env.theme
      let (border, bw) := if env.isFocused then (t.accent, px 2) else (t.border, px 1)
      Scene.inBox v [.fill v t.surface (px 3), .stroke v border bw (px 3),
        centeredText env v (v.x0 + padX) value.dots (textStyle env)]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .text s | .paste s =>
        let cs := cleanInput s
        if cs.isEmpty then some (st, []) else some (st, [.emit (onChange (cs.foldl Secret.push value))])
      | .key .backspace _ true => some (st, [.emit (onChange value.pop)])
      | .focus | .blur | .enter _ | .leave _ => some (st, [])
      | _ => none
    focusable := true
    access := fun _ _ => some { role := .passwordInput } }

end Paw.Widgets
