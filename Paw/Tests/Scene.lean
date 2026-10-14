/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Scene
import Paw.Tests.Util

namespace Paw.Tests.Scene

open Paw

def r (x y w h : Int) : Rect := Rect.ofXYWH (px x) (px y) (px w) (px h)

def red : Color := Color.rgb 255 0 0

def sample : Scene :=
  Scene.ofList [
    (r 0 0 100 20, .fill (r 0 0 100 20) red 0),
    (r 0 0 100 20, .stroke (r 0 0 100 20) (Color.rgba 0 0 0 128) (px 1) (px 4)),
    (r 2 2 50 16, .text ⟨px 2, px 2⟩ (SafeText.filter "hi\x1b") { size := px 14, color := Color.black })]

def tests : TestM Unit := do
  checkEq "items" 3 sample.items.length
  checkEq "empty" 0 Scene.empty.items.length
  checkEq "append" 6 (sample ++ sample).items.length
  checkEq "draw keeps its clip" [r 1 1 2 2] ((Scene.draw (r 1 1 2 2) (.fill (r 0 0 9 9) red 0)).items.map (·.1))
  check "a scene within its box" (decide (sample.Within (r 0 0 100 20)))
  check "not within a smaller box" (!decide (sample.Within (r 0 0 10 10)))
  let clipped := sample.clip (r 0 0 10 10)
  check "clipping puts it within" (decide (clipped.Within (r 0 0 10 10)))
  checkEq "clipping intersects each clip" (r 2 2 8 8) (clipped.items.getLast!.1)
  checkEq "clipping keeps the draws" (sample.items.map (·.2)) (clipped.items.map (·.2))
  checkEq "translate moves clips and draws"
    [(r 1 1 2 2, .fill (r 1 1 2 2) red 0)]
    ((Scene.draw (r 0 0 2 2) (.fill (r 0 0 2 2) red 0)).translate ⟨px 1, px 1⟩).items
  checkEq "translate moves text"
    [(r 1 1 2 2, Draw.text ⟨px 1, px 1⟩ (SafeText.trusted "a") {})]
    ((Scene.draw (r 0 0 2 2) (.text ⟨0, 0⟩ (SafeText.trusted "a") {})).translate ⟨px 1, px 1⟩).items
  checkEq "translate moves strokes"
    [(r 1 1 2 2, Draw.stroke (r 1 1 2 2) red 1 0)]
    ((Scene.draw (r 0 0 2 2) (.stroke (r 0 0 2 2) red 1 0)).translate ⟨px 1, px 1⟩).items
  -- The byte format.
  checkEq "a color is four bytes" [1, 2, 3, 4] (Color.codec.enc ⟨1, 2, 3, 4⟩)
  checkEq "a rect is four zigzag ints" [0, 2, 4, 6] (Scene.rectCodec.enc ⟨0, 1, 2, 3⟩)
  checkEq "a fill" ([0] ++ Scene.rectCodec.enc (r 0 0 1 1) ++ [255, 0, 0, 255, 0])
    (Draw.codec.enc (.fill (r 0 0 1 1) red 0))
  checkEq "scene round trip" (some sample) (Scene.codec.decodeAll (Scene.codec.enc sample))
  checkEq "an unknown draw tag" none (Draw.codec.decodeAll [9])
  checkEq "text with a forbidden character is refused"
    none (SafeText.codec.decodeAll (Codec.string.enc "a\x1b"))
  checkEq "text round trip" (some (SafeText.filter "ok")) (SafeText.codec.decodeAll (SafeText.codec.enc (SafeText.filter "ok")))
  checkEq "text style round trip" (some ({ size := 5, color := red, bold := true } : TextStyle))
    (TextStyle.codec.decodeAll (TextStyle.codec.enc { size := 5, color := red, bold := true }))
  checkEq "color constructors" (Color.rgba 1 2 3 255) (Color.rgb 1 2 3)
  checkEq "white" (Color.rgb 255 255 255) Color.white

end Paw.Tests.Scene
