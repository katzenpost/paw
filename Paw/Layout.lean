/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Geometry

/-! # Layout

A widget asks for space on each axis with a `SizeReq`, as in monomer: a `fixed` size it needs, a
`flex` size it would like and gives up first when space is short, and an `extra` weight for space
left over, scaled by `factor`. A `Layout` assigns its children rectangles and carries the proofs
that there is one per child and that each lies within the box it was given. A `SeparatedLayout`
also proves that its children do not overlap, which reserved regions rely on.

Stacks and grids are `Axial`: they only decide a size per child along one axis, and the proofs come
from placing those sizes one after another. Unlike monomer, a stack never places a child outside
its box: children that do not fit are cut at its edge. -/

namespace Paw

structure SizeReq where
  fixed : Nat := 0
  flex : Nat := 0
  extra : Nat := 0
  factor : Nat := 1
  deriving Repr, DecidableEq, Inhabited

namespace SizeReq

/-- Exactly `s`. -/
def fixedSize (s : Nat) : SizeReq := { fixed := s }

/-- `s` if there is room, less if not, and a share of what is left over. -/
def flexSize (s : Nat) (factor : Nat := 1) : SizeReq := { flex := s, extra := s, factor }

/-- At least `s`, and a share of what is left over. -/
def minSize (s : Nat) (factor : Nat := 1) : SizeReq := { fixed := s, extra := s, factor }

/-- At most `s`. -/
def maxSize (s : Nat) (factor : Nat := 1) : SizeReq := { flex := s, factor }

/-- At least `a`, and up to `b` if there is room. -/
def rangeSize (a b : Nat) (factor : Nat := 1) : SizeReq := { fixed := a, flex := b - a, factor }

/-- Nothing needed, but all that is left over. -/
def filler : SizeReq := { extra := px 1 |>.toNat }

/-- Two requests side by side. -/
def mergeSum (a b : SizeReq) : SizeReq :=
  { fixed := a.fixed + b.fixed, flex := a.flex + b.flex, extra := a.extra + b.extra,
    factor := max a.factor b.factor }

/-- Two requests on top of each other, as monomer merges them. -/
def mergeMax (a b : SizeReq) : SizeReq :=
  let fixed := max a.fixed b.fixed
  let flex :=
    if (a.fixed > 0) == (b.fixed > 0) then max a.flex b.flex
    else if a.fixed > 0 && a.flex > b.flex then a.flex
    else if b.fixed > 0 && b.flex > a.flex then b.flex
    else max a.flex b.flex - fixed
  { fixed, flex, extra := max a.extra b.extra, factor := max a.factor b.factor }

def mergeAll (f : SizeReq → SizeReq → SizeReq) : List SizeReq → SizeReq
  | [] => {}
  | x :: xs => xs.foldl f x

end SizeReq

open SizeReq

/-- A child as a layout sees it. -/
structure Item where
  w : SizeReq
  h : SizeReq
  visible : Bool := true
  deriving Repr, DecidableEq, Inhabited

structure Layout where
  assign : Rect → List Item → List Rect
  assign_length : ∀ v items, (assign v items).length = items.length
  assign_within : ∀ v items, ∀ r ∈ assign v items, r.Within v
  /-- What the container asks for, given its children. -/
  sizeReq : List Item → SizeReq × SizeReq

structure SeparatedLayout extends Layout where
  assign_disjoint : ∀ v items, (assign v items).Pairwise Rect.Disjoint

inductive Axis where
  | horizontal
  | vertical
  deriving Repr, DecidableEq, Inhabited

/-- Spans one after another from `o`: each `(gap, size)` leaves `gap`, then takes `size`. -/
def place (o : Int) : List (Nat × Nat) → List (Int × Int)
  | [] => []
  | (g, s) :: rest => (o + g, o + g + s) :: place (o + g + s) rest

theorem place_length (o : Int) (xs : List (Nat × Nat)) : (place o xs).length = xs.length := by
  induction xs generalizing o with
  | nil => rfl
  | cons x xs ih => simp [place, ih]

