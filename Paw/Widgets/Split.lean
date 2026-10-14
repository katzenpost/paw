/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Splits

Two children side by side, or one above the other, with a divider between them that the user drags
to share the room differently. How the room is shared is the app's, in thousandths for the first
child: dragging the divider, or moving it by the arrow keys while it has focus, asks for a new
share. The pointer takes the resize shape over the divider. -/

namespace Paw.Widgets

/-- How thick a split's divider is. -/
def dividerWidth : Int := px 6

/-- The room for the first child, out of `total`, for a share of `ratio` thousandths. -/
def firstLength (total : Int) (ratio : Nat) : Int :=
  let room := max 0 (total - dividerWidth)
  room * (min ratio 1000 : Nat) / 1000

/-- The divider's rectangle in `v`. -/
def dividerRect (vertical : Bool) (ratio : Nat) (v : Rect) : Rect :=
  if vertical then Rect.ofXYWH v.x0 (v.y0 + firstLength v.height ratio) v.width dividerWidth
  else Rect.ofXYWH (v.x0 + firstLength v.width ratio) v.y0 dividerWidth v.height

/-- The first child before the divider, the second after it; any more get nothing. Each is cut to
the box. -/
def splitLayout (vertical : Bool) (ratio : Nat) : Layout where
  name := if vertical then "vsplit" else "hsplit"
  assign := fun v items =>
    let d := dividerRect vertical ratio v
    let first : Rect := if vertical then ⟨v.x0, v.y0, v.x1, d.y0⟩ else ⟨v.x0, v.y0, d.x0, v.y1⟩
    let second : Rect := if vertical then ⟨v.x0, d.y1, v.x1, v.y1⟩ else ⟨d.x1, v.y0, v.x1, v.y1⟩
    items.zipIdx.map fun (_, k) => (if k == 0 then first else if k == 1 then second else ⟨v.x0, v.y0, v.x0, v.y0⟩).inter v
  assign_length := by simp
  assign_within := by
    intro v items r h
    simp only [List.mem_map] at h
    obtain ⟨_, -, rfl⟩ := h
    exact Rect.inter_within _ _
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    let along (i : Item) := if vertical then i.h else i.w
    let across (i : Item) := if vertical then i.w else i.h
    let main := (vis.map along).foldl SizeReq.mergeSum { fixed := dividerWidth.toNat }
    let cross := SizeReq.mergeAll SizeReq.mergeMax (vis.map across)
    if vertical then (cross, main) else (main, cross)

structure SplitState where
  dragging : Bool := false
  deriving TypeName, Inhabited

/-- What holds a split: its divider, which is dragged, or moved by keys, to ask for a new share. -/
def splitWidget {Msg : Type} (vertical : Bool) (ratio : Nat) (onResize : Nat → Msg) : Widget Msg :=
  let shareAt (v : Rect) (p : Point) : Nat :=
    let (pos, total) := if vertical then (p.y - v.y0, v.height) else (p.x - v.x0, v.width)
    let room := max 1 (total - dividerWidth)
    (max 0 (min 1000 ((pos - dividerWidth / 2) * 1000 / room))).toNat
  let ask (r : Nat) : List (Req Msg) := if r == ratio then [] else [.emit (onResize r)]
  Widget.Spec.build (σ := SplitState) {
    kind := if vertical then "vsplit" else "hsplit"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v =>
      let d := dividerRect vertical ratio v
      let t := env.theme
      let c := if env.isFocused then t.accent else if env.isHovered || env.isPressed then t.text else t.border
      let grip := if vertical then Rect.ofXYWH (d.x0 + d.width / 2 - px 12) (d.y0 + d.height / 2 - px 1) (px 24) (px 2)
        else Rect.ofXYWH (d.x0 + d.width / 2 - px 1) (d.y0 + d.height / 2 - px 12) (px 2) (px 24)
      Scene.inBox v [.fill grip c (px 1)]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v e => match e with
      | .press p .primary => if (dividerRect vertical ratio v).contains p then some ({ dragging := true }, []) else none
      | .move p => if st.dragging && env.isPressed then some (st, ask (shareAt v p)) else none
      | .release .. => some ({ dragging := false }, [])
      | .key .left _ true | .key .up _ true => some (st, ask (ratio - 50))
      | .key .right _ true | .key .down _ true => some (st, ask (min 1000 (ratio + 50)))
      | .enter _ | .leave _ | .focus | .blur | .click .. => some (st, [])
      | _ => none
    focusable := true
    cursor := fun _ _ => if vertical then .resizeV else .resizeH
    access := fun _ _ => some { role := .separator, range := some (0, 1000, ratio) } }

end Paw.Widgets
