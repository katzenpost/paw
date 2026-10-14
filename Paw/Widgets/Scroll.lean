/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Scrolls and key bindings

A vertical scroll lays its child out in a content rectangle as tall as the child asks, shifted up
by the scroll offset, and keeps a gutter on its right for its bar, which the child's box never
covers. The tree clips what the child draws to the scroll's box. The wheel, and Page Up and Page
Down from a focused child, bubble up to it. -/

namespace Paw.Widgets

open SizeReq

def gutter : Int := px 8

/-- A line of scrolling, in units. -/
def scrollStep : Int := px 40

structure ScrollState where
  offset : Int := 0
  /-- How far the content is scrolled left, when it scrolls across. -/
  offsetX : Int := 0
  deriving TypeName, Repr, Inhabited

/-- The scroll offset kept within what the content allows. -/
def clampOffset (off contentH viewH : Int) : Int := max 0 (min off (contentH - viewH))

/-- Which ways a scroll scrolls. -/
inductive ScrollAxes where
  | vertical
  | horizontal
  | both
  deriving Repr, DecidableEq, Inhabited

def ScrollAxes.across (a : ScrollAxes) : Bool := a != .vertical
def ScrollAxes.down (a : ScrollAxes) : Bool := a != .horizontal

/-- The child fills the content rectangle. Along a way the scroll scrolls, the scroll asks for what
the child asks, as room it may have but need not; across the other it asks what the child asks,
and the gutter. -/
def scrollLayoutFor (axes : ScrollAxes) : Layout where
  name := match axes with | .vertical => "vscroll" | .horizontal => "hscroll" | .both => "scroll"
  assign := fun v items => items.map fun _ => v
  assign_length := by simp
  assign_within := by
    intro v items r h
    simp only [List.mem_map] at h
    obtain ⟨_, -, rfl⟩ := h
    exact Rect.within_refl v
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    let h := mergeAll mergeMax (vis.map (·.h))
    let w := mergeAll mergeMax (vis.map (·.w))
    let pad (r : SizeReq) (on : Bool) : SizeReq := if on then { r with fixed := r.fixed + gutter.toNat } else r
    (if axes.across then flexSize (w.fixed + w.flex) else pad w axes.down,
     if axes.down then flexSize (h.fixed + h.flex) else pad h axes.across)

/-- A scroll along `axes`: its content as large as the child asks along them, shifted by the
offsets, clear of the gutters its bars are drawn in. -/
def scrollWidgetFor {Msg : Type} (axes : ScrollAxes) : Widget Msg :=
  -- The view, less the gutters for the bars.
  let inner (v : Rect) : Rect :=
    Rect.ofXYWH v.x0 v.y0 (v.width - if axes.down then gutter else 0) (v.height - if axes.across then gutter else 0)
  Widget.Spec.build (σ := ScrollState) {
    kind := match axes with | .vertical => "scroll" | .horizontal => "hscroll" | .both => "scroll2"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    content := fun _ st v (rw, rh) =>
      let i := inner v
      let w := if axes.across then max i.width (rw.flex : Int) else i.width
      let h := if axes.down then max i.height (rh.flex : Int) else i.height
      Rect.ofXYWH (v.x0 - clampOffset st.offsetX w i.width) (v.y0 - clampOffset st.offset h i.height) w h
    render := fun env _ v =>
      let i := inner v
      let c := env.content
      let bar (len content off : Int) : Int × Int :=
        let thumb := max (px 16) (len * len / max 1 content)
        (off * (len - thumb) / max 1 (content - len), thumb)
      let vbar := if axes.down && c.height > i.height then
          let (y, thumbH) := bar i.height c.height (v.y0 - c.y0)
          [Draw.fill (Rect.ofXYWH (v.x1 - gutter + px 2) (v.y0 + y) (gutter - px 4) thumbH) env.theme.border (px 2)]
        else []
      let hbar := if axes.across && c.width > i.width then
          let (x, thumbW) := bar i.width c.width (v.x0 - c.x0)
          [Draw.fill (Rect.ofXYWH (v.x0 + x) (v.y1 - gutter + px 2) thumbW (gutter - px 4)) env.theme.border (px 2)]
        else []
      Scene.inBox v (vbar ++ hbar)
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v e =>
      let i := inner v
      let c := env.content
      let byY (d : Int) := { st with offset := clampOffset (clampOffset st.offset c.height i.height + d) c.height i.height }
      let byX (d : Int) := { st with offsetX := clampOffset (clampOffset st.offsetX c.width i.width + d) c.width i.width }
      match e with
      | .wheel _ dx dy =>
        -- A wheel turned for the way a scroll does not scroll moves it the way it does.
        let st := if axes.down then byY (dy * scrollStep) else byX (dy * scrollStep)
        let st := if axes.across && dx != 0 then
            { st with offsetX := clampOffset (clampOffset st.offsetX c.width i.width + dx * scrollStep) c.width i.width }
          else st
        some (st, [])
      | .key .pageDown _ true => if axes.down then some (byY (i.height - scrollStep), []) else none
      | .key .pageUp _ true => if axes.down then some (byY (scrollStep - i.height), []) else none
      | _ => none
    access := fun _ _ => some { role := .scrollView } }

/-- A key with modifiers. -/
structure KeyCombo where
  key : Key
  ctrl : Bool := false
  shift : Bool := false
  alt : Bool := false
  deriving Repr, DecidableEq

def KeyCombo.matches (c : KeyCombo) (k : Key) (m : Mods) : Bool :=
  c.key == k && c.ctrl == m.ctrl && c.shift == m.shift && c.alt == m.alt

/-- Emits a binding's message when its keys are pressed in the child and the child does not
handle them. -/
def keystrokeWidget {Msg : Type} (bindings : List (KeyCombo × Msg)) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "keystroke"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v
    handle := fun _ st _ e => match e with
      | .key k m true => (bindings.find? (·.1.matches k m)).map fun (_, msg) => (st, [.emit msg])
      | _ => none }

/-- A box less padding on every side. -/
def padLayout (p : Int) : Layout where
  name := "pad"
  assign := fun v items => items.map fun _ => (v.shrink p p p p).inter v
  assign_length := by simp
  assign_within := by
    intro v items r h
    simp only [List.mem_map] at h
    obtain ⟨_, -, rfl⟩ := h
    exact Rect.inter_within _ _
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    let add (r : SizeReq) := { r with fixed := r.fixed + 2 * p.toNat }
    (add (mergeAll mergeMax (vis.map (·.w))), add (mergeAll mergeMax (vis.map (·.h))))

/-- The child, at a fixed width or height where given, whatever it asks for. -/
def sizeLayout (w h : Option Nat) : Layout where
  name := "size"
  assign := fun v items => items.map fun _ => v
  assign_length := by simp
  assign_within := by
    intro v items r hr
    simp only [List.mem_map] at hr
    obtain ⟨_, -, rfl⟩ := hr
    exact Rect.within_refl v
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    ((w.map fixedSize).getD (mergeAll mergeMax (vis.map (·.w))),
     (h.map fixedSize).getD (mergeAll mergeMax (vis.map (·.h))))

end Paw.Widgets
