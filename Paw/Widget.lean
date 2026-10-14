/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Scene
import Paw.Layout
import Paw.Event
import Paw.Style

/-! # Widgets

A widget is a record of functions over its own state, as in monomer, with the law that what it
draws lies within the box it is given. Unlike monomer's, these functions never see the widget tree:
the tree is walked by `Paw.Tree`, which merges, lays out and draws children itself, so a widget
cannot draw or act on anything but its own box and state. -/

/-! Common types as `Ui.lazy` arguments. -/
deriving instance TypeName for String, Nat, Int, Bool

namespace Paw

/-- The state of a widget that keeps none. -/
structure NoState where
  deriving TypeName, Repr, Inhabited

structure WidgetId where
  n : Nat
  deriving Repr, DecidableEq, Hashable, Ord, Inhabited

/-- What widgets know of the world. -/
structure Env where
  /-- The width and height of a line of text, from the Rust layer or a mock. -/
  measure : TextStyle → SafeText → Int × Int
  /-- Milliseconds since the app started. -/
  now : Nat := 0
  theme : Theme := Theme.light
  focused : Option WidgetId := none
  hovered : Option WidgetId := none
  pressed : Option WidgetId := none
  /-- The widget being asked, which the tree sets. -/
  self : WidgetId := ⟨0⟩
  /-- The rectangle the widget's children are laid out in, which the tree sets. -/
  content : Rect := default
  /-- The window, which overlays are placed within. -/
  window : Rect := default
  /-- The widget being asked is enabled, which the tree sets. -/
  enabled : Bool := true
  /-- The window has keyboard focus. -/
  windowFocused : Bool := true
  /-- Animations run; false when the user asked for reduced motion, and they jump to their end. -/
  motion : Bool := true

/-- Text measured as monomer's tests measure it: 10 pixels a character, 20 pixels a line. -/
def Env.mock : Env := { measure := fun _ t => (px (t.text.length * 10), px 20) }

namespace Env

def isFocused (env : Env) : Bool := env.focused == some env.self
def isHovered (env : Env) : Bool := env.hovered == some env.self
def isPressed (env : Env) : Bool := env.pressed == some env.self

/-- The widget being asked, as styles see it. -/
def interaction (env : Env) : Interaction :=
  { hovered := env.isHovered, focused := env.isFocused, active := env.isPressed, disabled := !env.enabled }

/-- How the widget being asked looks now, by `s`. -/
def look (env : Env) (s : Style) : StyleState := s.current env.interaction

end Env

/-- What a widget asks of the runtime. -/
inductive Req (Msg : Type) where
  /-- A message for the app's `update`. -/
  | emit (m : Msg)
  /-- A message for `update` only if the input being handled designated the widget: the user
  chose it, unmoved, not by synthetic input, and not by assistive technology. Otherwise dropped. -/
  | choose (m : Msg)
  /-- Keyboard focus to the widget. -/
  | focus (id : WidgetId)
  | render
  /-- Write the clipboard. The runtime does it only for input that designated the widget. -/
  | copy (t : SafeText)
  deriving Repr, DecidableEq

def Req.map {α β : Type} (f : α → β) : Req α → Req β
  | .emit m => .emit (f m)
  | .choose m => .choose (f m)
  | .focus id => .focus id
  | .render => .render
  | .copy t => .copy t

/-- What a widget is, to assistive technology. -/
inductive Role where
  | label
  | button
  | checkBox
  | textInput
  /-- A field for a secret, whose value is never told. -/
  | passwordInput
  | scrollView
  | window
  /-- A modal dialog, above everything else. -/
  | dialog
  /-- An image or icon, named by its description. -/
  | image
  deriving Repr, DecidableEq, Inhabited

/-- How a widget describes itself to assistive technology such as a screen reader. Names and values
are `SafeText`, filtered as anything shown on screen is, since a screen reader speaks them in the
same voice as the app's own words. -/
structure Access where
  role : Role
  name : SafeText := SafeText.empty
  value : Option SafeText := none
  checked : Option Bool := none
  deriving Repr, DecidableEq, Inhabited

