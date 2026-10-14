/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tree
import Paw.Widgets.Basic
import Paw.Widgets.TextField
import Paw.Widgets.Scroll

/-! # Building views

Functions that build nodes, for writing an app's `view`. A string the app wrote is shown with
`label`; text from elsewhere with `text`, which takes it already filtered. -/

namespace Paw.Ui

open Widgets

variable {Msg : Type}

/-- The app's own words. -/
def label (s : String) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.label (SafeText.trusted s)) key

/-- Text from elsewhere, filtered. -/
def text (t : SafeText) (key : Option String := none) : Node Msg := Node.leaf (Widgets.label t) key

/-- Text from elsewhere, as its filtered lines. -/
def paragraph (s : String) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.paragraph (SafeText.lines s)) key

def button (caption : String) (onClick : Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) onClick) key

def checkbox (caption : String) (value : Bool) (onChange : Bool → Msg)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.checkbox (SafeText.trusted caption) value onChange) key

def textField (value : String) (onChange : String → Msg) (cfg : TextFieldCfg := {})
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.textField value onChange cfg) key

def passwordField (value : Secret) (onChange : Secret → Msg) (key : Option String := none) :
    Node Msg :=
  Node.leaf (Widgets.passwordField value onChange) key

def spacer : Node Msg := Node.leaf Widgets.spacer

/-- Children one above the other. -/
def col (children : List (Node Msg)) (spacing : Int := px 4) (key : Option String := none) :
    Node Msg :=
  Node.container (vstack spacing).toLayout children key

/-- Children side by side. -/
def row (children : List (Node Msg)) (spacing : Int := px 4) (key : Option String := none) :
    Node Msg :=
  Node.container (hstack spacing).toLayout children key

/-- One child per item, keyed by `key` so that each keeps its state when the list changes. -/
def list {α : Type} (items : List α) (key : α → String) (view : α → Node Msg)
    (spacing : Int := px 4) : Node Msg :=
  col (items.map fun a => (view a).withInfo ({ · with key := some (key a) })) spacing

/-- The child, scrolled vertically. -/
def scroll (child : Node Msg) (key : Option String := none) : Node Msg :=
  Node.containerWith scrollWidget scrollLayout [child] key

/-- The child with key bindings. -/
def keystroke (bindings : List (KeyCombo × Msg)) (child : Node Msg) : Node Msg :=
  Node.containerWith (keystrokeWidget bindings) (box { expand := true }) [child]

/-- The child with `p` units of space around it. -/
def pad (p : Int) (child : Node Msg) : Node Msg := Node.container (padLayout p) [child]

end Paw.Ui
