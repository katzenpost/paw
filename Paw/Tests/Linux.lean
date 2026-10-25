/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Linux
import Paw.Ui
import Paw.Tests.Util

/-! # The Linux platform's formats

Lean decodes the window events Rust encodes, Rust reads the requests Lean encodes, and text is
measured by the Rust layer's fonts. No window is opened. -/

namespace Paw.Tests.Linux

open Paw Paw.Linux Paw.Codec

def input (k : InputKind) (t : Nat) : WindowEvent := .input { kind := k, time := t }

/-- What `events::sample` in Rust encodes. -/
def sample : List WindowEvent := [
  input (.press ⟨640, -64⟩ .primary) 1,
  input (.release ⟨640, 64⟩ .secondary) 2,
  input (.move ⟨1, 2⟩) 3,
  input (.wheel ⟨0, 0⟩ (-1) 2) 4,
  input (.key (.char 'é') { ctrl := true } true) 5,
  input (.key (.f 12) {} false) 6,
  input (.key .pageDown { shift := true, alt := true, super := true } true) 7,
  input (.text "hé 🚀") 8,
  input (.paste "a\nb") 9,
  .input { kind := .leaveWindow, time := 10, synthetic := true, obscured := true },
  .resize 64000 48000,
  .close,
  .access ⟨7⟩ .focus,
  .focus false,
  .visible true,
  input (.preedit "日本" 1) 11]

def echoes (r : Request) : Bool :=
  match requestEnc r with
  | some bytes => Ffi.requestEcho (toBytes bytes) == toBytes bytes
  | none => false

def isPng (b : ByteArray) : Bool := b.size > 8 && b.data.toList.take 4 == [0x89, 0x50, 0x4E, 0x47]

