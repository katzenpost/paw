/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Scroll

/-! # Lists to choose from

A select list shows items in rows, one chosen, in a box that scrolls. Its rows are clicked; the
list itself takes focus, and Up, Down, Home, End, Page Up and Page Down choose another, scrolling
to keep it in view. A dropdown is a button showing the chosen item, over a select list in a popup;
whether the popup is open is the app's, as everything the view shows is. -/

namespace Paw.Widgets

open SizeReq

/-- A row of a select list, chosen or not, asking for `onPick` when clicked. -/
def listItem {Msg : Type} (caption : SafeText) (chosen : Bool) (onPick : List Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "listItem"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      (fixedSize (w + 2 * env.theme.toggle.padding.1).toNat, fixedSize (h + 2 * env.theme.toggle.padding.2).toNat)
    render := fun env _ v =>
      let t := env.theme
      let s := if chosen then t.toggleOn.basic else if env.isHovered then t.toggle.current { hovered := true } else t.toggle.basic
      Scene.inBox v ([.fill v s.bg 0] ++
        [centeredText env v (v.x0 + t.toggle.padding.1) caption { textStyle env with color := s.fg }])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. => some (st, onPick.map .emit)
      | .enter _ | .leave _ | .press .. | .release .. => some (st, [])
      | _ => none
    access := fun _ _ => some { role := .listItem, name := caption, checked := some chosen } }

/-- A row of a select list built from any node, chosen or not, asking for `onPick` when clicked
anywhere in it: chosen, it is drawn on the theme's selection color, hovered on the hover color,
and otherwise on nothing, so that a list on a panel shows the panel. `name` is what assistive
technology reads for it. -/
def listRow {Msg : Type} (name : SafeText) (chosen : Bool) (onPick : List Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "listRow"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v =>
      let t := env.theme
      if chosen then Scene.inBox v [.fill v t.selection (px 4)]
      else if env.isHovered then Scene.inBox v [.fill v (t.toggle.current { hovered := true }).bg (px 4)]
      else Scene.empty
    render_within := fun env _ v => by
      split
      · exact Scene.inBox_within v _
      · split
        · exact Scene.inBox_within v _
        · exact Scene.empty_within v
    handle := fun _ st _ e => match e with
      | .click .. => some (st, onPick.map .emit)
      | .enter _ | .leave _ | .press .. | .release .. => some (st, [])
      | _ => none
    access := fun _ _ => some { role := .listItem, name, checked := some chosen } }

/-- A row's content, inset as a list item's caption is: eight pixels at the sides, four above and
below, so that a row of one line of text is a select list's row height. -/
def listRowLayout : Layout where
  name := "listRow"
  assign := fun v items => items.map fun _ => (v.shrink (px 8) (px 4) (px 8) (px 4)).inter v
  assign_length := by simp
  assign_within := by
    intro v items r h
    simp only [List.mem_map] at h
    obtain ⟨_, -, rfl⟩ := h
    exact Rect.inter_within _ _
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    let add (r : SizeReq) (p : Int) := { r with fixed := r.fixed + 2 * p.toNat }
    (add (SizeReq.mergeAll SizeReq.mergeMax (vis.map (·.w))) (px 8),
     add (SizeReq.mergeAll SizeReq.mergeMax (vis.map (·.h))) (px 4))

/-- The height of a row of a select list. -/
def rowHeight (env : Env) : Int :=
  (env.measure (textStyle env) (SafeText.trusted "M")).2 + 2 * env.theme.toggle.padding.2

/-- Rows one under another, as a vertical stack lays them out; but the box asks to be only as tall
as the first `rows` of them, and its frame. -/
def listLayout (rows : Nat) : Layout :=
  { (vstack 0).toLayout with
    name := "selectList"
    sizeReq := fun items =>
      let shown := (items.filter (·.visible)).take rows
      ({ (mergeAll mergeMax (items.map (·.w))) with fixed := (mergeAll mergeMax (items.map (·.w))).fixed + (gutter + px 2).toNat },
       fixedSize ((shown.map fun i => i.h.fixed + i.h.flex).sum + (px 2).toNat)) }

