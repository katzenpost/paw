/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Links

A link draws its caption underlined in the theme's link color, and asks for `onOpen` when clicked
or when Enter is pressed on it. Opening it is the app's: an `Effect.openLink` of the link, for
this widget's key, which needs the user's designation. The caption may be anything; where the link
really goes is shown beside it, in a tooltip Paw draws, on hover and focus (`Ui.externalLink`). -/

namespace Paw.Widgets

open SizeReq

/-- A link's caption, asking for `onOpen` when activated. -/
def link {Msg : Type} (caption : SafeText) (destination : SafeText) (onOpen : Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "link"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      (fixedSize w.toNat, fixedSize h.toNat)
    render := fun env _ v =>
      let t := env.theme
      let st := { textStyle env with color := if env.enabled then t.link else t.muted }
      let (w, h) := env.measure st caption
      let y := v.y0 + (v.height - h) / 2
      let underline := Rect.ofXYWH v.x0 (y + h - px 2) w (if env.isHovered || env.isFocused then px 2 else px 1)
      let ring := if env.isFocused then [Draw.stroke v (t.textField.current { focused := true }).border (px 2) (px 2)] else []
      Scene.inBox v ([.text ⟨v.x0, y⟩ caption st, .fill underline st.color 0] ++ ring)
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. | .key .enter _ true => some (st, [.emit onOpen])
      | .enter _ | .leave _ | .press .. | .release .. | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    cursor := fun _ _ => .pointer
    access := fun _ _ => some { role := .link, name := caption, value := some destination } }

end Paw.Widgets
