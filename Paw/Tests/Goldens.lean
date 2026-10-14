/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Linux
import Paw.Tests.Text

/-! # Golden images

Scenes drawn offscreen by the Rust layer with the bundled fonts, so the pixels are the same on
every machine, and compared with the approved images in `tests/goldens/`. A mismatch writes the
image drawn and a picture of the difference to `tests/goldens/actual/`. With `--update`, the
images drawn become the approved ones, for a person to look at before committing.

Also, every text in the security guidelines' attack corpus is drawn between two neighbours, and no
pixel outside its own cell may differ from the same row drawn with no text. -/

namespace Paw.Tests.Goldens

open Paw

def goldenDir : System.FilePath := "tests/goldens"

abbrev GApp := _root_.Gallery.app
abbrev GMsg := _root_.Gallery.Msg

/-- The scene the runtime would draw. -/
def sceneOf {caps : List Cap} {app : App caps} (rt : Runtime app) : Scene :=
  match rt.present with
  | .request (.present s) => s
  | _ => Scene.empty

def at_ {caps : List Cap} {app : App caps} (rt : Runtime app) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def step (rt : Runtime GApp) (k : InputKind) (t : Nat) : Runtime GApp :=
  (rt.step (.input { kind := k, time := t }) t).1

def click (rt : Runtime GApp) (k : String) (t : Nat) : Runtime GApp :=
  let p := at_ rt k
  step (step rt (.press p .primary) t) (.release p .primary) (t + 50)

