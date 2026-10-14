/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Ffi

/-! # Linux desktop

The platform on X11 and Wayland, through the Rust layer: the byte formats of window events and
requests, each a `Codec` with its round trip proved, and `run`, which opens a window and runs an
app in it. -/

namespace Paw.Linux

open Codec

def mouseButtonCodec : Codec MouseButton :=
  nat.refine (fun | 0 => some .primary | 1 => some .secondary | 2 => some .middle | _ => none)
    (fun | .primary => 0 | .secondary => 1 | .middle => 2) (by intro b; cases b <;> rfl)

def keyTag : Key → Nat
  | .char _ => 0 | .enter => 1 | .escape => 2 | .backspace => 3 | .tab => 4 | .delete => 5
  | .left => 6 | .right => 7 | .up => 8 | .down => 9 | .home => 10 | .end_ => 11
  | .pageUp => 12 | .pageDown => 13 | .f _ => 14

def keyEnc : Key → List UInt8
  | .char c => nat.enc 0 ++ char.enc c
  | .f n => nat.enc 14 ++ nat.enc n
  | k => nat.enc (keyTag k)

def keyDec (bs : List UInt8) : Option (Key × List UInt8) := do
  let (tag, bs) ← nat.dec bs
  match tag with
  | 0 => let (c, bs) ← char.dec bs; pure (.char c, bs)
  | 1 => pure (.enter, bs) | 2 => pure (.escape, bs) | 3 => pure (.backspace, bs)
  | 4 => pure (.tab, bs) | 5 => pure (.delete, bs) | 6 => pure (.left, bs)
  | 7 => pure (.right, bs) | 8 => pure (.up, bs) | 9 => pure (.down, bs)
  | 10 => pure (.home, bs) | 11 => pure (.end_, bs) | 12 => pure (.pageUp, bs)
  | 13 => pure (.pageDown, bs)
  | 14 => let (n, bs) ← nat.dec bs; pure (.f n, bs)
  | _ => none

theorem key_roundtrip (k : Key) (rest : List UInt8) : keyDec (keyEnc k ++ rest) = some (k, rest) := by
  cases k <;> simp [keyEnc, keyDec, keyTag, List.append_assoc, nat.roundtrip, char.roundtrip]

def keyCodec : Codec Key := { enc := keyEnc, dec := keyDec, roundtrip := key_roundtrip }

def modsCodec : Codec Mods :=
  (pair (pair bool bool) (pair bool bool)).map (fun ((a, b), (c, d)) => ⟨a, b, c, d⟩)
    (fun m => ((m.shift, m.ctrl), (m.alt, m.super))) (fun _ => rfl)

def kindEnc : InputKind → List UInt8
  | .press p b => nat.enc 0 ++ Scene.pointCodec.enc p ++ mouseButtonCodec.enc b
  | .release p b => nat.enc 1 ++ Scene.pointCodec.enc p ++ mouseButtonCodec.enc b
  | .move p => nat.enc 2 ++ Scene.pointCodec.enc p
  | .wheel p dx dy => nat.enc 3 ++ Scene.pointCodec.enc p ++ int.enc dx ++ int.enc dy
  | .key k m pressed => nat.enc 4 ++ keyCodec.enc k ++ modsCodec.enc m ++ bool.enc pressed
  | .text s => nat.enc 5 ++ string.enc s
  | .paste s => nat.enc 6 ++ string.enc s
  | .leaveWindow => nat.enc 7

