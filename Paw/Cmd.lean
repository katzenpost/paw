/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Route

/-! # Commands

What an app's `update` asks the runtime to do. Effects that use authority, such as writing the
clipboard or opening a link, need two things:

- a capability the app or component declared, proved to be among its `caps`;
- a `Designation` from the input being handled, of a widget whose key is the effect's target.

Commands are indexed by the `Origin` of the message being handled, and an effect exists only at
`Origin.user d`, for that `d`. So a message that is not the user's choice, such as a network
result, a timer or a synthetic click, cannot produce one (`Cmd.other_no_authority`), and a
designation kept from an earlier input authorizes nothing later. -/

namespace Paw

inductive Cap where
  | clipboardWrite
  | openUri
  | notify
  /-- Running a task: arbitrary `IO`, which Lean does not confine. -/
  | io
  deriving Repr, DecidableEq, Inhabited

/-- Where a message came from. -/
inductive Origin where
  /-- Input the user aimed at the widget `d` names. -/
  | user (d : Designation)
  /-- Anything else: a task's result, a timer, input that designated nothing. -/
  | other
  deriving Repr, DecidableEq

def Origin.designation : Origin → Option Designation
  | .user d => some d
  | .other => none

namespace Uri

def schemes : List String := ["https://", "http://", "mailto:"]

/-- A character a link may hold: printable, no space, no bidi control. -/
def charOk (c : Char) : Bool :=
  c.toNat > 0x20 && Text.allowed c && !Text.bidiControl c.toNat

/-- A link to open: an allowed scheme, something after it, and only printable characters. -/
def allowed (u : String) : Bool :=
  u.all charOk && schemes.any fun p => u.toLower.startsWith p && u.length > p.length

/-- Where a link goes, as the user should be told before following it: its scheme and host, such
as `https://github.com`, or for `mailto:` the address. -/
def destination (u : String) : String :=
  match schemes.find? fun p => u.toLower.startsWith p with
  | some "mailto:" => u
  | some p =>
    let rest := (u.drop p.length).toString
    p ++ String.ofList (rest.toList.takeWhile fun c => c != '/' && c != '?' && c != '#')
  | none => u

end Uri

/-- A link that may be opened: one with an allowed scheme and only printable characters. -/
structure Link where
  uri : String
  ok : Uri.allowed uri = true

/-- `uri` as a link, if it is one Paw opens. -/
def Link.parse? (uri : String) : Option Link := if h : Uri.allowed uri = true then some ⟨uri, h⟩ else none

/-- Effects that use authority, by the capability each needs. -/
inductive Effect : Cap → Type where
  /-- Write `t` to the clipboard, for the item keyed `target`. -/
  | setClipboard (target : String) (t : SafeText) : Effect .clipboardWrite
  /-- Open `uri` with the platform's opener, for the link keyed `target`. -/
  | openUri (target : String) (uri : String) (ok : Uri.allowed uri = true) : Effect .openUri

namespace Effect

def cap {c : Cap} (_ : Effect c) : Cap := c

/-- The key of the widget the user must have chosen. -/
def target {c : Cap} : Effect c → Option String
  | .setClipboard k _ => some k
  | .openUri k .. => some k

/-- `d` designates the widget this effect is for. -/
def DesignatedBy {c : Cap} (e : Effect c) (d : Designation) : Prop :=
  e.target.all (fun k => d.key == some k) = true

instance {c : Cap} (e : Effect c) (d : Designation) : Decidable (e.DesignatedBy d) := by
  unfold DesignatedBy; infer_instance

/-- An effect opening `link`, for the widget keyed `target`. -/
def openLink (target : String) (link : Link) : Effect .openUri := .openUri target link.uri link.ok

/-- An effect opening `uri`, if it is a link Paw opens. -/
def openUri? (target uri : String) : Option (Effect .openUri) :=
  if h : Uri.allowed uri = true then some (.openUri target uri h) else none

end Effect

inductive Cmd (Msg : Type) (caps : List Cap) : Origin → Type where
  | effect {c : Cap} (d : Designation) (e : Effect c) (granted : c ∈ caps)
      (designated : e.DesignatedBy d) : Cmd Msg caps (.user d)
  /-- Runs `io` and gives its result to `update` as a message of origin `other`. -/
  | task {o : Origin} (io : IO Msg) (granted : Cap.io ∈ caps) : Cmd Msg caps o
  /-- Runs `run` on a thread of its own, giving it a function that sends a message to `update`,
  with origin `other`, as often as it likes, from any thread, until `run` returns. -/
  | producer {o : Origin} (run : (Msg → IO Unit) → IO Unit) (granted : Cap.io ∈ caps) :
      Cmd Msg caps o
  | notify {o : Origin} (title : SafeName) (body : SafeText) (granted : Cap.notify ∈ caps) :
      Cmd Msg caps o
  | setTitle {o : Origin} (title : SafeName) : Cmd Msg caps o
  | quit {o : Origin} : Cmd Msg caps o
  /-- `m` to `update` in `ms` milliseconds, as a message of origin `other`: a timer carries no
  authority, whatever started it. -/
  | after {o : Origin} (ms : Nat) (m : Msg) : Cmd Msg caps o

namespace Cmd

variable {Msg : Type} {caps : List Cap} {o : Origin}

def usesAuthority : Cmd Msg caps o → Bool
  | .effect .. => true
  | _ => false

/-- A message that is not the user's choice cannot produce an effect that uses authority. -/
theorem other_no_authority (cmd : Cmd Msg caps .other) : cmd.usesAuthority = false := by
  cases cmd <;> rfl

def mapMsg {β : Type} (f : Msg → β) : Cmd Msg caps o → Cmd β caps o
  | .effect d e g h => .effect d e g h
  | .task io g => .task (f <$> io) g
  | .producer run g => .producer (fun send => run (send ∘ f)) g
  | .notify t b g => .notify t b g
  | .setTitle t => .setTitle t
  | .quit => .quit
  | .after ms m => .after ms (f m)

/-- A component's command as its parent's, whose capabilities include the component's. -/
def lift {caps' : List Cap} (sub : caps ⊆ caps') : Cmd Msg caps o → Cmd Msg caps' o
  | .effect d e g h => .effect d e (sub g) h
  | .task io g => .task io (sub g)
  | .producer run g => .producer run (sub g)
  | .notify t b g => .notify t b (sub g)
  | .setTitle t => .setTitle t
  | .quit => .quit
  | .after ms m => .after ms m

theorem lift_usesAuthority {caps' : List Cap} (sub : caps ⊆ caps') (c : Cmd Msg caps o) :
    (c.lift sub).usesAuthority = c.usesAuthority := by
  cases c <;> rfl

end Cmd

/-- `update` runs with the model and the commands emitted so far as state, at one origin. -/
abbrev UpdateM (σ Msg : Type) (caps : List Cap) (o : Origin) := StateM (σ × Array (Cmd Msg caps o))

def emit {σ Msg : Type} {caps : List Cap} {o : Origin} (c : Cmd Msg caps o) :
    UpdateM σ Msg caps o Unit :=
  modify fun (s, cs) => (s, cs.push c)

/-- A model, its messages, an update that may use `caps`, and a view. An app is the component at
the root; others are embedded by mapping their messages and lifting their commands. -/
structure Component (caps : List Cap) where
  Model : Type
  Msg : Type
  update : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  view : Model → Node Msg

end Paw
