/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw
import LeanBench

/-! # Benchmarks

Each layer at the sizes an app meets and a few times larger: text filtering, the byte formats,
layout, the widget tree, routing, a whole runtime step, and the calls into the Rust layer. Every
action reads its input from a reference and stores its result in one, so that nothing is computed
once outside the timed region.

The budget: one input handled, from routing to the new scene, in well under a millisecond for an
ordinary view; a frame drawn in a few milliseconds. -/

namespace Paw.Bench

open Paw

def cfg (suite : String) (samples : Nat := 50) : LeanBench.BenchConfig :=
  { suite := some suite, samples, warmup := 3 }

/-- A bench of `f` on the input in `input`, keeping the result in `out`. -/
def mkBench {α β : Type} (name suite : String) (input : IO.Ref α) (out : IO.Ref β) (f : α → β)
    (samples : Nat := 50) : LeanBench.Bench :=
  { name, config := cfg suite samples, action := do out.set (f (← input.get)) }

/-! ## An app with a list of `n` rows -/

inductive Msg where
  | typed (s : String)
  | remove (id : Nat)
  | add
  deriving Inhabited

/-- A row, the argument its lazy view is built from. -/
structure Row where
  id : Nat
  text : String
  deriving BEq, TypeName, Inhabited

structure Model where
  items : List Row
  draft : String := ""
  deriving BEq, Inhabited

def update : (o : Origin) → Msg → UpdateM Model Msg [] o Unit
  | _, .typed s => modify fun (m, cs) => ({ m with draft := s }, cs)
  | _, .remove id => modify fun (m, cs) => ({ m with items := m.items.filter (·.id != id) }, cs)
  | _, .add => modify fun (m, cs) => ({ m with items := ⟨m.items.length, m.draft⟩ :: m.items }, cs)

def view (m : Model) : Node Msg :=
  Ui.col [
    Ui.row [Ui.textField m.draft .typed {} "draft", Ui.button "Add" .add "add"],
    Ui.scroll (Ui.list m.items (toString ·.id) fun row => Ui.lazy row fun r =>
      Ui.row [Ui.text (SafeText.filter r.text), Ui.spacer, Ui.button "Remove" (.remove r.id)]) "list"]

def app : App [] := { Model := Model, Msg := Msg, init := default, update, view }

def model (n : Nat) : Model :=
  { items := (List.range n).map fun i => ⟨i, s!"message number {i}, which says something"⟩ }

def measure : TextStyle → SafeText → Int × Int := Env.mock.measure

def runtime (n : Nat) : Runtime app :=
  let rt := (Paw.Runtime.start app (Rect.ofXYWH 0 0 (px 800) (px 600)) 0 measure).1
  { rt with model := model n }.rebuild.1

def center {caps : List Cap} {a : App caps} (rt : Runtime a) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨0, 0⟩

/-- A click on Add, then typing one character into the field, as two whole runtime steps each. -/
def clickAndType (rt : Runtime app) : Runtime app :=
  let p := center rt "add"
  let (rt, _) := rt.step (.input { kind := .press p .primary, time := 1000 }) 1000
  let (rt, _) := rt.step (.input { kind := .release p .primary, time := 1050 }) 1050
  let d := center rt "draft"
  let (rt, _) := rt.step (.input { kind := .press d .primary, time := 2000 }) 2000
  let (rt, _) := rt.step (.input { kind := .release d .primary, time := 2050 }) 2050
  let (rt, _) := rt.step (.input { kind := .text "x", time := 2600 }) 2600
  rt

def moves (rt : Runtime app) : Runtime app := Id.run do
  let mut rt := rt
  for i in [0:20] do
    rt := (rt.step (.input { kind := .move ⟨px (10 + i), px 300⟩, time := 3000 + i }) (3000 + i)).1
  return rt

/-! ## The suites -/

def textBenches : IO (Array LeanBench.Bench) := do
  let ascii ← IO.mkRef (String.ofList (List.replicate 1024 'a'))
  let mixed ← IO.mkRef (String.join (List.replicate 64 "héllo wörld 漢字 🚀‮\x1b "))
  let big ← IO.mkRef (String.intercalate "\n" (List.replicate 1024 (String.ofList (List.replicate 63 'm'))))
  let name ← IO.mkRef "Ꭺlice Ⅼovelace"
  let t ← IO.mkRef SafeText.empty
  let ls ← IO.mkRef ([] : List SafeText)
  let s ← IO.mkRef ""
  return #[
    mkBench "text filter 1 KiB ascii" "text" ascii t (SafeText.filter ·),
    mkBench "text filter 1 KiB mixed" "text" mixed t (SafeText.filter ·),
    mkBench "text lines 64 KiB" "text" big ls (SafeText.lines ·),
    mkBench "text skeleton of a name" "text" name s Text.skeleton]

def sceneOf (n : Nat) : Scene :=
  Scene.ofList ((List.range n).map fun (i : Nat) =>
    let r := Rect.ofXYWH 0 (px (i : Int)) (px 300) (px 20)
    (r, if i % 2 == 0 then Draw.fill r Color.white (px 4)
        else Draw.text ⟨0, px (i : Int)⟩ (SafeText.trusted s!"row {i} of the scene") {}))

