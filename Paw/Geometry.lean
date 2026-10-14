/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # Geometry

Positions and sizes are integers in units of 1/64 of a logical pixel, so that layout is exact and
its laws are decidable and proved by `omega`. -/

namespace Paw

/-- Units per logical pixel. -/
def unitsPerPx : Int := 64

/-- `n` logical pixels in units. -/
def px (n : Int) : Int := n * unitsPerPx

structure Point where
  x : Int
  y : Int
  deriving Repr, DecidableEq, Inhabited

instance : Add Point := ⟨fun a b => ⟨a.x + b.x, a.y + b.y⟩⟩

/-- A rectangle by its corners: `(x0, y0)` is in it, `(x1, y1)` is just outside it. -/
structure Rect where
  x0 : Int
  y0 : Int
  x1 : Int
  y1 : Int
  deriving Repr, DecidableEq, Inhabited

namespace Rect

def ofXYWH (x y w h : Int) : Rect := ⟨x, y, x + w, y + h⟩

def width (r : Rect) : Int := max 0 (r.x1 - r.x0)

def height (r : Rect) : Int := max 0 (r.y1 - r.y0)

def isEmpty (r : Rect) : Bool := r.x1 ≤ r.x0 || r.y1 ≤ r.y0

/-- Not inverted. -/
def Valid (r : Rect) : Prop := r.x0 ≤ r.x1 ∧ r.y0 ≤ r.y1

instance (r : Rect) : Decidable r.Valid := by unfold Valid; infer_instance

/-- `a` lies inside `b`. -/
def Within (a b : Rect) : Prop := b.x0 ≤ a.x0 ∧ b.y0 ≤ a.y0 ∧ a.x1 ≤ b.x1 ∧ a.y1 ≤ b.y1

instance (a b : Rect) : Decidable (a.Within b) := by unfold Within; infer_instance

/-- `a` and `b` share no point. -/
def Disjoint (a b : Rect) : Prop := a.x1 ≤ b.x0 ∨ b.x1 ≤ a.x0 ∨ a.y1 ≤ b.y0 ∨ b.y1 ≤ a.y0

instance (a b : Rect) : Decidable (a.Disjoint b) := by unfold Disjoint; infer_instance

def contains (r : Rect) (p : Point) : Bool := r.x0 ≤ p.x && p.x < r.x1 && r.y0 ≤ p.y && p.y < r.y1

def inter (a b : Rect) : Rect := ⟨max a.x0 b.x0, max a.y0 b.y0, min a.x1 b.x1, min a.y1 b.y1⟩

def translate (r : Rect) (p : Point) : Rect := ⟨r.x0 + p.x, r.y0 + p.y, r.x1 + p.x, r.y1 + p.y⟩

/-- `r` less the given margins on the left, top, right and bottom, never past empty. -/
def shrink (r : Rect) (l t rt b : Int) : Rect :=
  let x0 := min (r.x0 + l) r.x1
  let y0 := min (r.y0 + t) r.y1
  ⟨x0, y0, max x0 (r.x1 - rt), max y0 (r.y1 - b)⟩

theorem within_refl (a : Rect) : a.Within a := by unfold Within; omega

theorem Within.trans {a b c : Rect} (h₁ : a.Within b) (h₂ : b.Within c) : a.Within c := by
  unfold Within at *; omega

theorem inter_within (a b : Rect) : (a.inter b).Within b := by
  simp only [Within, inter]; omega

theorem inter_within_left (a b : Rect) : (a.inter b).Within a := by
  simp only [Within, inter]; omega

theorem Disjoint.symm {a b : Rect} (h : a.Disjoint b) : b.Disjoint a := by
  unfold Disjoint at *; omega

theorem shrink_within (r : Rect) (h : r.Valid) {l t rt b : Int}
    (hl : 0 ≤ l) (ht : 0 ≤ t) (hr : 0 ≤ rt) (hb : 0 ≤ b) : (r.shrink l t rt b).Within r := by
  simp only [Valid, Within, shrink] at *; omega

theorem shrink_valid (r : Rect) (l t rt b : Int) : (r.shrink l t rt b).Valid := by
  simp only [Valid, shrink]; omega

end Rect

end Paw
