/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Scene
import Paw.Layout
import Paw.Event

/-! # Widgets

A widget is a record of functions over its own state, as in monomer, with the law that what it
draws lies within the box it is given. Unlike monomer's, these functions never see the widget tree:
the tree is walked by `Paw.Tree`, which merges, lays out and draws children itself, so a widget
cannot draw or act on anything but its own box and state. -/

namespace Paw

/-- The state of a widget that keeps none. -/
structure NoState where
  deriving TypeName, Repr, Inhabited

structure WidgetId where
  n : Nat
  deriving Repr, DecidableEq, Hashable, Ord, Inhabited

structure Theme where
  text : Color := Color.rgb 0x20 0x20 0x20
  background : Color := Color.rgb 0xF4 0xF4 0xF4
  surface : Color := Color.white
  accent : Color := Color.rgb 0x2A 0x6F 0xDB
  border : Color := Color.rgb 0xB0 0xB0 0xB0
  fontSize : Int := px 14
  deriving Repr, Inhabited

/-- What widgets know of the world. -/
structure Env where
  /-- The width and height of a line of text, from the Rust layer or a mock. -/
  measure : TextStyle → SafeText → Int × Int
  /-- Milliseconds since the app started. -/
  now : Nat := 0
  theme : Theme := {}
  focused : Option WidgetId := none
  hovered : Option WidgetId := none
  pressed : Option WidgetId := none
  /-- The widget being asked, which the tree sets. -/
  self : WidgetId := ⟨0⟩
  /-- The rectangle the widget's children are laid out in, which the tree sets. -/
  content : Rect := default

/-- Text measured as monomer's tests measure it: 10 pixels a character, 20 pixels a line. -/
def Env.mock : Env := { measure := fun _ t => (px (t.text.length * 10), px 20) }

namespace Env

def isFocused (env : Env) : Bool := env.focused == some env.self
def isHovered (env : Env) : Bool := env.hovered == some env.self
def isPressed (env : Env) : Bool := env.pressed == some env.self

end Env

/-- What a widget asks of the runtime. -/
inductive Req (Msg : Type) where
  /-- A message for the app's `update`. -/
  | emit (m : Msg)
  /-- Keyboard focus to the widget. -/
  | focus (id : WidgetId)
  | render
  /-- Write the clipboard. The runtime does it only for input that designated the widget. -/
  | copy (t : SafeText)
  deriving Repr, DecidableEq

def Req.map {α β : Type} (f : α → β) : Req α → Req β
  | .emit m => .emit (f m)
  | .focus id => .focus id
  | .render => .render
  | .copy t => .copy t

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

/-- A widget that only holds children: it draws nothing and asks for nothing itself. -/
def Widget.container {Msg : Type} (kind : String) : Widget Msg :=
  Widget.Spec.build (σ := NoState)
    { kind, init := {}, sizeReq := fun _ _ => ({}, {}), render := fun _ _ _ => Scene.empty
      render_within := fun _ _ v => Scene.empty_within v }

end Paw
