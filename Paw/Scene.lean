/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Geometry
import Paw.Text
import Paw.Codec

/-! # Scenes

What a widget draws: a list of draw items, each with the clip it is drawn under. The Rust layer
draws each item clipped to its rectangle, so a scene whose clips lie within a box draws nothing
outside it, whatever its text or shapes would otherwise cover. -/

namespace Paw

structure Color where
  r : UInt8
  g : UInt8
  b : UInt8
  a : UInt8
  deriving Repr, DecidableEq, Inhabited

namespace Color

def rgba (r g b a : UInt8) : Color := ⟨r, g, b, a⟩

def rgb (r g b : UInt8) : Color := ⟨r, g, b, 255⟩

def black : Color := rgb 0 0 0

def white : Color := rgb 255 255 255

def codec : Codec Color :=
  (Codec.pair (Codec.pair Codec.u8 Codec.u8) (Codec.pair Codec.u8 Codec.u8)).map
    (fun ((r, g), (b, a)) => ⟨r, g, b, a⟩) (fun c => ((c.r, c.g), (c.b, c.a))) (fun _ => rfl)

end Color

structure TextStyle where
  /-- The font size, in units. -/
  size : Int := px 14
  color : Color := Color.black
  bold : Bool := false
  deriving Repr, DecidableEq, Inhabited

def TextStyle.codec : Codec TextStyle :=
  (Codec.pair Codec.int (Codec.pair Color.codec Codec.bool)).map
    (fun (s, c, b) => ⟨s, c, b⟩) (fun t => (t.size, t.color, t.bold)) (fun _ => rfl)

def SafeText.codec : Codec SafeText :=
  Codec.string.refine (fun s => if h : s.toList.all Text.allowed = true then some ⟨s, h⟩ else none)
    (·.text) (by intro t; simp [t.ok])

inductive Draw where
  /-- A filled rectangle, with rounded corners of the given radius. -/
  | fill (r : Rect) (c : Color) (radius : Int)
  /-- A rectangle's outline of the given width, with rounded corners of the given radius. -/
  | stroke (r : Rect) (c : Color) (width : Int) (radius : Int)
  /-- One line of text whose line box has its top left at the point. -/
  | text (at_ : Point) (t : SafeText) (style : TextStyle)
  deriving Repr, DecidableEq, Inhabited

namespace Scene

def rectCodec : Codec Rect :=
  (Codec.pair (Codec.pair Codec.int Codec.int) (Codec.pair Codec.int Codec.int)).map
    (fun ((x0, y0), (x1, y1)) => ⟨x0, y0, x1, y1⟩) (fun r => ((r.x0, r.y0), (r.x1, r.y1)))
    (fun _ => rfl)

def pointCodec : Codec Point :=
  (Codec.pair Codec.int Codec.int).map (fun (x, y) => ⟨x, y⟩) (fun p => (p.x, p.y)) (fun _ => rfl)

end Scene

namespace Draw

open Scene (rectCodec pointCodec)

def enc : Draw → List UInt8
  | .fill r c radius => Codec.nat.enc 0 ++ rectCodec.enc r ++ Color.codec.enc c ++ Codec.int.enc radius
  | .stroke r c w radius =>
    Codec.nat.enc 1 ++ rectCodec.enc r ++ Color.codec.enc c ++ Codec.int.enc w ++
      Codec.int.enc radius
  | .text p t s => Codec.nat.enc 2 ++ pointCodec.enc p ++ SafeText.codec.enc t ++ TextStyle.codec.enc s

def dec (bs : List UInt8) : Option (Draw × List UInt8) := do
  let (tag, bs) ← Codec.nat.dec bs
  match tag with
  | 0 =>
    let (r, bs) ← rectCodec.dec bs
    let (c, bs) ← Color.codec.dec bs
    let (radius, bs) ← Codec.int.dec bs
    pure (.fill r c radius, bs)
  | 1 =>
    let (r, bs) ← rectCodec.dec bs
    let (c, bs) ← Color.codec.dec bs
    let (w, bs) ← Codec.int.dec bs
    let (radius, bs) ← Codec.int.dec bs
    pure (.stroke r c w radius, bs)
  | 2 =>
    let (p, bs) ← pointCodec.dec bs
    let (t, bs) ← SafeText.codec.dec bs
    let (s, bs) ← TextStyle.codec.dec bs
    pure (.text p t s, bs)
  | _ => none

theorem roundtrip (d : Draw) (rest : List UInt8) : dec (enc d ++ rest) = some (d, rest) := by
  cases d <;>
    simp [enc, dec, List.append_assoc, Codec.nat.roundtrip, rectCodec.roundtrip,
      pointCodec.roundtrip, Color.codec.roundtrip, Codec.int.roundtrip, SafeText.codec.roundtrip,
      TextStyle.codec.roundtrip]

def codec : Codec Draw := ⟨enc, dec, roundtrip⟩

end Draw

structure Scene where
  items : List (Rect × Draw)
  deriving Repr, DecidableEq, Inhabited

namespace Scene

def ofList (items : List (Rect × Draw)) : Scene := ⟨items⟩

def empty : Scene := ⟨[]⟩

/-- One draw item under the clip `c`. -/
def draw (c : Rect) (d : Draw) : Scene := ⟨[(c, d)]⟩

instance : Append Scene := ⟨fun a b => ⟨a.items ++ b.items⟩⟩

/-- Every item's clip lies within `v`. -/
def Within (s : Scene) (v : Rect) : Prop := ∀ i ∈ s.items, i.1.Within v

instance (s : Scene) (v : Rect) : Decidable (s.Within v) := by unfold Within; infer_instance

def clip (v : Rect) (s : Scene) : Scene := ⟨s.items.map fun (r, d) => (r.inter v, d)⟩

theorem clip_within (v : Rect) (s : Scene) : (s.clip v).Within v := by
  intro i hi
  simp only [clip, List.mem_map] at hi
  obtain ⟨⟨r, d⟩, -, rfl⟩ := hi
  exact Rect.inter_within r v

theorem empty_within (v : Rect) : Scene.empty.Within v := fun _ h => nomatch h

theorem draw_within {c v : Rect} (d : Draw) (h : c.Within v) : (Scene.draw c d).Within v := by
  intro i hi
  simp only [draw, List.mem_singleton] at hi
  exact hi ▸ h

theorem append_within {a b : Scene} {v : Rect} (ha : a.Within v) (hb : b.Within v) :
    (a ++ b).Within v := by
  intro i hi
  cases List.mem_append.mp hi with
  | inl h => exact ha i h
  | inr h => exact hb i h

theorem Within.mono {s : Scene} {v w : Rect} (h : s.Within v) (hw : v.Within w) : s.Within w :=
  fun i hi => (h i hi).trans hw

def Draw.translate (p : Point) : Draw → Draw
  | .fill r c radius => .fill (r.translate p) c radius
  | .stroke r c w radius => .stroke (r.translate p) c w radius
  | .text q t s => .text (q + p) t s

/-- The scene moved by `p`. -/
def translate (s : Scene) (p : Point) : Scene :=
  ⟨s.items.map fun (r, d) => (r.translate p, Draw.translate p d)⟩

def codec : Codec Scene :=
  (Codec.list (Codec.pair rectCodec Draw.codec)).map Scene.ofList (·.items) (fun _ => rfl)

end Scene

end Paw
