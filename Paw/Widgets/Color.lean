/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Colors and shadows

A swatch shows a color, and as a button opens a color popup. A shadow is drawn from a few
translucent rounded fills, within the box of the widget that draws it, which keeps the room for it
around its child. -/

namespace Paw.Widgets

open SizeReq

/-- Two hexadecimal digits for `b`. -/
def hex2 (b : UInt8) : String :=
  let d (n : Nat) : Char := "0123456789ABCDEF".toList.getD n '0'
  String.ofList [d (b.toNat / 16), d (b.toNat % 16)]

/-- `c` as `#RRGGBB`, with `AA` after it if it is not opaque. -/
def Color.hex (c : Color) : String :=
  "#" ++ hex2 c.r ++ hex2 c.g ++ hex2 c.b ++ (if c.a == 255 then "" else hex2 c.a)

/-- A square of `c`, framed; as a button, if `onClick` is given, which asks for it when clicked. -/
def swatch {Msg : Type} (c : Color) (onClick : Option Msg := none) (size : Int := px 28) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "swatch"
    init := {}
    sizeReq := fun _ _ => (fixedSize size.toNat, fixedSize size.toNat)
    render := fun env _ box =>
      let s := env.look env.theme.button
      -- Square, in the middle of whatever box it is given.
      let side := min box.width box.height
      let v := Rect.ofXYWH (box.x0 + (box.width - side) / 2) (box.y0 + (box.height - side) / 2) side side
      let inner := v.shrink (px 3) (px 3) (px 3) (px 3)
      -- A translucent color is shown over a mark that shows through it.
      let behind := if c.a < 255 then [Draw.fill (Rect.ofXYWH inner.x0 inner.y0 (inner.width / 2) (inner.height / 2)) env.theme.text 0,
          .fill (Rect.ofXYWH (inner.x0 + inner.width / 2) (inner.y0 + inner.height / 2) (inner.width / 2) (inner.height / 2)) env.theme.text 0]
        else []
      Scene.inBox box ([.fill v s.bg (px 4)] ++ behind ++ [.fill inner c (px 2), .stroke v s.border s.borderWidth (px 4)])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match onClick, e with
      | some m, .click .. | some m, .key .enter _ true | some m, .key (.char ' ') _ true => some (st, [.emit m])
      | some _, .enter _ | some _, .leave _ | some _, .press .. | some _, .release .. | some _, .focus | some _, .blur =>
        some (st, [])
      | _, _ => none
    focusable := onClick.isSome
    access := fun _ _ => some { role := .colorWell, value := some (SafeText.trusted (Color.hex c)) } }

/-- What draws a shadow `depth` units deep around its child, which is laid out inside it clear of
the shadow, and `radius` round. -/
def shadow {Msg : Type} (depth radius : Int) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "shadow"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun _ _ v =>
      -- Faint fills from the edge of the box inwards, which stack, so the shadow darkens towards
      -- the middle; it falls a little below what it shadows.
      let layers := (List.range 4).map fun (k : Nat) =>
        let inset := depth * (k : Int) / 4
        Draw.fill ((v.shrink inset (inset + depth / 3) inset (max 0 (inset - depth / 3))).inter v)
          (Color.rgba 0 0 0 9) (radius + depth - inset)
      Scene.inBox v layers
    render_within := fun _ _ v => Scene.inBox_within v _ }

end Paw.Widgets