/-- What holds a select list's rows: a box that scrolls them, and chooses by keys. There are
`count` rows, `chosen` is the index of the one chosen, and `pick i` asks for the `i`th. Unless
`framed`, the box is drawn only while it has focus, so that a list in a sidebar sits on the
sidebar. -/
def selectListBox {Msg : Type} (count : Nat) (chosen : Option Nat) (pick : Nat → List Msg)
    (framed : Bool := true) : Widget Msg :=
  Widget.Spec.build (σ := ScrollState) {
    kind := "selectList"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    content := fun env st v _ =>
      let inner := v.shrink (px 1) (px 1) (px 1) (px 1)
      let h := max inner.height ((count : Int) * rowHeight env)
      Rect.ofXYWH inner.x0 (inner.y0 - clampOffset st.offset h inner.height) (inner.width - gutter) h
    render := fun env _ v =>
      let t := env.theme
      let s := env.look t.toggle
      let ch := env.content.height
      let inner := v.shrink (px 1) (px 1) (px 1) (px 1)
      let bar := if ch ≤ inner.height then []
        else
          let thumbH := max (px 16) (inner.height * inner.height / ch)
          let y := inner.y0 + (inner.y0 - env.content.y0) * (inner.height - thumbH) / max 1 (ch - inner.height)
          [Draw.fill (Rect.ofXYWH (inner.x1 - gutter + px 2) y (gutter - px 4) thumbH) t.border (px 2)]
      let box := if framed then [.fill v s.bg (px 3), .stroke v s.border s.borderWidth (px 3)]
        else if env.isFocused then [.stroke v s.border s.borderWidth (px 3)] else []
      Scene.inBox v (box ++ bar)
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v e =>
      let rh := rowHeight env
      let viewH := v.height - px 2
      let page := max 1 (viewH / max rh 1).toNat
      let ch := env.content.height
      -- The index chosen by a key, and the offset that shows it.
      let go (i : Nat) : Option (ScrollState × List (Req Msg)) :=
        if count == 0 then some (st, []) else
        let i := min i (count - 1)
        let top := (i : Int) * rh
        let off := if top < st.offset then top else if top + rh > st.offset + viewH then top + rh - viewH else st.offset
        some ({ offset := off }, if some i == chosen then [] else (pick i).map .emit)
      let cur := chosen.getD 0
      match e with
      | .key .down _ true => go (if chosen.isNone then 0 else cur + 1)
      | .key .up _ true => go (cur - 1)
      | .key .home _ true => go 0
      | .key .end_ _ true => go (count - 1)
      | .key .pageDown m true => if m.ctrl then none else go (cur + page)
      | .key .pageUp m true => if m.ctrl then none else go (cur - page)
      | .wheel _ _ dy => some ({ offset := clampOffset (st.offset + dy * scrollStep) ch viewH }, [])
      | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    access := fun _ _ => some { role := .list } }

/-- A dropdown's button: the chosen item's caption and a chevron. Space, Enter and Down open or
close it; Up and Down while it is open choose the item before or after. -/
def dropdownButton {Msg : Type} (caption : SafeText) (isOpen : Bool) (onOpen : Bool → Msg)
    (onStep : Bool → List Msg) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "dropdown"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      let (padX, padY) := env.theme.button.padding
      (minSize (w + 2 * padX + px 20).toNat, fixedSize (h + 2 * padY).toNat)
    render := fun env _ v =>
      let s := env.look env.theme.button
      let st := { textStyle env with color := s.fg }
      let side := min (px 12) v.height
      let chevron := Rect.ofXYWH (v.x1 - env.theme.button.padding.1 - side) (v.y0 + (v.height - side) / 2) side side
      let k := side / 4
      Scene.inBox v (frame v s ++ [centeredText env v (v.x0 + env.theme.button.padding.1) caption st,
        .path [⟨chevron.x0, chevron.y0 + k⟩, ⟨chevron.x0 + side / 2, chevron.y1 - k⟩, ⟨chevron.x1, chevron.y0 + k⟩]
          false none (some (s.fg, px 2))])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. | .key (.char ' ') _ true | .key .enter _ true => some (st, [.emit (onOpen !isOpen)])
      | .key .down _ true => some (st, if isOpen then (onStep true).map .emit else [.emit (onOpen true)])
      | .key .up _ true => some (st, if isOpen then (onStep false).map .emit else [])
      | .enter _ | .leave _ | .press .. | .release .. | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    cursor := fun env _ => (env.look env.theme.button).cursor
    access := fun _ _ => some { role := .comboBox, value := some caption } }

end Paw.Widgets
