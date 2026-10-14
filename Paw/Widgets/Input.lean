/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.TextField
import Paw.Format

/-! # Fields for values

A field for a value of any type with a `Format`: the text being typed is the field's own, and a
value goes to the model only when the text reads as one. While it does not, the field is marked,
and when the field loses focus such text gives way to the model's value again. Numbers can also be
stepped by Up and Down and by the wheel, and a number with bounds is of a refinement type, so a
value out of bounds cannot be made. -/

namespace Paw.Widgets

structure InputState where
  text : List Char := []
  cursor : Nat := 0
  anchor : Option Nat := none
  since : Nat := 0
  history : History (List Char × Nat) := {}
  deriving TypeName, Inhabited

/-- A field for `value`, written and read by `fmt`, reporting new values with `onChange`. Up and
Down, and the wheel, give `step true` and `step false` of the value, if it steps. -/
def inputField {Msg α : Type} [BEq α] (fmt : Format α) (value : α) (onChange : α → Msg)
    (role : Role := .textInput) (step : Option (Bool → α → α) := none)
    (range : α → Option (Int × Int × Int) := fun _ => none) (maxLength : Nat := 64) : Widget Msg :=
  let shown := fmt.print value
  let valid (cs : List Char) : Bool := (fmt.parse cs).isSome
  -- The state after an edit: what is typed, and the value it reads as, if any is new.
  let result (st : InputState) (now : Nat) (e : Edit) (extra : List (Req Msg) := []) :
      Option (InputState × List (Req Msg)) :=
    let same := e.value == st.text
    let history := if same then st.history else st.history.record (st.text, st.cursor)
    let out := if same then [] else match fmt.parse e.value with
      | some v => if v == value then [] else [Req.emit (onChange v)]
      | none => []
    some ({ text := e.value, cursor := e.cursor, anchor := e.anchor, since := now, history }, extra ++ out)
  let stepTo (st : InputState) (now : Nat) (up : Bool) : Option (InputState × List (Req Msg)) :=
    match step with
    | some f =>
      let v := f up ((fmt.parse st.text).getD value)
      let t := fmt.print v
      some ({ st with text := t, cursor := t.length, anchor := none, since := now },
        if v == value then [] else [.emit (onChange v)])
    | none => none
  Widget.Spec.build (σ := InputState) {
    kind := "inputField"
    init := { text := shown, cursor := shown.length }
    -- Text the model's value would not read from gives way to it; text that reads as it stays.
    merge := fun st =>
      if fmt.parse st.text == some value then st
      else { st with text := shown, cursor := shown.length, anchor := none }
    sizeReq := fun env _ =>
      let (_, h) := env.measure (textStyle env) (SafeText.trusted "M")
      (SizeReq.minSize (px 80).toNat, SizeReq.fixedSize (h + 2 * env.theme.textField.padding.2).toNat)
    render := fun env st v =>
      let t := env.theme
      let s := env.look t.textField
      let s := if valid st.text then s else { s with border := t.error, borderWidth := max s.borderWidth (px 2) }
      let (padX, padY) := t.textField.padding
      let style := { textStyle env with color := s.fg }
      let e : Edit := Edit.clamp { value := st.text, cursor := st.cursor, anchor := st.anchor }
      let width (n : Nat) := (env.measure style (SafeText.filterChars (st.text.take n))).1
      let x0 := v.x0 + padX - max 0 (width e.cursor - (v.width - 2 * padX) + px 2)
      let sel := match e.selection with
        | some (lo, hi) => [Draw.fill (Rect.ofXYWH (x0 + width lo) (v.y0 + padY) (width hi - width lo)
            (v.height - 2 * padY)) (Color.rgba t.accent.r t.accent.g t.accent.b 80) 0]
        | none => []
      let caret := if caretShown env st.since then
          [Draw.fill (Rect.ofXYWH (x0 + width e.cursor) (v.y0 + padY) (px 1) (v.height - 2 * padY)) s.fg 0]
        else []
      Scene.inBox v (frame v s ++ sel ++ [centeredText env v x0 (SafeText.filterChars st.text) style] ++ caret)
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v ev =>
      let e : Edit := Edit.clamp { value := st.text, cursor := st.cursor, anchor := st.anchor }
      let result (e : Edit) (extra : List (Req Msg) := []) := result st env.now e extra
      let travel (to : Option ((List Char × Nat) × History (List Char × Nat))) : Option (InputState × List (Req Msg)) :=
        match to with
        | some ((t, c), history) =>
          let out := match fmt.parse t with
            | some x => if x == value then [] else [Req.emit (onChange x)]
            | none => []
          some ({ st with text := t, cursor := c, anchor := none, since := env.now, history }, out)
        | none => some (st, [])
      match ev with
      | .text s | .paste s => result (e.insert (cleanInput s) maxLength)
      | .key .backspace m true => result (if m.ctrl then e.deleteWordBack else e.backspace)
      | .key .delete m true => result (if m.ctrl then e.deleteWordForward else e.delete)
      | .key .left m true => result (if m.ctrl then e.wordLeft m.shift else e.left m.shift)
      | .key .right m true => result (if m.ctrl then e.wordRight m.shift else e.right m.shift)
      | .key .home m true => result (e.moveTo 0 m.shift)
      | .key .end_ m true => result (e.moveTo st.text.length m.shift)
      | .key .up _ true => stepTo st env.now true
      | .key .down _ true => stepTo st env.now false
      | .wheel _ _ dy => if dy == 0 then none else stepTo st env.now (dy < 0)
      | .key (.char 'a') m true => if m.ctrl then result e.selectAll else none
      | .key (.char 'c') m true => if m.ctrl then result e [.copy (SafeText.filterChars e.selected)] else none
      | .key (.char 'x') m true => if m.ctrl then result e.deleteSelection [.copy (SafeText.filterChars e.selected)] else none
      | .key (.char 'z') m true =>
        if !m.ctrl then none
        else if m.shift then travel (st.history.redo (st.text, st.cursor)) else travel (st.history.undo (st.text, st.cursor))
      | .key (.char 'Z') m true | .key (.char 'y') m true =>
        if m.ctrl then travel (st.history.redo (st.text, st.cursor)) else none
      | .press p .primary =>
        let measure (t : SafeText) := (env.measure (textStyle env) t).1
        result (e.moveTo (indexAt measure st.text (p.x - v.x0 - env.theme.textField.padding.1)) false)
      | .focus => some ({ st with since := env.now }, [])
      -- Leaving the field gives up text that is not a value, and shows the model's.
      | .blur => some (if valid st.text then st else { st with text := shown, cursor := shown.length, anchor := none }, [])
      | .tick _ | .enter _ | .leave _ => some (st, [])
      | _ => none
    focusable := true
    every := some fun env _ => if env.isFocused && env.windowFocused then some blinkMs else none
    cursor := fun env _ => (env.look env.theme.textField).cursor
    access := fun _ st => some { role, value := some (SafeText.filterChars st.text), range := range value } }

