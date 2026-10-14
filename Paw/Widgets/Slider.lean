/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Sliders and dials

A value between two bounds, of a refinement type, so that one out of bounds cannot be made. A
slider takes the value under the pointer when pressed and while dragged: the router sends moves to
the widget pressed, so a drag goes on outside the track. A dial turns as it is dragged up or down.
Both step by the arrow keys, Page Up and Page Down, Home and End, and the wheel; assistive
technology's increment and decrement arrive as Up and Down. -/

namespace Paw.Widgets

open SizeReq

/-- A value between `lo` and `hi`. -/
abbrev Ranged (lo hi : Int) := { x : Int // lo ≤ x ∧ x ≤ hi }

/-- `x` kept between `lo` and `hi`, given that `lo ≤ hi`. -/
def Ranged.clamp {lo hi : Int} (h : lo ≤ hi) (x : Int) : Ranged lo hi := ⟨max lo (min hi x), by omega⟩

/-- What a key or the wheel does to a value of `lo`..`hi` stepping by `step`, if anything. -/
def stepKey {lo hi : Int} (h : lo ≤ hi) (step : Nat) (v : Ranged lo hi) : Event → Option (Ranged lo hi)
  | .key .right _ true | .key .up _ true => some (Ranged.clamp h (v.1 + step))
  | .key .left _ true | .key .down _ true => some (Ranged.clamp h (v.1 - step))
  | .key .pageUp _ true => some (Ranged.clamp h (v.1 + max step ((hi - lo) / 10).toNat))
  | .key .pageDown _ true => some (Ranged.clamp h (v.1 - max step ((hi - lo) / 10).toNat))
  | .key .home _ true => some (Ranged.clamp h lo)
  | .key .end_ _ true => some (Ranged.clamp h hi)
  | .wheel _ dx dy => if dy == 0 && dx == 0 then none else some (Ranged.clamp h (v.1 - (dy + dx) * step))
  | _ => none

/-- How thick a slider's track is, and how large its thumb. -/
def trackWidth : Int := px 4
def thumbSize : Int := px 16

/-- A slider from `lo` to `hi`, across or, if `vertical`, up. -/
def slider {Msg : Type} {lo hi : Int} (value : Ranged lo hi) (onChange : Ranged lo hi → Msg)
    (vertical : Bool := false) (step : Nat := 1) : Widget Msg :=
  have h : lo ≤ hi := by have := value.2; omega
  -- The track's length and where along it a value is.
  let length (v : Rect) : Int := max 1 ((if vertical then v.height else v.width) - thumbSize)
  let along (v : Rect) (x : Int) : Int := if hi == lo then 0 else (x - lo) * length v / (hi - lo)
  let at_ (v : Rect) (p : Point) : Ranged lo hi :=
    let pos := if vertical then v.y1 - thumbSize / 2 - p.y else p.x - v.x0 - thumbSize / 2
    -- The nearest value, not the one below.
    Ranged.clamp h (lo + (pos * (hi - lo) + length v / 2) / length v)
  let change (x : Ranged lo hi) : List (Req Msg) := if x.1 == value.1 then [] else [.emit (onChange x)]
  Widget.Spec.build (σ := NoState) {
    kind := "slider"
    init := {}
    sizeReq := fun _ _ =>
      if vertical then (fixedSize thumbSize.toNat, minSize (px 100).toNat) else (minSize (px 100).toNat, fixedSize thumbSize.toNat)
    render := fun env _ v =>
      let t := env.theme
      let s := env.look t.toggle
      let off := along v value.1
      let (track, filled, thumb) := if vertical then
          let x := v.x0 + (v.width - trackWidth) / 2
          (Rect.ofXYWH x (v.y0 + thumbSize / 2) trackWidth (v.height - thumbSize),
           Rect.ofXYWH x (v.y1 - thumbSize / 2 - off) trackWidth off,
           Rect.ofXYWH (v.x0 + (v.width - thumbSize) / 2) (v.y1 - thumbSize - off) thumbSize thumbSize)
        else
          let y := v.y0 + (v.height - trackWidth) / 2
          (Rect.ofXYWH (v.x0 + thumbSize / 2) y (v.width - thumbSize) trackWidth,
           Rect.ofXYWH (v.x0 + thumbSize / 2) y off trackWidth,
           Rect.ofXYWH (v.x0 + off) (v.y0 + (v.height - thumbSize) / 2) thumbSize thumbSize)
      Scene.inBox v [.fill track t.border (trackWidth / 2), .fill filled (if env.enabled then t.accent else t.muted) (trackWidth / 2),
        .fill thumb s.bg (thumbSize / 2), .stroke thumb s.border s.borderWidth (thumbSize / 2)]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st v e => match e with
      | .press p .primary => some (st, change (at_ v p))
      | .move p => if env.isPressed then some (st, change (at_ v p)) else none
      | .release .. | .click .. | .enter _ | .leave _ | .focus | .blur => some (st, [])
      | e => (stepKey h step value e).map fun x => (st, change x)
    focusable := true
    access := fun _ _ => some { role := .slider, range := some (lo, hi, value.1) } }

structure DialState where
  /-- Where a drag began, and the value then. -/
  drag : Option (Int × Int) := none
  deriving TypeName, Inhabited

/-- A dial from `lo` to `hi`, turned by dragging up or down, `size` units across. -/
def dial {Msg : Type} {lo hi : Int} (value : Ranged lo hi) (onChange : Ranged lo hi → Msg)
    (step : Nat := 1) (size : Int := px 48) : Widget Msg :=
  have h : lo ≤ hi := by have := value.2; omega
  let change (x : Ranged lo hi) : List (Req Msg) := if x.1 == value.1 then [] else [.emit (onChange x)]
  Widget.Spec.build (σ := DialState) {
    kind := "dial"
    init := {}
    sizeReq := fun _ _ => (fixedSize size.toNat, fixedSize size.toNat)
    render := fun env _ v =>
      let t := env.theme
      let s := env.look t.toggle
      let side := min v.width v.height
      let c := Rect.ofXYWH (v.x0 + (v.width - side) / 2) (v.y0 + (v.height - side) / 2) side side
      -- From 135° left of up, at the least, to 135° right of it, at the greatest.
      let frac : Float := if hi == lo then 0 else Float.ofInt (value.1 - lo) / Float.ofInt (hi - lo)
      let angle := (frac * 270 - 135) * 3.14159265358979 / 180
      let r := Float.ofInt side * 0.35
      let cx := c.x0 + side / 2
      let cy := c.y0 + side / 2
      let tip : Point := ⟨cx + (r * angle.sin).toInt64.toInt, cy - (r * angle.cos).toInt64.toInt⟩
      Scene.inBox v [.fill c s.bg (side / 2), .stroke c s.border s.borderWidth (side / 2),
        .path [⟨cx, cy⟩, tip] false none (some (if env.enabled then t.accent else t.muted, px 3))]
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun env st _ e => match e with
      | .press p .primary => some ({ drag := some (p.y, value.1) }, [])
      | .move p => match st.drag with
        | some (y0, v0) =>
          if env.isPressed then some (st, change (Ranged.clamp h (v0 + (y0 - p.y) * (hi - lo) / px 200))) else none
        | none => none
      | .release .. => some ({ drag := none }, [])
      | .click .. | .enter _ | .leave _ | .focus | .blur => some (st, [])
      | e => (stepKey h step value e).map fun x => (st, change x)
    focusable := true
    access := fun _ _ => some { role := .slider, range := some (lo, hi, value.1) } }

end Paw.Widgets
