/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Geometry
import Paw.Text

/-! # Input events

Events as widgets receive them, in the window's coordinates. -/

namespace Paw

inductive MouseButton where
  | primary
  | secondary
  | middle
  deriving Repr, DecidableEq, Inhabited

inductive Key where
  | char (c : Char)
  | enter
  | escape
  | backspace
  | tab
  | delete
  | left
  | right
  | up
  | down
  | home
  | end_
  | pageUp
  | pageDown
  /-- The function key Fn. -/
  | f (n : Nat)
  deriving Repr, DecidableEq, Inhabited

structure Mods where
  shift : Bool := false
  ctrl : Bool := false
  alt : Bool := false
  super : Bool := false
  deriving Repr, DecidableEq, Inhabited

inductive Event where
  | press (p : Point) (b : MouseButton)
  | release (p : Point) (b : MouseButton)
  /-- A press and a release on the same widget; `count` is 2 for a double click. -/
  | click (p : Point) (b : MouseButton) (count : Nat)
  | move (p : Point)
  | enter (p : Point)
  | leave (p : Point)
  | wheel (p : Point) (dx dy : Int)
  | key (k : Key) (m : Mods) (pressed : Bool)
  /-- Text typed, after the input method has composed it. -/
  | text (s : String)
  | paste (s : String)
  /-- Text an input method is composing, not yet typed, with its cursor; empty when it ends. -/
  | preedit (t : SafeText) (cursor : Nat)
  | focus
  | blur
  /-- Time, in milliseconds since the app started, for widgets that asked for it. -/
  | tick (now : Nat)
  /-- A press outside the open overlay this widget is: the user dismissed it. -/
  | dismiss
  /-- What was dragged is dropped here, at the point; `Env.dragged` holds it. -/
  | drop (p : Point)
  deriving Repr, DecidableEq, Inhabited

end Paw