/-- A widget as the tree holds it: functions over its state as a `Dynamic`. Widgets are written as
a `Widget.Spec` over their own state type and built with `Widget.Spec.build`; keeping the state
dynamic keeps nodes, trees and the runtime in `Type`, where `IO` can hold them. -/
structure Widget (Msg : Type) where
  /-- Widgets merge only with widgets of the same kind. -/
  kind : String
  init : Dynamic
  /-- The state to keep, given the state of the widget this one replaces on a rebuild. -/
  merge : Dynamic → Dynamic
  sizeReq : Env → Dynamic → SizeReq × SizeReq
  /-- For a container, the rectangle its children are laid out in, given its box and what they
  ask for: the box itself, or for a scroll, a rectangle as large as the content, shifted by the
  scroll. Children are still drawn clipped to the box. -/
  content : Env → Dynamic → Rect → SizeReq × SizeReq → Rect
  render : Env → Dynamic → Rect → Scene
  render_within : ∀ env st v, (render env st v).Within v
  handle : Env → Dynamic → Rect → Event → Option (Dynamic × List (Req Msg))
  focusable : Bool
  /-- Requests when the widget leaves the tree. -/
  dispose : Dynamic → List (Req Msg)
  /-- How it describes itself to assistive technology, if at all. -/
  access : Env → Dynamic → Option Access
  /-- For a widget that may tick: while this gives `some ms`, the widget gets `Event.tick` every
  `ms` milliseconds, while the window can be seen. A function of its state, as Elm's subscriptions
  are of the model: a widget that leaves the tree or changes its state stops ticking, with nothing
  to undo. `none` for the many widgets that never tick, which costs nothing to ask. -/
  every : Option (Env → Dynamic → Option Nat)
  /-- For a widget that may move, as an animation does: while this gives true, the router counts the
  widget and what is in it as moved on every layout, so nothing in them can be designated until
  they have been still for `stableMs`. -/
  moving : Option (Env → Dynamic → Bool)
  /-- How a container changes its children's drawing, before the tree clips it to the box: a
  fade lowers its alpha. -/
  mapChildren : Env → Dynamic → Scene → Scene
  /-- The pointer's shape over it. -/
  cursor : Env → Dynamic → Cursor
  /-- For a widget whose height depends on its width, such as a wrapped paragraph: its height
  request at a width. The tree asks once widths are known. -/
  heightFor : Option (Env → Dynamic → Int → SizeReq)

/-- A widget over its own state type `σ`. -/
structure Widget.Spec (Msg σ : Type) where
  kind : String
  init : σ
  merge : σ → σ := id
  sizeReq : Env → σ → SizeReq × SizeReq
  content : Env → σ → Rect → SizeReq × SizeReq → Rect := fun _ _ v _ => v
  render : Env → σ → Rect → Scene
  render_within : ∀ env st v, (render env st v).Within v
  handle : Env → σ → Rect → Event → Option (σ × List (Req Msg)) := fun _ _ _ _ => none
  focusable : Bool := false
  dispose : σ → List (Req Msg) := fun _ => []
  access : Env → σ → Option Access := fun _ _ => none
  every : Option (Env → σ → Option Nat) := none
  moving : Option (Env → σ → Bool) := none
  mapChildren : Env → σ → Scene → Scene := fun _ _ s => s
  cursor : Env → σ → Cursor := fun _ _ => .default
  heightFor : Option (Env → σ → Int → SizeReq) := none

namespace Widget.Spec

variable {Msg σ : Type} [TypeName σ]

/-- The state in `d`, or the initial state if `d` holds another type. -/
def state (s : Widget.Spec Msg σ) (d : Dynamic) : σ := (d.get? σ).getD s.init

def build (s : Widget.Spec Msg σ) : Widget Msg where
  kind := s.kind
  init := Dynamic.mk s.init
  merge := fun d => Dynamic.mk (((d.get? σ).map s.merge).getD s.init)
  sizeReq := fun env d => s.sizeReq env (s.state d)
  content := fun env d v r => s.content env (s.state d) v r
  render := fun env d v => s.render env (s.state d) v
  render_within := fun env d v => s.render_within env (s.state d) v
  handle := fun env d v e =>
    (s.handle env (s.state d) v e).map fun (st, reqs) => (Dynamic.mk st, reqs)
  focusable := s.focusable
  dispose := fun d => s.dispose (s.state d)
  access := fun env d => s.access env (s.state d)
  every := s.every.map fun f env d => f env (s.state d)
  moving := s.moving.map fun f env d => f env (s.state d)
  mapChildren := fun env d => s.mapChildren env (s.state d)
  cursor := fun env d => s.cursor env (s.state d)
  heightFor := s.heightFor.map fun f env d => f env (s.state d)

end Widget.Spec

/-- The widget with its messages mapped by `f`, as a component's widgets are mapped into its
parent's messages. -/
def Widget.mapMsg {α β : Type} (f : α → β) (w : Widget α) : Widget β where
  kind := w.kind
  init := w.init
  merge := w.merge
  sizeReq := w.sizeReq
  content := w.content
  render := w.render
  render_within := w.render_within
  handle := fun env st v e => (w.handle env st v e).map fun (st, rs) => (st, rs.map (Req.map f))
  focusable := w.focusable
  dispose := fun st => (w.dispose st).map (Req.map f)
  access := w.access
  every := w.every
  moving := w.moving
  mapChildren := w.mapChildren
  cursor := w.cursor
  heightFor := w.heightFor

/-- A widget that only holds children: it draws nothing and asks for nothing itself. -/
def Widget.container {Msg : Type} (kind : String) : Widget Msg :=
  Widget.Spec.build (σ := NoState)
    { kind, init := {}, sizeReq := fun _ _ => ({}, {}), render := fun _ _ _ => Scene.empty
      render_within := fun _ _ v => Scene.empty_within v }

end Paw
