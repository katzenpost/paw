/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Ffi
import Paw.Codec
import Paw.Geometry
import Paw.Text

/-! # Images

An image is decoded from PNG or JPEG bytes the app has, by the Rust layer, which refuses one
larger than 8192 pixels a side or 64 MiB of pixels, reading its size from the header before
allocating anything. Widgets cannot read files or fetch links: an app gets the bytes with a task
and hands the image to a widget, which only shows it.

The pixels stay in the Rust layer, where they are drawn, held by a handle Lean frees when nothing
refers to the image any more; so the platform keeps an image exactly as long as the app does.
A scene names an image by its id, which the Rust layer gives from a counter: two images never
share one, so no content can be made to draw as another image, as content crafted to collide a
hash could. `Image`'s constructor is private, so an id comes only from the Rust layer. -/

namespace Paw

inductive ImageError where
  /-- Not a PNG or a JPEG. -/
  | format
  /-- Larger than the limits, whatever the file's size. -/
  | tooLarge
  /-- A PNG or JPEG that does not decode. -/
  | corrupt
  deriving Repr, DecidableEq, Inhabited

structure Image where
  private mk ::
  /-- Width in pixels. -/
  w : Nat
  /-- Height in pixels. -/
  h : Nat
  id : Nat
  handle : Ffi.ImageHandle

instance : BEq Image := ⟨fun a b => a.id == b.id⟩

instance : Repr Image := ⟨fun i _ => s!"<image {i.id}: {i.w}×{i.h}>"⟩

namespace Image

/-- An image from the Rust layer's answer. -/
private def ofResult (r : ByteArray × Ffi.ImageHandle) : Except ImageError Image :=
  match Codec.nat.dec (Codec.ofBytes r.1) with
  | some (0, bs) =>
    match (Codec.pair Codec.nat (Codec.pair Codec.nat Codec.nat)).decodeAll bs with
    | some (w, h, id) => .ok ⟨w, h, id, r.2⟩
    | none => .error .corrupt
  | some (1, _) => .error .format
  | some (2, _) => .error .tooLarge
  | _ => .error .corrupt

/-- A PNG or JPEG, decoded under the limits. -/
def decode (bytes : ByteArray) : IO (Except ImageError Image) :=
  return ofResult (← Ffi.imageDecode bytes)

/-- A `w` × `h` image from straight RGBA pixels, four bytes each, row by row. -/
def ofRgba (w h : Nat) (rgba : ByteArray) : IO (Except ImageError Image) :=
  if w ≥ 2 ^ 32 || h ≥ 2 ^ 32 then return .error .tooLarge
  else return ofResult (← Ffi.imageOfRgba w.toUInt32 h.toUInt32 rgba)

end Image

/-- How an image is fitted to its box. -/
inductive ImageFit where
  /-- At its own size, a pixel to a logical pixel. -/
  | none
  /-- Stretched to the box. -/
  | fill
  /-- As wide as the box, keeping its shape. -/
  | width
  /-- As tall as the box, keeping its shape. -/
  | height
  /-- As large as fits in the box, keeping its shape. -/
  | either
  deriving Repr, DecidableEq, Inhabited

/-- Where an image of `w` × `h` pixels is drawn for a box `v`, centered: it may be larger than the
box, which clips it. -/
def ImageFit.place (fit : ImageFit) (v : Rect) (w h : Nat) : Rect :=
  let (w, h) : Int × Int := (max w 1, max h 1)
  let (dw, dh) : Int × Int := match fit with
    | .none => (px w, px h)
    | .fill => (v.width, v.height)
    | .width => (v.width, v.width * h / w)
    | .height => (v.height * w / h, v.height)
    | .either => if v.width * h ≤ v.height * w then (v.width, v.width * h / w) else (v.height * w / h, v.height)
  Rect.ofXYWH (v.x0 + (v.width - dw) / 2) (v.y0 + (v.height - dh) / 2) dw dh

/-- What an image is to assistive technology: described by `alt`, or only decoration, which a
screen reader passes over. An image must be one or the other. -/
inductive ImageAlt where
  | text (alt : SafeName)
  | decorative
  deriving Repr, DecidableEq, Inhabited

end Paw
