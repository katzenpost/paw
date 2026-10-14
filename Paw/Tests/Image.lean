/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Ui
import Paw.Linux
import Paw.Tests.Util

/-! # Images

Decoding under limits, the fixtures in `tests/fixtures`, how long the Rust layer keeps an image,
fitting, and what an image is to assistive technology. -/

namespace Paw.Tests.Image

open Paw

def fixture (name : String) : IO ByteArray := IO.FS.readBinFile ("tests/fixtures" / name)

def decoded (name : String) : IO (Except ImageError Image) := do Image.decode (← fixture name)

def size : Except ImageError Image → Option (Nat × Nat)
  | .ok i => some (i.w, i.h)
  | .error _ => none

def err : Except ImageError Image → Option ImageError
  | .ok _ => none
  | .error e => some e

def tests : TestM Unit := do
  -- Decoding.
  checkEq "a PNG decodes" (some (64, 48)) (size (← decoded "photo.png"))
  checkEq "a JPEG decodes" (some (64, 48)) (size (← decoded "photo.jpg"))
  checkEq "a truncated PNG is corrupt" (some .corrupt) (err (← decoded "truncated.png"))
  checkEq "a header claiming 100000 × 100000 is refused before decoding" (some .tooLarge)
    (err (← decoded "huge-header.png"))
  checkEq "a 35 KB PNG of 6000 × 6000 pixels is refused" (some .tooLarge) (err (← decoded "bomb.png"))
  checkEq "anything else is not a format Paw reads" (some .format) (err (← decoded "garbage.bin"))
  checkEq "nor is nothing" (some .format) (err (← Image.decode ByteArray.empty))
  checkEq "pixels of the right size make an image" (some (2, 1))
    (size (← Image.ofRgba 2 1 ⟨#[255, 0, 0, 255, 0, 0, 255, 255]⟩))
  checkEq "pixels of the wrong size do not" (some .corrupt) (err (← Image.ofRgba 2 2 ⟨#[0, 0, 0, 0]⟩))
  checkEq "nor do pixels past the limits" (some .tooLarge) (err (← Image.ofRgba 9000 1 ByteArray.empty))
  checkEq "nor a size past 32 bits" (some .tooLarge) (err (← Image.ofRgba (2 ^ 32) 1 ByteArray.empty))
  -- Ids and how long an image is kept.
  let bytes ← fixture "photo.png"
  let a ← Image.decode bytes
  let b ← Image.decode bytes
  match a, b with
  | .ok a, .ok b =>
    check "the same bytes twice are two images" (a.id != b.id)
    check "an image equals itself" (a == a)
  | _, _ => check "the fixture decodes" false
  let before ← Ffi.imageCount
  for _ in [0:5] do
    discard <| Image.decode bytes
  checkEq "an image Lean no longer holds is not kept" before (← Ffi.imageCount)
  let held ← (List.range 3).mapM fun _ => Image.decode bytes
  checkEq "one Lean holds is" (before + 3) (← Ffi.imageCount)
  checkEq "three" 3 held.length
  -- Fitting into a 100 × 50 box.
  let v := Rect.ofXYWH 0 0 (px 100) (px 50)
  checkEq "none: its own size, centered" (Rect.ofXYWH (px 18) (px 1) (px 64) (px 48)) (ImageFit.none.place v 64 48)
  checkEq "fill: the box" v (ImageFit.fill.place v 64 48)
  checkEq "width: as wide as the box" (Rect.ofXYWH 0 (-800) (px 100) (px 75)) (ImageFit.width.place v 64 48)
  checkEq "height: as tall" (Rect.ofXYWH 1067 0 4266 (px 50)) (ImageFit.height.place v 64 48)
  checkEq "either: as large as fits" (ImageFit.height.place v 64 48) (ImageFit.either.place v 64 48)
  checkEq "either, in a tall box, by width" (ImageFit.width.place (Rect.ofXYWH 0 0 (px 50) (px 100)) 64 48)
    (ImageFit.either.place (Rect.ofXYWH 0 0 (px 50) (px 100)) 64 48)
  check "an empty image does not divide by zero" ((ImageFit.either.place v 0 0).width ≥ 0)
  -- A widget: the image drawn by id, clipped to its box, described or decorative.
  match ← decoded "photo.png" with
  | .ok img =>
    let env : Env := Env.mock
    let tree (alt : ImageAlt) : Node Unit :=
      ((Ui.image img alt .width).init 1).1.resize env v
    let drawn := (tree .decorative).render env
    checkEq "the image is drawn by its id, where its fit puts it"
      [(v, Draw.image (ImageFit.width.place v 64 48) img.id 255)] drawn.items
    check "clipped to its box" (decide (drawn.Within v))
    let named := (tree (.text (SafeName.filter "A yellow sun"))).accessTree env
    check "described, it is an image to assistive technology"
      (named.any fun n => n.access.role == .image && n.access.name.text == "A yellow sun")
    checkEq "decorative, it is left out" 1 ((tree .decorative).accessTree env).length
    check "a fade fades it" (match (Scene.ofList drawn.items).withAlpha 128 with
      | ⟨[(_, .image _ _ a)]⟩ => a == 128 | _ => false)
  | .error _ => check "the fixture decodes" false
  -- Icons stay in their box.
  let icons : Node Unit := Ui.row ([Icon.close, .plus, .minus, .check, .chevronDown, .chevronRight, .warning].map
    (Ui.icon · (size := px 16)))
  let t := (icons.init 1).1.resize Env.mock (Rect.ofXYWH 0 0 (px 200) (px 20))
  let s := t.render Env.mock
  checkEq "seven icons, drawn as paths" 7 (t.children.length)
  check "every icon point lies in its icon's box" (t.children.all fun c =>
    (c.render Env.mock).items.all fun (_, d) => match d with
      | .path ps .. => ps.all fun p => c.viewport.x0 ≤ p.x && p.x ≤ c.viewport.x1 && c.viewport.y0 ≤ p.y && p.y ≤ c.viewport.y1
      | _ => true)
  check "and the row is within its box" (decide (s.Within t.viewport))
  checkEq "a decorative icon is not told" 1 (t.accessTree Env.mock).length

end Paw.Tests.Image