/-- The gallery with reduced motion, so that what it draws does not depend on when. -/
def gallery : Runtime GApp :=
  (Paw.Runtime.start GApp (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Linux.measure (motion := false)).1

/-- The gallery switched to the dark theme. -/
def galleryDark : Runtime GApp := click gallery "dark" 1000

/-- The gallery's rows half way through fading in. -/
def galleryFading : Runtime GApp :=
  let rt := (Paw.Runtime.start GApp (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Linux.measure).1
  ((rt.advance 16).1.advance 141).1

/-- The gallery with the pointer resting on + for a second, showing its tooltip. -/
def galleryTip : Runtime GApp := (step gallery (.move (at_ gallery "inc")) 1000).advance 2000 |>.1

/-- The gallery after a session: a name, a password, the box checked, an item added, the scroll
moved, and the name selected in its focused field. -/
def galleryUsed : Runtime GApp := Id.run do
  let mut rt := gallery
  rt := click rt "name" 1000
  rt := step rt (.text "Ada Lovelace") 1600
  rt := click rt "pass" 2000
  rt := step rt (.text "secret") 2600
  rt := click rt "agree" 3000
  rt := click rt "draft" 4000
  rt := step rt (.text "plums") 4600
  rt := click rt "add" 5000
  rt := step rt (.wheel (at_ rt "scroll") 0 2) 5500
  rt := click rt "name" 6000
  rt := step rt (.key (.char 'a') { ctrl := true } true) 6600
  return rt

/-- The gallery with its menu open. -/
def galleryMenu : Runtime GApp := click gallery "more" 1000

/-- The gallery asking to clear its list. -/
def galleryConfirm : Runtime GApp := click galleryMenu "clear" 2000

/-- A fill of `c`, to stand beside text. -/
def swatch (c : Color) : Widget Unit := Widget.Spec.build (σ := NoState) {
  kind := "swatch"
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (px 10).toNat, SizeReq.fixedSize (px 10).toNat)
  render := fun _ _ v => Scene.inBox v [.fill v c 0]
  render_within := fun _ _ v => Scene.inBox_within v _ }

def env : Env := { measure := Linux.measure }

/-- A tree laid out in a `w` × `h` box, drawn on the theme's background. -/
def draw (n : Node Unit) (w h : Nat) (env : Env := env) : Scene :=
  let box := Rect.ofXYWH 0 0 (px w) (px h)
  let t := ((n.init 1).1).resize env box
  Scene.inBox box [.fill box env.theme.background 0] ++ t.render env

def oneButton : Node Unit := Ui.pad (px 8) (Ui.button "Press me" ())

/-- The button's id in `oneButton`, after the padding container. -/
def buttonId : WidgetId := ⟨2⟩

/-- Name, scene, width, height, and scale in thousandths. -/
def goldens : List (String × Scene × Nat × Nat × Nat) := [
  ("gallery", sceneOf gallery, 640, 560, 1000),
  ("gallery-used", sceneOf galleryUsed, 640, 560, 1000),
  ("gallery-hidpi", sceneOf gallery, 1280, 1120, 2000),
  ("popup-open", sceneOf galleryMenu, 640, 560, 1000),
  ("confirm", sceneOf galleryConfirm, 640, 560, 1000),
  ("tooltip", sceneOf galleryTip, 640, 560, 1000),
  ("gallery-dark", sceneOf galleryDark, 640, 560, 1000),
  ("gallery-fading", sceneOf galleryFading, 640, 560, 1000),
  ("button", draw oneButton 140 50, 140, 50, 1000),
  ("button-hovered", draw oneButton 140 50 { env with hovered := some buttonId }, 140, 50, 1000),
  ("button-pressed", draw oneButton 140 50 { env with hovered := some buttonId, pressed := some buttonId },
    140, 50, 1000),
  ("button-focused", draw oneButton 140 50 { env with focused := some buttonId }, 140, 50, 1000),
  ("button-disabled", draw (Ui.pad (px 8) (Ui.enabled false (Ui.button "Press me" ()))) 140 50, 140, 50, 1000),
  ("paragraph-wrapped", draw (Ui.pad (px 8) (Ui.col [
      Ui.paragraph "Paw breaks a paragraph into lines that fit its box, at spaces, and cuts a word too long for any line, such as Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch, by its characters.",
      Ui.label "A label that is cut short with an ellipsis when it does not fit" (overflow := .ellipsis),
      Ui.label "A label of at most two lines, wrapped, and cut short with an ellipsis on the second when there is still more" (overflow := .ellipsis) (maxLines := 2)])) 260 260,
    260, 260, 1000),
  ("corpus", draw (Ui.col (Text.corpus.map fun (_, p) => Ui.text (SafeText.filter p))) 420 420, 420, 420, 1000)]

/-- One corpus text in the middle of three equal cells, between two swatches. -/
def corpusRow (payload : String) : Node Unit :=
  Node.container hgrid.toLayout [Node.leaf (swatch (Color.rgb 200 30 30)),
    Ui.text (SafeText.filter payload), Node.leaf (swatch (Color.rgb 30 30 200))]

/-- Holds `a` until it is called: what a scene draws by id must be alive until it is drawn. -/
@[noinline] def keepAlive {α : Type} (a : α) : IO Unit := do
  let r ← IO.mkRef (some a)
  r.set none

/-- The fixture photo in a 100 × 60 box in each way of fitting it, framed, then every icon. -/
def imageFits (img : Image) : Node Unit :=
  let framed (fit : ImageFit) : Node Unit :=
    Ui.width (px 100) (Ui.height (px 60) (Ui.image img .decorative fit))
  Ui.pad (px 8) <| Ui.col [
    Ui.row ([ImageFit.none, .fill, .width, .height, .either].map framed) (px 8),
    Ui.row ([Icon.close, .plus, .minus, .check, .chevronDown, .chevronRight, .warning].map
      (Ui.icon · (size := px 24))) (px 8)]

def check (update : Bool) (name : String) (scene : Scene) (w h scale : Nat) : IO Bool := do
  let png := Linux.renderPng scene w h scale
  let path := goldenDir / s!"{name}.png"
  if update then
    IO.FS.writeBinFile path png
    IO.println s!"updated {path}"
    return true
  if !(← path.pathExists) then
    IO.println s!"FAIL {name}: no approved image; run make goldens-update and look at it"
    return false
  let approved ← IO.FS.readBinFile path
  if approved == png then
    IO.println s!"ok   {name}"
    return true
  let actual := goldenDir / "actual"
  IO.FS.createDirAll actual
  IO.FS.writeBinFile (actual / s!"{name}.png") png
  let diff := Ffi.pngDiff approved png
  match Codec.nat.dec (Codec.ofBytes diff) with
  | some (n, rest) =>
    IO.FS.writeBinFile (actual / s!"{name}.diff.png") (Codec.toBytes rest)
    IO.println s!"FAIL {name}: {n} pixels differ; see {actual}/{name}.png and {name}.diff.png"
  | none => IO.println s!"FAIL {name}: the images cannot be compared; see {actual}/{name}.png"
  return false

end Paw.Tests.Goldens

open Paw Paw.Tests.Goldens in
def main (args : List String) : IO UInt32 := do
  let update := args.contains "--update"
  IO.FS.createDirAll goldenDir
  let mut ok := true
  for (name, scene, w, h, scale) in goldens do
    ok := (← check update name scene w h scale) && ok
  -- A scene names images by id; the images themselves are kept alive until they are drawn.
  match ← Image.decode (← IO.FS.readBinFile "tests/fixtures/photo.png") with
  | .ok img =>
    ok := (← check update "image-fit" (draw (imageFits img) 560 120) 560 120 1000) && ok
    keepAlive img
  | .error _ =>
    IO.println "FAIL image-fit: the fixture does not decode"
    ok := false
  let withPicture := (gallery.taskResult (.picture (← _root_.Gallery.sunset)) 1000).1
  ok := (← check update "gallery-picture" (sceneOf withPicture) 640 560 1000) && ok
  keepAlive withPicture
  -- The attack corpus stays in its cell.
  let (w, h) := (300, 30)
  let empty := Linux.renderPng (draw (corpusRow "") w h) w h
  for (what, payload) in Paw.Tests.Text.corpus do
    let png := Linux.renderPng (draw (corpusRow payload) w h) w h
    let outside := Ffi.pngDiffOutside empty png 100 0 200 30
    if outside != 0 then
      IO.println s!"FAIL {what}: {outside} pixels changed outside its cell"
      ok := false
  IO.println s!"corpus: {Paw.Tests.Text.corpus.length} texts drawn, checked against their neighbours"
  return if ok then 0 else 1
