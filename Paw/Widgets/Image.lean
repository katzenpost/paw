/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic
import Paw.Image

/-! # Images and icons

An image widget shows an `Image` the app decoded, fitted to its box by `ImageFit`, which Lean
computes, and clipped to the box like anything else. An icon is drawn from paths, in the theme's
text color. Both say what they are to assistive technology with an `ImageAlt`: a description, or
that they are only decoration. -/

namespace Paw.Widgets

/-- What an image or icon is to assistive technology. -/
def _root_.Paw.ImageAlt.access : ImageAlt → Option Access
  | .text alt => some { role := .image, name := alt.toText }
  | .decorative => none

/-- `img`, fitted to the box by `fit`. -/
def image {Msg : Type} (img : Image) (alt : ImageAlt) (fit : ImageFit := .either) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "image"
    init := {}
    sizeReq := fun _ _ => (SizeReq.flexSize (px img.w).toNat, SizeReq.flexSize (px img.h).toNat)
    render := fun _ _ v => Scene.inBox v [.image (fit.place v img.w img.h) img.id 255]
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => alt.access }

/-- Icons drawn from paths. -/
inductive _root_.Paw.Icon where
  | close
  | plus
  | minus
  | check
  | chevronDown
  | chevronRight
  | warning
  deriving Repr, DecidableEq, Inhabited

/-- The icon's paths in the square in the middle of `v`, in `c`. -/
def _root_.Paw.Icon.draw (k : Icon) (v : Rect) (c : Color) : List Draw :=
  let side := min v.width v.height
  let x0 := v.x0 + (v.width - side) / 2
  let y0 := v.y0 + (v.height - side) / 2
  -- A point in sixteenths of the square.
  let p (x y : Int) : Point := ⟨x0 + side * x / 16, y0 + side * y / 16⟩
  let line (ps : List Point) : Draw := .path ps false none (some (c, max (side / 10) (px 1)))
  match k with
  | .close => [line [p 4 4, p 12 12], line [p 12 4, p 4 12]]
  | .plus => [line [p 8 3, p 8 13], line [p 3 8, p 13 8]]
  | .minus => [line [p 3 8, p 13 8]]
  | .check => [line [p 3 8, p 7 12, p 13 4]]
  | .chevronDown => [line [p 4 6, p 8 10, p 12 6]]
  | .chevronRight => [line [p 6 4, p 10 8, p 6 12]]
  | .warning =>
    [.path [p 8 1, p 15 14, p 1 14] true none (some (c, max (side / 12) (px 1))), line [p 8 6, p 8 9],
     .path [p 7 11, p 9 11, p 9 13, p 7 13] true (some c) none]

/-- An icon `size` units square, in the theme's text color. -/
def icon {Msg : Type} (k : Icon) (alt : ImageAlt) (size : Int := px 16) : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "icon"
    init := {}
    sizeReq := fun _ _ => (SizeReq.fixedSize size.toNat, SizeReq.fixedSize size.toNat)
    render := fun env _ v => Scene.inBox v (k.draw v (if env.enabled then env.theme.text else env.theme.muted))
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => alt.access }

end Paw.Widgets