def codecBenches : IO (Array LeanBench.Bench) := do
  let s100 ← IO.mkRef (sceneOf 100)
  let s2000 ← IO.mkRef (sceneOf 2000)
  let bytes2000 ← IO.mkRef (Scene.codec.bytes (sceneOf 2000))
  -- What Lean decodes in practice: a poll's worth of window events from the Rust layer.
  let events : List WindowEvent := (List.range 50).map fun (i : Nat) =>
    .input { kind := if i % 5 == 0 then .text "a" else .move ⟨px (i : Int), px 300⟩, time := i }
  let eventBytes ← IO.mkRef (Codec.ofBytes ((Codec.list Linux.eventCodec).bytes events))
  let decoded ← IO.mkRef (none : Option (List WindowEvent))
  let out ← IO.mkRef ByteArray.empty
  return #[
    mkBench "codec encode scene 100" "codec" s100 out (fun s => Scene.codec.bytes s),
    mkBench "codec encode scene 2000" "codec" s2000 out (fun s => Scene.codec.bytes s),
    mkBench "codec decode 50 window events" "codec" eventBytes decoded (Codec.list Linux.eventCodec).decodeAll,
    mkBench "ffi scene echo 2000" "codec" bytes2000 out Ffi.sceneEcho]

def items (n : Nat) : List Item :=
  (List.range n).map fun i => { w := SizeReq.minSize ((i % 7) * 64), h := SizeReq.flexSize 1280 (i % 3) }

def layoutBenches : IO (Array LeanBench.Bench) := do
  let i10 ← IO.mkRef (items 10)
  let i1000 ← IO.mkRef (items 1000)
  let out ← IO.mkRef ([] : List Rect)
  let v := Rect.ofXYWH 0 0 (px 800) (px 600)
  return #[
    mkBench "layout vstack 10" "layout" i10 out (vstack.toLayout.assign v ·),
    mkBench "layout vstack 1000" "layout" i1000 out (vstack.toLayout.assign v ·),
    mkBench "layout hgrid 1000" "layout" i1000 out (hgrid.toLayout.assign v ·)]

def treeBenches : IO (Array LeanBench.Bench) := do
  let env : Env := { measure }
  let v := Rect.ofXYWH 0 0 (px 800) (px 600)
  let built (n : Nat) := (((view (model n)).resolve none).init 1).1.resize env v
  let m100 ← IO.mkRef (model 100)
  let m1000 ← IO.mkRef (model 1000)
  let t100 ← IO.mkRef (built 100)
  let t1000 ← IO.mkRef (built 1000)
  -- A window tall enough to show every one of 1000 rows: the most drawing a frame can need.
  let tall ← IO.mkRef ((((view (model 1000)).resolve none).init 1).1.resize env (Rect.ofXYWH 0 0 (px 800) (px 40000)))
  let next1000 ← IO.mkRef (model 1000 |>.items |>.drop 1 |> fun items => ({ items } : Model))
  let node ← IO.mkRef (default : Node Msg)
  let scene ← IO.mkRef Scene.empty
  let merged ← IO.mkRef ((default : Node Msg), ([] : List (Req Msg)), 0)
  let point ← IO.mkRef (none : Option (Node Msg))
  return #[
    mkBench "tree view and init 100" "tree" m100 node fun m => (((view m).resolve none).init 1).1,
    mkBench "tree view and init 1000" "tree" m1000 node fun m => (((view m).resolve none).init 1).1,
    mkBench "tree resize 1000" "tree" t1000 node (·.resize env v),
    mkBench "tree render 100" "tree" t100 scene (·.render env),
    mkBench "tree render 1000" "tree" t1000 scene (·.render env),
    mkBench "tree render 1000, all visible" "tree" tall scene (·.render env),
    { name := "tree merge 1000 after removing one", config := cfg "tree"
      action := do
        let old ← t1000.get
        merged.set (((view (← next1000.get)).resolve (some old)).merge env old 5000) },
    mkBench "tree hit test 1000" "tree" t1000 point (·.hit? ⟨px 400, px 300⟩)]

def routeBenches : IO (Array LeanBench.Bench) := do
  let env : Env := { measure }
  let tree := (((view (model 1000)).resolve none).init 1).1.resize env (Rect.ofXYWH 0 0 (px 800) (px 600))
  let t ← IO.mkRef tree
  let rt ← IO.mkRef (({} : Router).observe tree 0)
  let out ← IO.mkRef (({} : Router), ([] : List Delivery))
  let observed ← IO.mkRef ({} : Router)
  return #[
    { name := "route observe 1000", config := cfg "route"
      action := do observed.set ((← rt.get).observe (← t.get) 10) },
    { name := "route press 1000", config := cfg "route"
      action := do out.set ((← rt.get).route (← t.get) { kind := .press ⟨px 400, px 300⟩ .primary, time := 1000 }) },
    { name := "route move 1000", config := cfg "route"
      action := do out.set ((← rt.get).route (← t.get) { kind := .move ⟨px 400, px 300⟩, time := 1000 }) }]

