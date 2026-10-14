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

/-- Text measured as monomer's tests measure it: 10 pixels a character, 20 pixels a line. -/
def Env.mock : Env := { measure := fun _ t => (px (t.text.length * 10), px 20) }

/-- What a widget asks of the runtime. -/
inductive Req (Msg : Type) where
  /-- A message for the app's `update`. -/
  | emit (m : Msg)
  /-- Keyboard focus to the widget. -/
  | focus (id : WidgetId)
  | render
  deriving Repr, DecidableEq

structure Widget (Msg : Type) where
  /-- Widgets merge only with widgets of the same kind. -/
  kind : String
  State : Type
  [stateName : TypeName State]
  init : State
  /-- The state to keep, given the state of the widget this one replaces on a rebuild. -/
  merge : State → State := id
  sizeReq : Env → State → SizeReq × SizeReq
  render : Env → State → Rect → Scene
  render_within : ∀ env st v, (render env st v).Within v
  handle : Env → State → Rect → Event → Option (State × List (Req Msg)) := fun _ _ _ _ => none
  focusable : Bool := false
  /-- Requests when the widget leaves the tree. -/
  dispose : State → List (Req Msg) := fun _ => []

attribute [instance] Widget.stateName

/-- A widget that only holds children: it draws nothing and asks for nothing itself. -/
def Widget.container {Msg : Type} (kind : String) : Widget Msg where
  kind
  State := NoState
  init := {}
  sizeReq := fun _ _ => ({}, {})
  render := fun _ _ _ => Scene.empty
  render_within := fun _ _ v => Scene.empty_within v

end Paw