def kindDec (bs : List UInt8) : Option (InputKind × List UInt8) := do
  let (tag, bs) ← nat.dec bs
  match tag with
  | 0 => let (p, bs) ← Scene.pointCodec.dec bs; let (b, bs) ← mouseButtonCodec.dec bs; pure (.press p b, bs)
  | 1 => let (p, bs) ← Scene.pointCodec.dec bs; let (b, bs) ← mouseButtonCodec.dec bs; pure (.release p b, bs)
  | 2 => let (p, bs) ← Scene.pointCodec.dec bs; pure (.move p, bs)
  | 3 =>
    let (p, bs) ← Scene.pointCodec.dec bs
    let (dx, bs) ← int.dec bs
    let (dy, bs) ← int.dec bs
    pure (.wheel p dx dy, bs)
  | 4 =>
    let (k, bs) ← keyCodec.dec bs
    let (m, bs) ← modsCodec.dec bs
    let (pr, bs) ← bool.dec bs
    pure (.key k m pr, bs)
  | 5 => let (s, bs) ← string.dec bs; pure (.text s, bs)
  | 6 => let (s, bs) ← string.dec bs; pure (.paste s, bs)
  | 7 => pure (.leaveWindow, bs)
  | _ => none

theorem kind_roundtrip (k : InputKind) (rest : List UInt8) : kindDec (kindEnc k ++ rest) = some (k, rest) := by
  cases k <;> simp [kindEnc, kindDec, List.append_assoc, nat.roundtrip, Scene.pointCodec.roundtrip,
    mouseButtonCodec.roundtrip, int.roundtrip, keyCodec.roundtrip, modsCodec.roundtrip,
    bool.roundtrip, string.roundtrip]

def kindCodec : Codec InputKind := { enc := kindEnc, dec := kindDec, roundtrip := kind_roundtrip }

def inputCodec : Codec Input :=
  (pair kindCodec (pair nat (pair bool bool))).map (fun (k, t, s, o) => ⟨k, t, s, o⟩)
    (fun i => (i.kind, i.time, i.synthetic, i.obscured)) (fun _ => rfl)

def accessActionCodec : Codec AccessAction :=
  nat.refine (fun | 0 => some .press | 1 => some .focus | _ => none)
    (fun | .press => 0 | .focus => 1) (by intro a; cases a <;> rfl)

def eventEnc : WindowEvent → List UInt8
  | .input i => nat.enc 0 ++ inputCodec.enc i
  | .resize w h => nat.enc 1 ++ int.enc w ++ int.enc h
  | .close => nat.enc 2
  | .access id a => nat.enc 3 ++ nat.enc id.n ++ accessActionCodec.enc a

def eventDec (bs : List UInt8) : Option (WindowEvent × List UInt8) := do
  let (tag, bs) ← nat.dec bs
  match tag with
  | 0 => let (i, bs) ← inputCodec.dec bs; pure (.input i, bs)
  | 1 => let (w, bs) ← int.dec bs; let (h, bs) ← int.dec bs; pure (.resize w h, bs)
  | 2 => pure (.close, bs)
  | 3 =>
    let (id, bs) ← nat.dec bs
    let (a, bs) ← accessActionCodec.dec bs
    pure (.access ⟨id⟩ a, bs)
  | _ => none

theorem event_roundtrip (e : WindowEvent) (rest : List UInt8) :
    eventDec (eventEnc e ++ rest) = some (e, rest) := by
  cases e <;> simp [eventEnc, eventDec, List.append_assoc, nat.roundtrip, inputCodec.roundtrip,
    int.roundtrip, accessActionCodec.roundtrip]

def eventCodec : Codec WindowEvent := { enc := eventEnc, dec := eventDec, roundtrip := event_roundtrip }

def roleTag : Role → Nat
  | .label => 0 | .button => 1 | .checkBox => 2 | .textInput => 3 | .passwordInput => 4
  | .scrollView => 5 | .window => 6 | .dialog => 7

/-- An accessibility node as the Rust layer reads it. A password field's value is never sent. -/
def accessNodeEnc (n : AccessNode) : List UInt8 :=
  let value := if n.access.role == .passwordInput then none else n.access.value
  nat.enc n.id ++ nat.enc (roleTag n.access.role) ++ string.enc n.access.name.text ++
    (match value with | some v => bool.enc true ++ string.enc v.text | none => bool.enc false) ++
    nat.enc (match n.access.checked with | none => 0 | some false => 1 | some true => 2) ++
    bool.enc n.focusable ++ bool.enc n.disabled ++ Scene.rectCodec.enc n.bounds ++
    (list nat).enc n.children

