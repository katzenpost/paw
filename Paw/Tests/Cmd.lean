/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Cmd
import Paw.Tests.Util

/-! # Commands and components

Effects that use authority need a designation of a widget with the effect's target key, which only
the router makes; results and undesignated input cannot produce them. Components embed with their
messages mapped and their capabilities proved a subset of the parent's. -/

namespace Paw.Tests.Cmd

open Paw

def r (x y w h : Int) : Rect := Rect.ofXYWH (px x) (px y) (px w) (px h)

def sz (n : Nat) : Nat := (px n).toNat

def linkBox (kind := "link") : Widget String := Widget.Spec.build (σ := NoState) {
  kind
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz 10), SizeReq.fixedSize (sz 10))
  render := fun _ _ _ => Scene.empty
  render_within := fun _ _ v => Scene.empty_within v
  handle := fun _ st _ e => match e with
    | .click .. => some (st, [.emit "open"])
    | _ => none }

/-- Two links keyed "msg1" and "msg2", side by side. -/
def tree : Node String :=
  let row := Node.container hstack.toLayout [Node.leaf linkBox "msg1", Node.leaf linkBox "msg2"]
  (row.init 1).1.resize Env.mock (r 0 0 20 10)

/-- A designation from a real click on the link keyed `key`. -/
def clickOn (x : Int) (synthetic := false) : Option Designation :=
  let rt := ({} : Router).observe tree 0
  let (rt, _) := rt.route tree { kind := .press ⟨px x, px 5⟩ .primary, time := 1000, synthetic }
  let (_, ds) := rt.route tree { kind := .release ⟨px x, px 5⟩ .primary, time := 1100, synthetic }
  ds.findSome? (·.designation)

abbrev caps : List Cap := [.clipboardWrite, .openUri]

/-- The app's model: links opened, and the last error. -/
structure Model where
  opened : List String := []
  refused : Nat := 0
  deriving Repr, BEq, Inhabited

inductive Msg where
  | openLink (key : String) (uri : String)
  | copy (key : String) (text : String)
  | arrived (uri : String)
  deriving Repr, BEq

def update : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  | .user d, .openLink key uri => do
    match Effect.openUri? key uri with
    | some e =>
      if h : e.DesignatedBy d then
        emit (.effect d e (by decide) h)
        modify fun (m, cs) => ({ m with opened := m.opened ++ [uri] }, cs)
      else modify fun (m, cs) => ({ m with refused := m.refused + 1 }, cs)
    | none => modify fun (m, cs) => ({ m with refused := m.refused + 1 }, cs)
  | .user d, .copy key text => do
    let e := Effect.setClipboard key (SafeText.filter text)
    if h : e.DesignatedBy d then emit (.effect d e (by decide) h)
    else modify fun (m, cs) => ({ m with refused := m.refused + 1 }, cs)
  | .other, .openLink .. => modify fun (m, cs) => ({ m with refused := m.refused + 1 }, cs)
  | _, .arrived _ => emit (.setTitle (SafeName.filter "new message"))
  | _, _ => pure ()

