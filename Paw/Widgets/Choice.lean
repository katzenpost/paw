/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Choices

Radio buttons, option buttons, toggle buttons and tabs are one widget, as in monomer's
`makeOptionButton`: a control that is chosen or not, and asks for its choice when clicked, or when
Space (or Enter, for one that looks like a button) is pressed on it. Each says what it is to
assistive technology, and whether it is chosen. Separators are lines between things. -/

namespace Paw.Widgets

open SizeReq

/-- How a choice is drawn: as a button, or as a circle with a caption beside it. -/
inductive ChoiceLook where
  | button
  | radio
  deriving Repr, DecidableEq, Inhabited

/-- A control chosen or not, emitting `onPick` when activated. -/
def choice {Msg : Type} (kind : String) (look : ChoiceLook) (role : Role) (caption : SafeText) (chosen : Bool)
    (onPick : Msg) : Widget Msg :=
  let style (env : Env) : Style := match look with
    | .button => if chosen then env.theme.toggleOn else env.theme.toggle
    | .radio => env.theme.checkbox
  Widget.Spec.build (σ := NoState) {
    kind
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      match look with
      | .button =>
        let (padX, padY) := (style env).padding
        (fixedSize (w + 2 * padX).toNat, fixedSize (h + 2 * padY).toNat)
      | .radio => (fixedSize (h + captionGap + w).toNat, fixedSize h.toNat)
    render := fun env _ v =>
      let s := env.look (style env)
      Scene.inBox v <| match look with
      | .button =>
        let st := { textStyle env with color := s.fg }
        let (w, _) := env.measure st caption
        frame v s ++ [centeredText env v (v.x0 + (v.width - w) / 2) caption st]
      | .radio =>
        let t := env.theme
        let side := min (env.measure (textStyle env) caption).2 v.height
        let circle := Rect.ofXYWH v.x0 (v.y0 + (v.height - side) / 2) side side
        let dot := circle.shrink (side * 3 / 10) (side * 3 / 10) (side * 3 / 10) (side * 3 / 10)
        let captionStyle := { textStyle env with color := if env.enabled then t.text else t.muted }
        frame circle { s with radius := side / 2 } ++
          (if chosen then [.fill dot (if env.enabled then t.accent else s.fg) (side / 2)] else []) ++
          [centeredText env v (v.x0 + side + captionGap) caption captionStyle]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. | .key (.char ' ') _ true => some (st, [.emit onPick])
      | .key .enter _ true => if look == .button then some (st, [.emit onPick]) else none
      | .enter _ | .leave _ | .press .. | .release .. | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    access := fun _ _ => some { role, name := caption, checked := some chosen } }

/-- A radio button for `value`, chosen when it is `current`. -/
def radio {Msg α : Type} [BEq α] (caption : SafeText) (value current : α) (onChange : α → Msg) : Widget Msg :=
  choice "radio" .radio .radio caption (value == current) (onChange value)

/-- A button for `value`, shown pressed when it is `current`: one of a group, as radios are. -/
def optionButton {Msg α : Type} [BEq α] (caption : SafeText) (value current : α) (onChange : α → Msg) :
    Widget Msg :=
  choice "optionButton" .button .radio caption (value == current) (onChange value)

/-- A button that stays pressed while `on`, and asks for the other when clicked. -/
def toggleButton {Msg : Type} (caption : SafeText) (on : Bool) (onChange : Bool → Msg) : Widget Msg :=
  choice "toggleButton" .button .toggle caption on (onChange !on)

/-- A tab for `value`, shown chosen when it is `current`. -/
def tab {Msg α : Type} [BEq α] (caption : SafeText) (value current : α) (onChange : α → Msg) : Widget Msg :=
  choice "tab" .button .tab caption (value == current) (onChange value)

/-- What holds a row of tabs, to assistive technology. -/
def tabBar {Msg : Type} : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "tabBar"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v
    access := fun _ _ => some { role := .tabList } }

/-- A line between things, across the box if `vertical` is false, else down it, in the theme's
divider color, leaving `inset` at each end. -/
def separator {Msg : Type} (vertical : Bool := false) (inset : Int := 0) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "separator"
    init := {}
    sizeReq := fun _ _ =>
      if vertical then (fixedSize (px 9).toNat, {}) else ({}, fixedSize (px 9).toNat)
    render := fun env _ v =>
      let line := if vertical then Rect.ofXYWH (v.x0 + v.width / 2) (v.y0 + inset) (px 1) (v.height - 2 * inset)
        else Rect.ofXYWH (v.x0 + inset) (v.y0 + v.height / 2) (v.width - 2 * inset) (px 1)
      Scene.inBox v [.fill line env.theme.divider 0]
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => some { role := .separator } }

end Paw.Widgets