/-- A request other than drawing, as the Rust layer reads it. -/
def requestEnc : Request → Option (List UInt8)
  | .present _ => none
  | .setTitle t => some (nat.enc 0 ++ string.enc t.text)
  | .setClipboard t => some (nat.enc 1 ++ string.enc t.text)
  | .openUri u => some (nat.enc 2 ++ string.enc u)
  | .notify t b => some (nat.enc 3 ++ string.enc t.text ++ string.enc b.text)
  | .quit => some (nat.enc 4)
  | .access focus nodes => some (nat.enc 5 ++ nat.enc focus ++ nat.enc nodes.length ++ nodes.flatMap accessNodeEnc)

/-- Text measured by the Rust layer, with the fonts it draws with. -/
def measure (style : TextStyle) (t : SafeText) : Int × Int :=
  let bytes := int.enc style.size ++ bool.enc style.bold ++ string.enc t.text
  ((pair int int).decodeAll (ofBytes (Ffi.measureRaw (toBytes bytes)))).getD (0, 0)

/-- A scene drawn offscreen as PNG, `w` × `h` pixels at `scale`/1000 pixels per logical pixel. -/
def renderPng (s : Scene) (w h : Nat) (scale : Nat := 1000) : ByteArray :=
  Ffi.renderPng (Scene.codec.bytes s) w.toUInt32 h.toUInt32 scale.toUInt32

/-- The window the Rust layer opened, as the runtime's platform. -/
def platform : Platform where
  poll := fun ms => do
    let b ← Ffi.windowPoll ms.toUInt32
    return ((list eventCodec).decodeAll (ofBytes b)).getD [.close]
  now := Ffi.now
  size := do
    let b ← Ffi.windowSize
    return ((pair int int).decodeAll (ofBytes b)).getD (px 800, px 600)
  measure := measure
  perform := fun r => match r with
    | .present s => Ffi.windowPresent (Scene.codec.bytes s)
    | r => match requestEnc r with
      | some bytes => Ffi.windowRequest (toBytes bytes)
      | none => pure ()

/-- Where each keyed widget is, one per line: its key, then its box's left, top, right and bottom
in logical pixels. -/
def layoutReport {Msg : Type} (tree : Node Msg) : String :=
  String.intercalate "\n" <| tree.keyedPlacements.map fun (k, r) =>
    s!"{k} {r.x0 / unitsPerPx} {r.y0 / unitsPerPx} {r.x1 / unitsPerPx} {r.y1 / unitsPerPx}"

/-- Opens a window of `w` × `h` logical pixels and runs `app` in it until it quits or the window
closes. Two hooks are for tests that drive the window from outside: if `PAW_TEST_LOG` names a
file, `describe` of the model is appended to it after each step; if `PAW_TEST_LAYOUT` names one,
it always holds `layoutReport` of the tree on screen. -/
def run {caps : List Cap} (app : App caps) (title : String := "Paw") (w h : Nat := 800)
    (describe : app.Model → String := fun _ => "") : IO Unit := do
  Ffi.windowOpen title w.toUInt32 h.toUInt32
  let log ← IO.getEnv "PAW_TEST_LOG"
  let layout ← IO.getEnv "PAW_TEST_LAYOUT"
  let last ← IO.mkRef ""
  let onStep : Runtime app → IO Unit := fun rt => do
    if let some path := log then
      let h ← IO.FS.Handle.mk path .append
      h.putStrLn (describe rt.model)
    if let some path := layout then
      let report := layoutReport rt.tree
      if report != (← last.get) then
        IO.FS.writeFile (path ++ ".tmp") report
        IO.FS.rename (path ++ ".tmp") path
        last.set report
  Runtime.run app platform onStep

end Paw.Linux