def run (o : Origin) (msg : Msg) (m : Model := {}) : Model × List (Cmd Msg caps o) :=
  let ((), (m, cs)) := (update o msg).run (m, #[])
  (m, cs.toList)

/-- A component: a counter with its own messages, needing no capabilities. -/
abbrev counter : Component [] where
  Model := Nat
  Msg := Bool
  update := fun _ up => modify fun (n, cs) => (if up then n + 1 else n - 1, cs)
  view := fun n => Node.leaf (linkBox s!"counter{n}") |>.mapMsg fun _ => true

def tests : TestM Unit := do
  let some d1 := clickOn 5 | check "a real click designates" false
  let some d2 := clickOn 15 | check "a real click designates" false
  checkEq "the designation names the link's key" (some "msg1") d1.key
  checkEq "and the other" (some "msg2") d2.key
  check "a synthetic click designates nothing" (clickOn 5 (synthetic := true)).isNone
  -- An effect needs a designation of a widget with its target key.
  let (m, cs) := run (.user d1) (.openLink "msg1" "https://example.org/a")
  checkEq "the link the user clicked opens" ["https://example.org/a"] m.opened
  checkEq "as one command" 1 cs.length
  check "which uses authority" (cs.all (·.usesAuthority))
  let (m, cs) := run (.user d1) (.openLink "msg2" "https://example.org/b")
  checkEq "a click on one link cannot open another" 1 m.refused
  checkEq "no command" 0 cs.length
  let (m, _) := run .other (.openLink "msg1" "https://example.org/a")
  checkEq "a message that is not the user's choice opens nothing" 1 m.refused
  let (_, cs) := run (.user d2) (.copy "msg2" "text")
  checkEq "copying the clicked item" 1 cs.length
  let (m, _) := run (.user d2) (.copy "msg1" "text")
  checkEq "copying another item is refused" 1 m.refused
  -- Commands that need no designation.
  let (_, cs) := run .other (.arrived "x")
  checkEq "a title from any message" 1 cs.length
  check "and it uses no authority" (cs.all (!·.usesAuthority))
  -- Links are checked.
  check "https is allowed" (Effect.openUri? "k" "https://example.org").isSome
  check "http is allowed" (Effect.openUri? "k" "http://example.org").isSome
  check "mailto is allowed" (Effect.openUri? "k" "mailto:a@example.org").isSome
  check "javascript is refused" (Effect.openUri? "k" "javascript:alert(1)").isNone
  check "file is refused" (Effect.openUri? "k" "file:///etc/passwd").isNone
  check "a space is refused" (Effect.openUri? "k" "https://a b").isNone
  check "a control character is refused" (Effect.openUri? "k" "https://a\x1bb").isNone
  check "a leading dash is refused" (Effect.openUri? "k" "-https://a").isNone
  check "an empty host is refused" (Effect.openUri? "k" "https://").isNone
  check "upper case schemes are allowed" (Effect.openUri? "k" "HTTPS://example.org").isSome
  checkEq "an effect's target" (some "k") (Effect.setClipboard "k" SafeText.empty).target
  checkEq "the clipboard's capability" Cap.clipboardWrite (Effect.setClipboard "k" SafeText.empty).cap
  -- Components.
  let ((), (n, _)) := (counter.update .other true).run (41, #[])
  checkEq "a component updates its own model" 42 n
  let sub : [] ⊆ caps := by decide
  let lifted : List (Cmd String caps .other) := ((run .other (.arrived "x")).2.map
    (Cmd.mapMsg fun _ => "x")).map (Cmd.lift (List.Subset.refl _))
  checkEq "a lifted command keeps what it does" 1 lifted.length
  check "lifting keeps authority as it was" (lifted.all (!·.usesAuthority))
  let _ := sub
  let v := (counter.view 3).init 1 |>.1
  checkEq "a component's view, mapped into the parent's messages" "counter3" v.kind
  let (_, reqs) := v.handleAt Env.mock ⟨1⟩ (.click ⟨0, 0⟩ .primary 1)
  checkEq "its messages come out mapped" (some [Req.emit true]) reqs
  -- Producers.
  let prod : Cmd Nat [.io] .other := .producer (fun send => do send 1; send 2) (by decide)
  check "a producer uses no authority" (!prod.usesAuthority)
  let sent ← IO.mkRef ([] : List String)
  match (prod.mapMsg toString).lift (caps' := [.notify, .io]) (by decide) with
  | .producer run _ => run fun s => sent.modify (· ++ [s])
  | _ => check "a producer maps and lifts to a producer" false
  checkEq "a mapped producer sends its messages mapped" ["1", "2"] (← sent.get)
  checkEq "Origin.designation" (some d1) (Origin.user d1).designation
  checkEq "no designation for other" none Origin.other.designation

end Paw.Tests.Cmd