def tests : TestM Unit := do
  let decoded := (list eventCodec).decodeAll (ofBytes (Ffi.sampleEvents ()))
  check "Lean decodes the events Rust encodes" (decoded.map (·.length) == some 16)
  check "and they are the events meant"
    (decoded.any fun ds => (ds.zip sample).all fun (a, b) => eventEnc a == eventEnc b)
  check "Linux desktop is not Android" !onAndroid
  check "off Android, a permission is held" (← permission "android.permission.RECORD_AUDIO")
  check "a set title request reaches Rust" (echoes (.setTitle (SafeName.filter "t")))
  check "a clipboard request" (echoes (.setClipboard (SafeText.filter "c")))
  check "a link" (echoes (.openUri "https://example.org"))
  check "a notification" (echoes (.notify (SafeName.filter "a") (SafeText.filter "b")))
  check "quit" (echoes .quit)
  check "the pointer's shape" ([Cursor.default, .pointer, .text, .resizeH, .resizeV].all (echoes ∘ .cursor))
  check "an input method on, with its caret" (echoes (.ime (some (Rect.ofXYWH 64 128 64 1280))))
  check "and off" (echoes (.ime none))
  let field : Access := { role := .textInput, name := SafeText.trusted "name", value := some (SafeText.trusted "Ada") }
  let box : Access := { role := .checkBox, checked := some true }
  let pw : Access := { role := .passwordInput, value := some (SafeText.trusted "pw") }
  let node : AccessNode :=
    { id := 2, access := field, bounds := Rect.ofXYWH 0 0 640 640, focusable := true, disabled := false, children := [] }
  check "an accessibility tree" (echoes (.access 2 [node, { node with id := 3, access := box }]))
  check "with a value in a range" (echoes (.access 2 [{ node with access := { role := .slider, range := some (-5, 5, 2) } }]))
  let secret : AccessNode := { node with access := pw }
  let sent := (requestEnc (.access 0 [secret])).getD []
  let hasPw := (List.range sent.length).any fun i => ((sent.drop i).take 2 == ([112, 119] : List UInt8))
  check "a password's value is never sent" (!sent.isEmpty && !hasPw)
  check "drawing is not a request" (requestEnc (.present Scene.empty)).isNone
  checkEq "malformed requests echo as nothing" 0 (Ffi.requestEcho ⟨#[9]⟩).size
  -- Measuring with the bundled fonts.
  let style : TextStyle := { size := px 14 }
  let (w0, h) := measure style SafeText.empty
  checkEq "empty text has no width" 0 w0
  checkEq "a line is 1.25 times the font size" (px 14 * 5 / 4) h
  let (w1, _) := measure style (SafeText.trusted "a")
  let (w2, _) := measure style (SafeText.trusted "aa")
  check "a wider text measures wider" (0 < w1 && w1 < w2)
  let (wb, _) := measure { style with bold := true } (SafeText.trusted "aa")
  check "bold is no narrower" (wb ≥ w2)
  let (w28, h28) := measure { style with size := px 28 } (SafeText.trusted "aa")
  check "a larger size measures larger" (w28 > w2 && h28 > h)
  -- Random events through the codec.
  let mut g : Rng := ⟨17⟩
  let mut ok := true
  for i in [0:300] do
    let (k, g1) := g.next 8
    let (x, g2) := g1.next 100000
    let (c, g3) := g2.next 0x10FFFF
    g := g3
    let p : Point := ⟨(x : Int) - 50000, (c : Int) - 5000⟩
    let kind : InputKind := match k with
      | 0 => .press p .middle | 1 => .release p .primary | 2 => .move p | 3 => .wheel p x (-1)
      | 4 => .key (.char (Char.ofNat c)) { shift := true } (i % 2 == 0)
      | 5 => .text (String.ofList [Char.ofNat c]) | 6 => .paste "x" | _ => .leaveWindow
    let e := input kind i
    if (eventCodec.decodeAll (eventCodec.enc e)).map eventEnc != some (eventEnc e) then ok := false
  check "random events round trip" ok
  -- Offscreen drawing.
  let scene := Scene.inBox (Rect.ofXYWH 0 0 (px 20) (px 10)) [.fill (Rect.ofXYWH 0 0 (px 20) (px 10)) Color.black 0,
    .text ⟨0, 0⟩ (SafeText.trusted "Hi") { color := Color.white }]
  check "a scene draws to PNG" (isPng (renderPng scene 20 10))
  check "at twice the scale" (isPng (renderPng scene 40 20 (scale := 2000)))
  checkEq "a malformed scene draws nothing" 0 (Ffi.renderPng ⟨#[1, 9]⟩ 10 10 1000).size
  -- The layout report the end-to-end tests read.
  let tree := ((Ui.col [Ui.label "a" "first", Ui.label "b", Ui.label "c" "third"] (spacing := 0) : Node Unit).init 1).1.resize
    { measure := fun _ _ => (px 10, px 20) } (Rect.ofXYWH 0 0 (px 100) (px 100))
  checkEq "a layout report names keyed widgets" "first 0 0 100 20\nthird 0 40 100 60" (layoutReport tree)
  -- Comparing images.
  let a := renderPng scene 20 10
  let b := renderPng (Scene.inBox (Rect.ofXYWH 0 0 (px 5) (px 5)) [.fill (Rect.ofXYWH 0 0 (px 5) (px 5)) Color.black 0]) 20 10
  checkEq "an image does not differ from itself" (some 0) ((Codec.nat.dec (ofBytes (Ffi.pngDiff a a))).map (·.1))
  check "two images differ" (((Codec.nat.dec (ofBytes (Ffi.pngDiff a b))).map (·.1)).any (· > 0))
  checkEq "images of different sizes cannot be compared" 0 (Ffi.pngDiff a (renderPng scene 10 10)).size
  checkEq "no difference outside the whole image" 0 (Ffi.pngDiffOutside a b 0 0 20 10)
  check "a difference outside a small corner" (Ffi.pngDiffOutside a b 0 0 1 1 > 0)

end Paw.Tests.Linux
