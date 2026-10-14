/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widget

/-! # Labels, buttons and checkboxes

Each widget draws with `Scene.inBox`, every item clipped to its box, so its law is
`Scene.inBox_within`. Text is `SafeText`: the app's own strings through `SafeText.trusted`, text
from elsewhere through `SafeText.filter`. -/

namespace Paw.Widgets

open SizeReq

/-- Horizontal and vertical padding inside buttons and fields. -/
def padX : Int := px 8
def padY : Int := px 4

def textStyle (env : Env) : TextStyle := { size := env.theme.fontSize, color := env.theme.text }

/-- A color `k`/16 of the way to black. -/
def Color.darken (c : Color) (k : Nat) : Color :=
  let f (x : UInt8) := UInt8.ofNat (x.toNat * (16 - min k 16) / 16)
  ⟨f c.r, f c.g, f c.b, c.a⟩

/-- Text vertically centered in `v`, starting at `x`. -/
def centeredText (env : Env) (v : Rect) (x : Int) (t : SafeText) (style : TextStyle) : Draw :=
  let (_, h) := env.measure style t
  .text ⟨x, v.y0 + (v.height - h) / 2⟩ t style

/-- One line of text. -/
def label {Msg : Type} (t : SafeText) (style : Option TextStyle := none) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "label"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (style.getD (textStyle env)) t
      (fixedSize w.toNat, fixedSize h.toNat)
    render := fun env _ v =>
      Scene.inBox v [centeredText env v v.x0 t (style.getD (textStyle env))]
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

/-- A button that emits `onClick` when clicked, or when Enter or Space is pressed on it. -/
def button {Msg : Type} (caption : SafeText) (onClick : Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "button"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      (fixedSize (w + 2 * padX).toNat, fixedSize (h + 2 * padY).toNat)
    render := fun env _ v =>
      let t := env.theme
      let bg := if env.isPressed then Color.darken t.surface 3
        else if env.isHovered then Color.darken t.surface 1 else t.surface
      let (border, width) := if env.isFocused then (t.accent, px 2) else (t.border, px 1)
      let (w, _) := env.measure (textStyle env) caption
      Scene.inBox v [.fill v bg (px 4), .stroke v border width (px 4),
        centeredText env v (v.x0 + (v.width - w) / 2) caption (textStyle env)]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. => some (st, [.emit onClick])
      | .key .enter _ true | .key (.char ' ') _ true => some (st, [.emit onClick])
      | .enter _ | .leave _ | .press .. | .release .. | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    access := fun _ _ => some { role := .button, name := caption } }

/-- A checkbox showing `value`, which emits `onChange` with the other value when toggled. -/
def checkbox {Msg : Type} (caption : SafeText) (value : Bool) (onChange : Bool → Msg) :
    Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "checkbox"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      (fixedSize (h + padX + w).toNat, fixedSize h.toNat)
    render := fun env _ v =>
      let t := env.theme
      let side := v.height
      let boxR := Rect.ofXYWH v.x0 v.y0 side side
      let mark := boxR.shrink (side / 4) (side / 4) (side / 4) (side / 4)
      let (border, width) := if env.isFocused then (t.accent, px 2) else (t.border, px 1)
      Scene.inBox v ([.fill boxR t.surface (px 3), .stroke boxR border width (px 3)] ++
        (if value then [.fill mark t.accent (px 2)] else []) ++
        [centeredText env v (v.x0 + side + padX) caption (textStyle env)])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. | .key (.char ' ') _ true => some (st, [.emit (onChange !value)])
      | .enter _ | .leave _ | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    access := fun _ _ => some { role := .checkBox, name := caption, checked := some value } }

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
