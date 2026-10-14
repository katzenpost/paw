/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic
import Paw.Route

/-! # Dragging and dropping

Something draggable gives a value of its own type; a drop target takes values of one type, and
asks for a message when one is dropped on it. The router turns a press and a move of a few pixels
on something draggable into a drag, draws a faint copy of it under the pointer, and on release
delivers a drop to the target under it, designated only if the checks for a click pass: the input
was not synthetic, and the target had been still. A drop target lights up while something is
dragged over it. Dragging is within the window: values from other apps are pasted, not dropped. -/

namespace Paw.Widgets

/-- What holds something draggable, giving `payload` to a drop. -/
def draggable {Msg α : Type} [TypeName α] (payload : α) : Widget Msg :=
  let init : DragPayload := { payload := Dynamic.mk payload }
  Widget.Spec.build {
    kind := "draggable"
    init
    -- Each view's payload, not one kept from before.
    merge := fun _ => init
    sizeReq := fun _ _ => ({}, {})
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v }

/-- What holds a drop target, asking for `accept a` when a value `a` of its type is dropped on it;
a value of another type goes on to the targets around it. -/
def dropTarget {Msg α : Type} [TypeName α] (accept : α → Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "dropTarget"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v =>
      Scene.inBox v (if env.dragAt.any v.contains then [.stroke v env.theme.accent (px 2) (px 4)] else [])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st _ e => match e with
      | .drop _ => (env.dragged.bind (·.get? α)).map fun a => (st, [.emit (accept a)])
      | _ => none }

end Paw.Widgets