theorem place_start (o : Int) (xs : List (Nat × Nat)) : ∀ p ∈ place o xs, o ≤ p.1 := by
  induction xs generalizing o with
  | nil => intro p h; cases h
  | cons x xs ih =>
    intro p h
    simp only [place, List.mem_cons] at h
    rcases h with rfl | h
    · simp only; omega
    · have := ih _ p h; omega

theorem place_pairwise (o : Int) (xs : List (Nat × Nat)) :
    (place o xs).Pairwise (fun a b => a.2 ≤ b.1) := by
  induction xs generalizing o with
  | nil => exact List.Pairwise.nil
  | cons x xs ih =>
    simp only [place, List.pairwise_cons]
    exact ⟨fun p h => place_start _ xs p h, ih _⟩

namespace Axis

/-- The part of `v` a span of this axis covers. -/
def span (ax : Axis) (v : Rect) (p : Int × Int) : Rect :=
  match ax with
  | .horizontal => (⟨p.1, v.y0, p.2, v.y1⟩ : Rect).inter v
  | .vertical => (⟨v.x0, p.1, v.x1, p.2⟩ : Rect).inter v

theorem span_within (ax : Axis) (v : Rect) (p : Int × Int) : (ax.span v p).Within v := by
  cases ax <;> exact Rect.inter_within _ _

theorem span_disjoint (ax : Axis) (v : Rect) {p q : Int × Int} (h : p.2 ≤ q.1) :
    (ax.span v p).Disjoint (ax.span v q) := by
  cases ax <;> simp only [span, Rect.inter, Rect.Disjoint] <;> omega

def start (ax : Axis) (v : Rect) : Int := match ax with | .horizontal => v.x0 | .vertical => v.y0

def length (ax : Axis) (v : Rect) : Nat := match ax with
  | .horizontal => v.width.toNat
  | .vertical => v.height.toNat

def main (ax : Axis) (i : Item) : SizeReq := match ax with | .horizontal => i.w | .vertical => i.h

def cross (ax : Axis) (i : Item) : SizeReq := match ax with | .horizontal => i.h | .vertical => i.w

/-- A request for the container, given its requests along and across this axis. -/
def pair (ax : Axis) (along across : SizeReq) : SizeReq × SizeReq := match ax with
  | .horizontal => (along, across)
  | .vertical => (across, along)

end Axis

/-- The gap before each child: `spacing` before a visible child that follows a visible one. -/
def gaps (spacing : Nat) : Bool → List Item → List Nat
  | _, [] => []
  | seen, i :: rest =>
    (if i.visible && seen then spacing else 0) :: gaps spacing (seen || i.visible) rest

theorem gaps_length (s : Nat) (seen : Bool) (items : List Item) :
    (gaps s seen items).length = items.length := by
  induction items generalizing seen with
  | nil => rfl
  | cons i rest ih => simp [gaps, ih]

/-- A layout along one axis: it decides a size per child, from the length available after
spacing, and the children are placed one after another. -/
structure Axial where
  axis : Axis
  spacing : Nat
  sizes : Nat → List Item → List Nat
  sizes_length : ∀ m items, (sizes m items).length = items.length
  sizeReq : List Item → SizeReq × SizeReq

namespace Axial

def visibleCount (items : List Item) : Nat := (items.filter (·.visible)).length

def totalSpacing (a : Axial) (items : List Item) : Nat := a.spacing * (visibleCount items - 1)

def assign (a : Axial) (v : Rect) (items : List Item) : List Rect :=
  let sizes := a.sizes (a.axis.length v - a.totalSpacing items) items
  (place (a.axis.start v) ((gaps a.spacing false items).zip sizes)).map (a.axis.span v)

theorem assign_length (a : Axial) (v : Rect) (items : List Item) :
    (a.assign v items).length = items.length := by
  simp [assign, place_length, gaps_length, a.sizes_length]