/-- The list with a popup open over it. -/
def viewWithPopup (m : Model) : Node Msg :=
  Ui.col [Ui.popup true (Ui.button "Menu" .add "menu")
    (Ui.col ((List.range 5).map fun i => Ui.button s!"Item {i}" .add s!"item-{i}")) .add "pop", view m]

def overlayBenches : IO (Array LeanBench.Bench) := do
  let env : Env := { measure }
  let win := Rect.ofXYWH 0 0 (px 800) (px 600)
  let tree := (((viewWithPopup (model 1000)).resolve none).init 1).1.resize env win
  let t ← IO.mkRef tree
  let rt ← IO.mkRef (({} : Router).observe tree 0)
  let inPopup : Point := ((tree.findKey? "item-2").map fun n =>
    ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩).getD ⟨0, 0⟩
  let out ← IO.mkRef (({} : Router), ([] : List Delivery))
  let observed ← IO.mkRef ({} : Router)
  let scene ← IO.mkRef Scene.empty
  return #[
    { name := "overlay observe 1000", config := cfg "overlay"
      action := do observed.set ((← rt.get).observe (← t.get) 10) },
    { name := "overlay move in popup 1000", config := cfg "overlay"
      action := do out.set ((← rt.get).route (← t.get) { kind := .move inPopup, time := 1000 }) },
    { name := "overlay press outside 1000", config := cfg "overlay"
      action := do out.set ((← rt.get).route (← t.get) { kind := .press ⟨px 400, px 500⟩ .primary, time := 1000 }) },
    { name := "overlay render overlays 1000", config := cfg "overlay"
      action := do
        let (r, t) := (← rt.get, ← t.get)
        scene.set (Node.renderOverlays env win (r.shown.toList.filterMap fun (_, p, _) => t.get? p)) }]

/-- The list, fading in over a second. -/
def fadingApp : App [] := { app with view := fun m => Ui.fadeIn (view m) 1000 }

/-- Sixty frames of the fade, 16 ms apart, as `Runtime.advance` steps. -/
def frames (rt : Runtime fadingApp) : Runtime fadingApp := Id.run do
  let mut rt := rt
  for i in [1:61] do
    rt := (rt.advance (16 * i)).1
  return rt

def timeBenches : IO (Array LeanBench.Bench) := do
  let idle ← IO.mkRef (runtime 1000)
  let deadline ← IO.mkRef (none : Option Nat)
  let fading ← IO.mkRef (let rt := (Paw.Runtime.start fadingApp (Rect.ofXYWH 0 0 (px 800) (px 600)) 0 measure).1
    { rt with model := model 1000 }.rebuild.1)
  let out ← IO.mkRef (Paw.Runtime.start fadingApp (Rect.ofXYWH 0 0 (px 800) (px 600)) 0 measure).1
  return #[
    mkBench "time next deadline, idle, 1000 rows" "time" idle deadline (·.nextDeadline),
    mkBench "time 60 frames of a fade, 1000 rows" "time" fading out frames (samples := 10)]

def runtimeBenches : IO (Array LeanBench.Bench) := do
  let r10 ← IO.mkRef (runtime 10)
  let r100 ← IO.mkRef (runtime 100)
  let r1000 ← IO.mkRef (runtime 1000)
  let out ← IO.mkRef (runtime 0)
  return #[
    mkBench "runtime click and type, 10 rows (5 steps)" "runtime" r10 out clickAndType,
    mkBench "runtime click and type, 100 rows (5 steps)" "runtime" r100 out clickAndType,
    mkBench "runtime click and type, 1000 rows (5 steps)" "runtime" r1000 out clickAndType (samples := 20),
    mkBench "runtime 20 idle moves, 1000 rows" "runtime" r1000 out moves (samples := 20)]

def platformBenches : IO (Array LeanBench.Bench) := do
  let short ← IO.mkRef (SafeText.trusted "Remove")
  let long ← IO.mkRef (SafeText.trusted (String.join (List.replicate 20 "a fairly long line of text ")))
  let size ← IO.mkRef ((0 : Int), (0 : Int))
  let scene ← IO.mkRef ((runtime 100).tree.render (runtime 100).env)
  let png ← IO.mkRef ByteArray.empty
  return #[
    mkBench "platform measure a word" "platform" short size (Linux.measure {}),
    mkBench "platform measure 540 characters" "platform" long size (Linux.measure {}),
    mkBench "platform draw 100 rows to PNG, 800x600" "platform" scene png (Linux.renderPng · 800 600) (samples := 20)]

end Paw.Bench

open Paw.Bench in
def main (args : List String) : IO UInt32 := do
  for suite in [textBenches, codecBenches, layoutBenches, treeBenches, routeBenches, overlayBenches, timeBenches, runtimeBenches,
      platformBenches] do
    (← suite).forM LeanBench.register
  LeanBench.runMain args