/-- An integer between `lo` and `hi`, typed or stepped by `by`. -/
def numericField {Msg : Type} {lo hi : Int} (value : { x : Int // lo ≤ x ∧ x ≤ hi })
    (onChange : { x : Int // lo ≤ x ∧ x ≤ hi } → Msg) (by_ : Nat := 1) : Widget Msg :=
  let fmt := Format.bounded Format.int lo hi
  have hb : lo ≤ hi := by have := value.2; omega
  inputField fmt value onChange (role := .spin)
    (step := some fun up x => ⟨max lo (min hi (if up then x.1 + by_ else x.1 - by_)), by omega⟩)
    (range := fun x => some (lo, hi, x.1))

/-- A number with `places` decimal places, in units of `10 ^ -places`, between `lo` and `hi`. -/
def decimalField {Msg : Type} {lo hi : Int} (places : Nat) (hp : 1 ≤ places)
    (value : { x : Int // lo ≤ x ∧ x ≤ hi }) (onChange : { x : Int // lo ≤ x ∧ x ≤ hi } → Msg)
    (by_ : Nat := 1) : Widget Msg :=
  have hb : lo ≤ hi := by have := value.2; omega
  inputField (Format.bounded (Format.decimal places hp) lo hi) value onChange (role := .spin)
    (step := some fun up x => ⟨max lo (min hi (if up then x.1 + by_ else x.1 - by_)), by omega⟩)
    (range := fun x => some (lo, hi, x.1))

/-- A date, typed as year, month and day. -/
def dateField {Msg : Type} (value : Format.Date) (onChange : Format.Date → Msg) : Widget Msg :=
  inputField Format.date value onChange (role := .dateInput)

/-- A time of day, typed as hours and minutes. -/
def timeField {Msg : Type} (value : Format.Time) (onChange : Format.Time → Msg) : Widget Msg :=
  inputField Format.time value onChange (role := .timeInput)

end Paw.Widgets