theorem assign_within (a : Axial) (v : Rect) (items : List Item) :
    ∀ r ∈ a.assign v items, r.Within v := by
  intro r h
  simp only [assign, List.mem_map] at h
  obtain ⟨p, -, rfl⟩ := h
  exact a.axis.span_within v p

theorem assign_disjoint (a : Axial) (v : Rect) (items : List Item) :
    (a.assign v items).Pairwise Rect.Disjoint := by
  simp only [assign]
  exact List.Pairwise.map _ (fun _ _ h => a.axis.span_disjoint v h) (place_pairwise _ _)

def toSeparated (a : Axial) : SeparatedLayout where
  assign := a.assign
  assign_length := a.assign_length
  assign_within := a.assign_within
  sizeReq := a.sizeReq
  assign_disjoint := a.assign_disjoint

end Axial

/-- Ceiling of `a / b`, and 0 when `b` is. -/
def ceilDiv (a b : Nat) : Nat := if b = 0 then 0 else (a + b - 1) / b

/-- Flexible sizes `(flex, factor)` less `shortfall` in all, taken in proportion to
`flex × factor`. A size cannot give up more than it has; what it cannot give, the others give in
the next round, so the shortfall is covered unless only rigid sizes (factor 0) are left. -/
def shrinkFlex (shortfall : Nat) (items : List (Nat × Nat)) : (fuel : Nat) → List Nat
  | 0 => items.map (·.1)
  | fuel + 1 =>
    let fac := items.foldl (fun acc (f, k) => acc + f * k) 0
    if shortfall = 0 || fac = 0 then items.map (·.1)
    else
      let cut := fun ((f, k) : Nat × Nat) => min f (ceilDiv (shortfall * f * k) fac)
      let removed := items.foldl (fun acc i => acc + cut i) 0
      shrinkFlex (shortfall - removed) (items.map fun (f, k) => (f - cut (f, k), k)) fuel

theorem shrinkFlex_length (s : Nat) (items : List (Nat × Nat)) (fuel : Nat) :
    (shrinkFlex s items fuel).length = items.length := by
  induction fuel generalizing s items with
  | zero => simp [shrinkFlex]
  | succ n ih => simp only [shrinkFlex]; split <;> simp [ih]

/-- monomer's stack sizes in integers: fixed sizes first, flexible sizes shrunk in proportion to
`flex × factor` when space is short, and space left over shared in proportion to
`extra × factor`. -/
def stackSizes (main : Nat) (reqs : List (SizeReq × Bool)) : List Nat :=
  let vis := (reqs.filter (·.2)).map (·.1)
  let sum (f : SizeReq → Nat) := vis.foldl (fun acc r => acc + f r) 0
  let fixed := sum (·.fixed)
  let flex := sum (·.flex)
  let extraFac := sum fun r => r.extra * r.factor
  let avail := main - fixed
  let flexAvail := min flex avail
  let extraAvail := avail - flexAvail
  let flexes := shrinkFlex (flex - flexAvail)
    (reqs.map fun (r, visible) => (if visible then r.flex else 0, r.factor)) (reqs.length + 1)
  (reqs.zip flexes).map fun ((r, visible), f) =>
    if !visible then 0
    else
      let share := if extraFac = 0 then 0 else extraAvail * r.extra * r.factor / extraFac
      r.fixed + f + share

theorem stackSizes_length (m : Nat) (reqs : List (SizeReq × Bool)) :
    (stackSizes m reqs).length = reqs.length := by
  simp [stackSizes, shrinkFlex_length]

/-- A grid's sizes: the length shared evenly between its visible children. -/
def gridSizes (main : Nat) (items : List Item) : List Nat :=
  let n := Axial.visibleCount items
  items.map fun i => if i.visible && n > 0 then main / n else 0

