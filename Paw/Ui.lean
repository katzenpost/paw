/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tree
import Paw.Widgets.Basic
import Paw.Widgets.TextField
import Paw.Widgets.TextArea
import Paw.Widgets.Scroll
import Paw.Widgets.Overlay
import Paw.Widgets.Anim
import Paw.Widgets.Image

/-! # Building views

Functions that build nodes, for writing an app's `view`. A string the app wrote is shown with
`label`; text from elsewhere with `text`, which takes it already filtered. -/

namespace Paw.Ui

open Widgets

variable {Msg : Type}

/-- The text block for one line: wrapped to more lines up to `maxLines`, the last cut short by
`overflow`. -/
def lineCfg (overflow : TextOverflow) (maxLines : Nat) : TextCfg :=
  { wrap := maxLines > 1, maxLines := some maxLines, overflow }

/-- The app's own words: one line, or wrapped to up to `maxLines`, cut at the edge or with an
ellipsis. -/
def label (s : String) (key : Option String := none) (overflow : TextOverflow := .clip)
    (maxLines : Nat := 1) : Node Msg :=
  Node.leaf (Widgets.textBlock [SafeText.trusted s] (lineCfg overflow maxLines)) key

/-- Text from elsewhere, filtered, laid out as `label` lays out the app's. -/
def text (t : SafeText) (key : Option String := none) (overflow : TextOverflow := .clip)
    (maxLines : Nat := 1) : Node Msg :=
  Node.leaf (Widgets.textBlock [t] (lineCfg overflow maxLines)) key

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

/-- Text of many lines, wrapped to the area's width. -/
def textArea (value : String) (onChange : String → Msg) (cfg : TextAreaCfg := {})
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.textArea value onChange cfg) key

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

/-- `view arg`, built only when `arg` differs from the argument of what is on screen there; how a
long list avoids rebuilding rows that did not change. -/
def lazy {α : Type} [BEq α] [TypeName α] (arg : α) (view : α → Node Msg)
    (key : Option String := none) : Node Msg :=
  Node.lazy arg view key

/-- The child, scrolled vertically. -/
def scroll (child : Node Msg) (key : Option String := none) : Node Msg :=
  Node.containerWith scrollWidget scrollLayout [child] key

/-- The child with key bindings. -/
def keystroke (bindings : List (KeyCombo × Msg)) (child : Node Msg) : Node Msg :=
  Node.containerWith (keystrokeWidget bindings) (box { expand := true }) [child]

/-- The child at `h` units high, whatever it asks for: how a scroll is given its height. -/
def height (h : Int) (child : Node Msg) : Node Msg :=
  Node.container (sizeLayout none (some h.toNat)) [child]

/-- The child at `w` units wide, whatever it asks for. -/
def width (w : Int) (child : Node Msg) : Node Msg :=
  Node.container (sizeLayout (some w.toNat) none) [child]

/-- The child with `p` units of space around it. -/
def pad (p : Int) (child : Node Msg) : Node Msg := Node.container (padLayout p) [child]

/-- `anchor`, and while `isOpen`, `content` in a popup below it, above everything else. The pointer
reaches only the popup while it is open; a press outside it or Escape emits `onDismiss`. Keys and
text still go to the focused widget. -/
def popup (isOpen : Bool) (anchor content : Node Msg) (onDismiss : Msg) (key : Option String := none) :
    Node Msg :=
  let pop := Node.containerWith (popupWidget onDismiss) (padLayout (px 4)) [content]
  Node.container (box { expand := true }) (anchor :: if isOpen then [pop.overlay .popup] else []) key

/-- `img`, fitted to its box by `fit`, described to assistive technology by `alt`, or marked as
decoration. -/
def image (img : Image) (alt : ImageAlt) (fit : ImageFit := .either) (key : Option String := none) :
    Node Msg :=
  Node.leaf (Widgets.image img alt fit) key

/-- An icon `size` units square. -/
def icon (k : Icon) (alt : ImageAlt := .decorative) (size : Int := px 16) (key : Option String := none) :
    Node Msg :=
  Node.leaf (Widgets.icon k alt size) key

/-- `child` and everything in it drawn with `theme`, on the theme's background: how a part of the
window, or all of it, switches theme. -/
def themed (theme : Theme) (child : Node Msg) : Node Msg :=
  (Node.containerWith backdrop (box { expand := true }) [child]).withInfo ({ · with theme := some theme })

/-- `child`, enabled only if `on`: a disabled widget takes no input or focus, and looks it. -/
def enabled (on : Bool) (child : Node Msg) : Node Msg := if on then child else child.disable

/-- `child` with `tip` shown below it once the pointer has rested on it for a second, or while
focus is in it. The tip takes no input. -/
def tooltip (tip : String) (child : Node Msg) : Node Msg :=
  let t := Node.containerWith tipPanel (padLayout (px 4)) [paragraph tip]
  Node.container (box { expand := true }) [child, t.overlay .tip]

/-- `child` faded in over `ms` when it appears. -/
def fadeIn (child : Node Msg) (ms : Nat := 250) : Node Msg :=
  Node.containerWith (Widgets.fadeIn ms) (box { expand := true }) [child]

/-- `child` slid in from `offset` over `ms` when it appears. -/
def slideIn (child : Node Msg) (offset : Point := ⟨0, px 16⟩) (ms : Nat := 250) : Node Msg :=
  Node.containerWith (Widgets.slideIn offset ms) (box { expand := true }) [child]

/-- `content` in a dialog named `title`, over the whole window, which it dims. It takes no room
where it is placed in the view. Nothing beneath it can be reached until it closes; Escape and Enter
emit `onDismiss`. It opens only with a token `Modal.open` made from the input being handled; one
that appears otherwise, as on a task's result, is never shown and is dismissed at once. -/
def dialog (m : Modal) (title : SafeName) (content : Node Msg) (onDismiss : Msg) : Node Msg :=
  let panel := Node.containerWith (dialogPanel title) (padLayout (px 12)) [content]
  (Node.containerWith (modalWidget m onDismiss) (box {}) [panel] (some "dialog")).overlay .modal

/-- A dialog with `body` and an OK button that, like Escape, emits `onClose`. -/
def alert (m : Modal) (title : SafeName) (body : String) (onClose : Msg) : Node Msg :=
  dialog m title (col [Node.leaf (Widgets.label title.toText (bold := true)), paragraph body,
    row [spacer, button "OK" onClose "ok"]] (px 8)) onClose

/-- A dialog asking to confirm `body`, which should say what happens, to whom, and whether it can
be undone. `cancel`, Escape and Enter emit `onCancel`; `accept` emits `onAccept` only when the user
chose it: a click on it within `stableMs` of the dialog appearing, a synthetic click or a press from
assistive technology is dropped. -/
def confirm (m : Modal) (title : SafeName) (body : String) (onAccept onCancel : Msg)
    (accept : String := "OK") (cancel : String := "Cancel") : Node Msg :=
  dialog m title (col [Node.leaf (Widgets.label title.toText (bold := true)), paragraph body,
    row [spacer, button cancel onCancel "cancel",
      Node.leaf (Widgets.button (SafeText.trusted accept) onAccept (designated := true)) "accept"]] (px 8))
    onCancel
