/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widget

/-! # Labels, buttons and checkboxes

Each widget draws with `Scene.inBox`, every item clipped to its box, so its law is
`Scene.inBox_within`. Controls look as the theme's style for their kind says, in the state they
are in. Text is `SafeText`: the app's own strings through `SafeText.trusted`, text
from elsewhere through `SafeText.filter`. -/

namespace Paw.Widgets

open SizeReq

/-- The space between a checkbox and its caption. -/
def captionGap : Int := px 8

def textStyle (env : Env) : TextStyle := { size := env.theme.fontSize, color := env.theme.text }

/-- A control's box drawn as `s` says: its background, then its border. -/
def frame (v : Rect) (s : StyleState) : List Draw :=
  [.fill v s.bg s.radius, .stroke v s.border s.borderWidth s.radius]

/-- Text vertically centered in `v`, starting at `x`. -/
def centeredText (env : Env) (v : Rect) (x : Int) (t : SafeText) (style : TextStyle) : Draw :=
  let (_, h) := env.measure style t
  .text ⟨x, v.y0 + (v.height - h) / 2⟩ t style

/-- One line of text, in bold if `bold`. -/
def label {Msg : Type} (t : SafeText) (bold : Bool := false) : Widget Msg :=
  let style (env : Env) : TextStyle := { textStyle env with bold }
  Widget.Spec.build (σ := NoState) {
    kind := "label"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (style env) t
      (fixedSize w.toNat, fixedSize h.toNat)
    render := fun env _ v => Scene.inBox v [centeredText env v v.x0 t (style env)]
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => some { role := .label, name := t } }

/-- Lines joined by spaces, as a screen reader reads a paragraph. -/
def joinLines (lines : List SafeText) : SafeText :=
  lines.foldl (fun acc l => if acc.text.isEmpty then l else acc ++ SafeText.trusted " " ++ l) SafeText.empty

/-- Lines of text, one under another. -/
def paragraph {Msg : Type} (lines : List SafeText) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "paragraph"
    init := {}
    sizeReq := fun env _ =>
      let sizes := lines.map (env.measure (textStyle env))
      (fixedSize (sizes.foldl (fun m (w, _) => max m w.toNat) 0),
       fixedSize (sizes.foldl (fun s (_, h) => s + h.toNat) 0))
    render := fun env _ v =>
      let style := textStyle env
      let (_, items) := lines.foldl (fun (y, ds) t =>
        let (_, h) := env.measure style t
        (y + h, ds ++ [Draw.text ⟨v.x0, y⟩ t style])) (v.y0, [])
      Scene.inBox v items
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => some { role := .label, name := joinLines lines } }

/-- A button that emits `onClick` when clicked, or when Enter or Space is pressed on it; if
`designated`, only when that input designated it, as `Req.choose`. -/
def button {Msg : Type} (caption : SafeText) (onClick : Msg) (designated : Bool := false) : Widget Msg :=
  let act : Req Msg := if designated then .choose onClick else .emit onClick
  Widget.Spec.build (σ := NoState) {
    kind := "button"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      let (padX, padY) := env.theme.button.padding
      (fixedSize (w + 2 * padX).toNat, fixedSize (h + 2 * padY).toNat)
    render := fun env _ v =>
      let s := env.look env.theme.button
      let style := { textStyle env with color := s.fg }
      let (w, _) := env.measure style caption
      Scene.inBox v (frame v s ++ [centeredText env v (v.x0 + (v.width - w) / 2) caption style])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. => some (st, [act])
      | .key .enter _ true | .key (.char ' ') _ true => some (st, [act])
      | .enter _ | .leave _ | .press .. | .release .. | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    cursor := fun env _ => (env.look env.theme.button).cursor
    access := fun _ _ => some { role := .button, name := caption } }

/-- A checkbox showing `value`, which emits `onChange` with the other value when toggled. -/
def checkbox {Msg : Type} (caption : SafeText) (value : Bool) (onChange : Bool → Msg) :
    Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "checkbox"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      (fixedSize (h + captionGap + w).toNat, fixedSize h.toNat)
    render := fun env _ v =>
      let t := env.theme
      let s := env.look t.checkbox
      -- The box is as tall as a line of the caption, centered in whatever height it is given.
      let side := min (env.measure (textStyle env) caption).2 v.height
      let boxR := Rect.ofXYWH v.x0 (v.y0 + (v.height - side) / 2) side side
      let mark := boxR.shrink (side / 4) (side / 4) (side / 4) (side / 4)
      -- The caption is on the window, not in the box: the window's text, or muted when disabled.
      let caption' := { textStyle env with color := if env.enabled then t.text else t.muted }
      Scene.inBox v (frame boxR s ++
        (if value then [.fill mark (if env.enabled then t.accent else s.fg) (px 2)] else []) ++
        [centeredText env v (v.x0 + side + captionGap) caption caption'])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. | .key (.char ' ') _ true => some (st, [.emit (onChange !value)])
      | .enter _ | .leave _ | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    cursor := fun env _ => (env.look env.theme.checkbox).cursor
    access := fun _ _ => some { role := .checkBox, name := caption, checked := some value } }

/-- The theme's window background over its box: what holds a subtree with a theme of its own. -/
def backdrop {Msg : Type} : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "backdrop"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v => Scene.inBox v [.fill v env.theme.background 0]
    render_within := fun _ _ v => Scene.inBox_within v _ }

/-- Empty space that takes the width left over, and no height: for pushing things apart in a
row. -/
def spacer {Msg : Type} : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "spacer"
    init := {}
    sizeReq := fun _ _ => (filler, {})
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v }

end Paw.Widgets