def stack (axis : Axis) (spacing : Int := 0) : SeparatedLayout :=
  Axial.toSeparated {
    axis
    spacing := spacing.toNat
    sizes := fun m items => stackSizes m (items.map fun i => (axis.main i, i.visible))
    sizes_length := fun m items => by simp [stackSizes_length]
    sizeReq := fun items =>
      let vis := items.filter (·.visible)
      let gapsReq := fixedSize (spacing.toNat * (vis.length - 1))
      axis.pair (mergeSum (mergeAll mergeSum (vis.map axis.main)) gapsReq)
        (mergeAll mergeMax (vis.map axis.cross)) }

def grid (axis : Axis) (spacing : Int := 0) : SeparatedLayout :=
  Axial.toSeparated {
    axis
    spacing := spacing.toNat
    sizes := gridSizes
    sizes_length := fun m items => by simp [gridSizes]
    sizeReq := fun items =>
      let vis := items.filter (·.visible)
      let n := vis.length
      let cell := mergeAll mergeMax (vis.map axis.main)
      axis.pair
        { cell with fixed := cell.fixed * n + spacing.toNat * (n - 1), flex := cell.flex * n,
                    extra := cell.extra * n }
        (mergeAll mergeMax (vis.map axis.cross)) }

/-- Children side by side, left to right. -/
def hstack (spacing : Int := 0) : SeparatedLayout := stack .horizontal spacing

/-- Children one above the other, top to bottom. -/
def vstack (spacing : Int := 0) : SeparatedLayout := stack .vertical spacing

/-- Children side by side in equal widths. -/
def hgrid (spacing : Int := 0) : SeparatedLayout := grid .horizontal spacing

/-- Children one above the other in equal heights. -/
def vgrid (spacing : Int := 0) : SeparatedLayout := grid .vertical spacing

/-- Children on top of each other, each given the whole box. Children overlap, so this is not a
`SeparatedLayout`. -/
def zstack : Layout where
  assign := fun v items => items.map fun _ => v
  assign_length := by simp
  assign_within := by
    intro v items r h
    simp only [List.mem_map] at h
    obtain ⟨_, -, rfl⟩ := h
    exact Rect.within_refl v
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    (mergeAll mergeMax (vis.map (·.w)), mergeAll mergeMax (vis.map (·.h)))

inductive AlignH where
  | left | center | right
  deriving Repr, DecidableEq, Inhabited

inductive AlignV where
  | top | middle | bottom
  deriving Repr, DecidableEq, Inhabited

structure BoxCfg where
  alignH : AlignH := .center
  alignV : AlignV := .middle
  /-- Give the child the whole box rather than the size it asks for. -/
  expand : Bool := false
  deriving Repr, DecidableEq, Inhabited

/-- Where a child of length `want` goes in `[lo, hi)`. -/
def alignSpan (lo hi : Int) (want : Nat) (at_ : Nat) : Int × Int :=
  let room := max 0 (hi - lo)
  let len := min (want : Int) room
  let off := match at_ with | 0 => 0 | 1 => (room - len) / 2 | _ => room - len
  (lo + off, lo + off + len)

/-- Each child placed in the box by its size request and the alignment. -/
def box (cfg : BoxCfg) : Layout where
  assign := fun v items => items.map fun i =>
    if cfg.expand then v
    else
      let h := alignSpan v.x0 v.x1 (i.w.fixed + i.w.flex)
        (match cfg.alignH with | .left => 0 | .center => 1 | .right => 2)
      let vv := alignSpan v.y0 v.y1 (i.h.fixed + i.h.flex)
        (match cfg.alignV with | .top => 0 | .middle => 1 | .bottom => 2)
      (⟨h.1, vv.1, h.2, vv.2⟩ : Rect).inter v
  assign_length := by simp
  assign_within := by
    intro v items r h
    simp only [List.mem_map] at h
    obtain ⟨_, -, rfl⟩ := h
    split
    · exact Rect.within_refl v
    · exact Rect.inter_within _ _
  sizeReq := fun items =>
    let vis := items.filter (·.visible)
    (mergeAll mergeMax (vis.map (·.w)), mergeAll mergeMax (vis.map (·.h)))

end Paw
