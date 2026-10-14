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
  deriving TypeName, Repr, Inhabited

/-- The scroll offset kept within what the content allows. -/
def clampOffset (off contentH viewH : Int) : Int := max 0 (min off (contentH - viewH))

/-- The child fills the content rectangle. -/
def scrollLayout : Layout where
  name := "vscroll"
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
    ({ w with fixed := w.fixed + gutter.toNat }, flexSize (h.fixed + h.flex))

def scrollWidget {Msg : Type} : Widget Msg :=
  Widget.Spec.build (σ := ScrollState) {
    kind := "scroll"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    content := fun _ st v (_, rh) =>
      let h := max v.height (rh.flex : Int)
      let off := clampOffset st.offset h v.height
      Rect.ofXYWH v.x0 (v.y0 - off) (v.width - gutter) h
    render := fun env _ v =>
      let ch := env.content.height
      if ch ≤ v.height then Scene.empty
      else
        let thumbH := max (px 16) (v.height * v.height / ch)
        let off := v.y0 - env.content.y0
        let y := v.y0 + off * (v.height - thumbH) / max 1 (ch - v.height)
        Scene.inBox v [.fill (Rect.ofXYWH (v.x1 - gutter + px 2) y (gutter - px 4) thumbH) env.theme.border (px 2)]
    render_within := fun _ _ v => by
      dsimp only
      split
      · exact Scene.empty_within v
      · exact Scene.inBox_within v _
    handle := fun env st v e =>
      let ch := env.content.height
      let by_ (d : Int) := some ({ offset := clampOffset (clampOffset st.offset ch v.height + d) ch v.height }, [])
      match e with
      | .wheel _ _ dy => by_ (dy * scrollStep)
      | .key .pageDown _ true => by_ (v.height - scrollStep)
      | .key .pageUp _ true => by_ (scrollStep - v.height)
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
