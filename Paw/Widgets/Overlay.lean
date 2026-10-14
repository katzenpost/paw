/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic
import Paw.Route

/-! # Overlays

The widgets that hold an overlay's content: a popup's panel, and a modal's dimming of the window
with a dialog panel on it. A popup is dismissed by Escape or by a press outside it, which the router
turns into `Event.dismiss`; a modal by Escape or Enter, so that the key someone typing might press
next takes the safe choice. -/

namespace Paw.Widgets

/-- What holds a popup's content: a panel. It emits `onDismiss` on Escape or a press outside it. -/
def popupWidget {Msg : Type} (onDismiss : Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "popup"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v =>
      Scene.inBox v [.fill v env.theme.surface (px 4), .stroke v env.theme.border (px 1) (px 4)]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .dismiss | .key .escape _ true => some (st, [.emit onDismiss])
      | _ => none }

/-- What holds a modal dialog: a dimming of everything beneath, keeping the token `m` the dialog was
first opened with. It emits `onDismiss` on Escape or Enter. -/
def modalWidget {Msg : Type} (m : Modal) (onDismiss : Msg) : Widget Msg :=
  Widget.Spec.build {
    kind := "modal"
    init := m
    sizeReq := fun _ _ => ({}, {})
    render := fun _ _ v => Scene.inBox v [.fill v (Color.rgba 0 0 0 96) 0]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .dismiss | .key .escape _ true | .key .enter _ true => some (st, [.emit onDismiss])
      | _ => none }

/-- A dialog's panel, named `title` to assistive technology. -/
def dialogPanel {Msg : Type} (title : SafeName) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "dialog"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v =>
      Scene.inBox v [.fill v env.theme.surface (px 6), .stroke v env.theme.border (px 1) (px 6)]
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => some { role := .dialog, name := title.toText } }

end Paw.Widgets
