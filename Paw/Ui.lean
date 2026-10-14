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
import Paw.Widgets.Choice
import Paw.Widgets.Input
import Paw.Widgets.Slider
import Paw.Widgets.List
import Paw.Widgets.Split
import Paw.Widgets.Link
import Paw.Widgets.Drag
import Paw.Widgets.Color
import Paw.Cmd

/-! # Building views

Functions that build nodes, for writing an app's `view`. A string the app wrote is shown with
`label`; text from elsewhere with `text`, which takes it already filtered. -/

namespace Paw.Ui

open Widgets

variable {Msg : Type}

/-- The text block for one line: wrapped to more lines up to `maxLines`, the last cut short by
`overflow`, in `bold`, `tone` and `size`. -/
def lineCfg (overflow : TextOverflow) (maxLines : Nat) (bold : Bool := false) (tone : TextTone := .normal)
    (size : TextSize := .body) : TextCfg :=
  { wrap := maxLines > 1, maxLines := some maxLines, overflow, bold, tone, size }

/-- The app's own words: one line, or wrapped to up to `maxLines`, cut at the edge or with an
ellipsis; in bold, of less weight (`tone := .muted`), or in another size if asked. -/
def label (s : String) (key : Option String := none) (overflow : TextOverflow := .clip)
    (maxLines : Nat := 1) (bold : Bool := false) (tone : TextTone := .normal) (size : TextSize := .body) :
    Node Msg :=
  Node.leaf (Widgets.textBlock [SafeText.trusted s] (lineCfg overflow maxLines bold tone size)) key

/-- Text from elsewhere, filtered, laid out as `label` lays out the app's. -/
def text (t : SafeText) (key : Option String := none) (overflow : TextOverflow := .clip)
    (maxLines : Nat := 1) (bold : Bool := false) (tone : TextTone := .normal) (size : TextSize := .body) :
    Node Msg :=
  Node.leaf (Widgets.textBlock [t] (lineCfg overflow maxLines bold tone size)) key

/-- A pane's or a group's title: the app's words, bold, at the theme's heading size. -/
def heading (s : String) (key : Option String := none) : Node Msg :=
  label s key (overflow := .ellipsis) (bold := true) (size := .heading)

/-- Small text of less weight, such as a time or a hint, from elsewhere and filtered. -/
def caption (t : SafeText) (key : Option String := none) (overflow : TextOverflow := .ellipsis) : Node Msg :=
  text t key overflow (tone := .muted) (size := .caption)

/-- Text from elsewhere, as its filtered lines. -/
def paragraph (s : String) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.paragraph (SafeText.lines s)) key

def button (caption : String) (onClick : Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) onClick) key

/-- The one action a view suggests, in the theme's accent, as monomer's `mainButton`. -/
def mainButton (caption : String) (onClick : Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) onClick (kind := .main)) key

/-- A secondary action: its caption alone until hovered, pressed or focused. -/
def flatButton (caption : String) (onClick : Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) onClick (kind := .flat)) key

/-- An action that deletes or cannot be undone, in the theme's error color. -/
def destructiveButton (caption : String) (onClick : Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) onClick (kind := .destructive)) key

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

/-- Empty space that takes the room left over both ways, as monomer's `filler`: for centering. -/
def filler : Node Msg := Node.leaf Widgets.filler

/-- `child` on the theme's panel color, with no frame: a sidebar, a header or a bar set apart from
the window. -/
def surface (child : Node Msg) (key : Option String := none) : Node Msg :=
  Node.containerWith Widgets.surface (box { expand := true }) [child] key

/-- A count in a pill, such as how many messages are unread. -/
def badge (n : Nat) (what : String := "unread") (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.badge n what) key

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

/-- The child, scrolled vertically, or along `axes`; with `follow`, kept at the end of its content
as it grows, unless scrolled back from it. -/
def scroll (child : Node Msg) (key : Option String := none) (axes : ScrollAxes := .vertical)
    (follow : Bool := false) : Node Msg :=
  Node.containerWith (scrollWidgetFor axes follow) (scrollLayoutFor axes) [child] key

/-- The child, scrolled across. -/
def hscroll (child : Node Msg) (key : Option String := none) : Node Msg := scroll child key .horizontal

/-- `first` and `second` side by side, or if `vertical` one above the other, sharing the room by
`ratio` thousandths for the first; dragging the divider between them asks for a new share. -/
def split (first second : Node Msg) (ratio : Nat) (onResize : Nat → Msg) (vertical : Bool := false)
    (key : Option String := none) : Node Msg :=
  Node.containerWith (splitWidget vertical ratio onResize) (splitLayout vertical ratio) [first, second] key

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

/-- A radio button for `value`, chosen when it is `current`. -/
def radio {α : Type} [BEq α] (caption : String) (value current : α) (onChange : α → Msg)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.radio (SafeText.trusted caption) value current onChange) key

/-- A button for `value`, pressed when it is `current`: one of a group. -/
def optionButton {α : Type} [BEq α] (caption : String) (value current : α) (onChange : α → Msg)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.optionButton (SafeText.trusted caption) value current onChange) key

/-- A button that stays pressed while `on`. -/
def toggleButton (caption : String) (on : Bool) (onChange : Bool → Msg) (key : Option String := none) :
    Node Msg :=
  Node.leaf (Widgets.toggleButton (SafeText.trusted caption) on onChange) key

/-- A field for a value of any type with a format: the model hears of it only when the text reads
as a value. -/
def inputField {α : Type} [BEq α] (fmt : Format α) (value : α) (onChange : α → Msg)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.inputField fmt value onChange) key

/-- An integer between `lo` and `hi`, typed, or stepped by Up, Down and the wheel. -/
def numericField {lo hi : Int} (value : { x : Int // lo ≤ x ∧ x ≤ hi })
    (onChange : { x : Int // lo ≤ x ∧ x ≤ hi } → Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.numericField value onChange) key

/-- A number with `places` decimal places, in units of `10 ^ -places`, between `lo` and `hi`. -/
def decimalField {lo hi : Int} (places : Nat) (hp : 1 ≤ places) (value : { x : Int // lo ≤ x ∧ x ≤ hi })
    (onChange : { x : Int // lo ≤ x ∧ x ≤ hi } → Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.decimalField places hp value onChange) key

def dateField (value : Format.Date) (onChange : Format.Date → Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.dateField value onChange) key

def timeField (value : Format.Time) (onChange : Format.Time → Msg) (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.timeField value onChange) key

/-- A slider from `lo` to `hi`, across. -/
def hslider {lo hi : Int} (value : Ranged lo hi) (onChange : Ranged lo hi → Msg) (step : Nat := 1)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.slider value onChange false step) key

/-- A slider from `lo` at the bottom to `hi` at the top. -/
def vslider {lo hi : Int} (value : Ranged lo hi) (onChange : Ranged lo hi → Msg) (step : Nat := 1)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.slider value onChange true step) key

/-- A dial from `lo` to `hi`, turned by dragging up or down. -/
def dial {lo hi : Int} (value : Ranged lo hi) (onChange : Ranged lo hi → Msg) (step : Nat := 1)
    (key : Option String := none) : Node Msg :=
  Node.leaf (Widgets.dial value onChange step) key

/-- What a row of a select list is built from, so that a row whose caption and choice are unchanged
is not built again. -/
structure ListRow where
  caption : String
  chosen : Bool
  deriving BEq, TypeName

/-- `items` in rows, `selected` chosen, in a box `rows` rows tall that scrolls; `extra` is asked
for too when one is clicked. -/
def selectListWith {α : Type} [BEq α] (items : List α) (selected : Option α) (onChange : α → Msg)
    (caption : α → String) (keyOf : α → String) (rows : Nat := 6) (extra : List Msg := [])
    (key : Option String := none) : Node Msg :=
  let arr := items.toArray
  let chosen := selected.bind fun s => arr.findIdx? (· == s)
  let pick (i : Nat) : List Msg := (arr[i]?.map fun a => [onChange a]).getD [] ++ extra
  let row (a : α) : Node Msg :=
    (Ui.lazy (ListRow.mk (caption a) (selected.any (· == a))) fun r =>
      Node.leaf (Widgets.listItem (SafeText.filter r.caption) r.chosen (onChange a :: extra))).withInfo
      ({ · with key := some (keyOf a) })
  Node.containerWith (selectListBox items.length chosen pick) (listLayout rows) (items.map row) key

/-- `items` in rows, `selected` chosen, in a box `rows` rows tall that scrolls, each row built by
`row` and read to assistive technology as `name`; `extra` is asked for too when one is clicked.
A row is one line of a select list's height. Unless `framed`, the box is drawn only while it has
focus, for a list in a sidebar. -/
def selectListOf {α : Type} [BEq α] (items : List α) (selected : Option α) (onChange : α → Msg)
    (row : α → Node Msg) (name : α → String) (keyOf : α → String) (rows : Nat := 6) (framed : Bool := true)
    (extra : List Msg := []) (key : Option String := none) : Node Msg :=
  let arr := items.toArray
  let chosen := selected.bind fun s => arr.findIdx? (· == s)
  let pick (i : Nat) : List Msg := (arr[i]?.map fun a => [onChange a]).getD [] ++ extra
  let rowNode (a : α) : Node Msg :=
    Node.containerWith (Widgets.listRow (SafeText.filter (name a)) (selected.any (· == a)) (onChange a :: extra))
      Widgets.listRowLayout [row a] (some (keyOf a))
  Node.containerWith (selectListBox items.length chosen pick framed) (listLayout rows) (items.map rowNode) key

/-- `items` in rows, `selected` chosen, in a box that scrolls. -/
def selectList {α : Type} [BEq α] (items : List α) (selected : Option α) (onChange : α → Msg)
    (caption : α → String) (keyOf : α → String) (rows : Nat := 6) (key : Option String := none) : Node Msg :=
  selectListWith items selected onChange caption keyOf rows [] key

/-- A button showing `selected`, which opens a select list of `items` below it while `isOpen`;
choosing one closes it. -/
def dropdown {α : Type} [BEq α] (items : List α) (selected : α) (onChange : α → Msg) (caption : α → String)
    (keyOf : α → String) (isOpen : Bool) (onOpen : Bool → Msg) (key : Option String := none) : Node Msg :=
  let arr := items.toArray
  let idx := (arr.findIdx? (· == selected)).getD 0
  let onStep (next : Bool) : List Msg :=
    let i := if next then idx + 1 else idx - 1
    (arr[i]?.map fun a => [onChange a]).getD []
  popup isOpen
    (Node.leaf (Widgets.dropdownButton (SafeText.filter (caption selected)) isOpen onOpen onStep) key)
    (selectListWith items (some selected) onChange caption keyOf (rows := min 6 items.length) (extra := [onOpen false]))
    (onOpen false)

/-- A dropdown of strings. -/
def textDropdown (items : List String) (selected : String) (onChange : String → Msg) (isOpen : Bool)
    (onOpen : Bool → Msg) (key : Option String := none) : Node Msg :=
  dropdown items selected onChange id id isOpen onOpen key

/-- A line across the box, or down it if `vertical`, leaving `inset` at each end. -/
def separator (vertical : Bool := false) (inset : Int := 0) : Node Msg :=
  Node.leaf (Widgets.separator vertical inset)

/-- Pages, one shown at a time, chosen by a row of tabs: each page is its caption, the value that
shows it, and the page. Pages not shown keep their state. -/
def tabs {α : Type} [BEq α] (current : α) (onChange : α → Msg) (pages : List (String × α × Node Msg))
    (key : Option String := none) : Node Msg :=
  let bar := Node.containerWith tabBar (hstack (px 2)).toLayout
    (pages.map fun (caption, a, _) => Node.leaf (Widgets.tab (SafeText.trusted caption) a current onChange) s!"tab-{caption}")
  let stack := Node.container zstack (pages.map fun (caption, a, page) =>
    -- Wrapped, so that the page keeps its own key.
    let page := Node.container (box { expand := true }) [page] (some s!"page-{caption}")
    if a == current then page else page.hide)
  col [bar, separator, stack] (px 2) key

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
    (accept : String := "OK") (cancel : String := "Cancel") (acceptKind : ButtonKind := .main) : Node Msg :=
  dialog m title (col [Node.leaf (Widgets.label title.toText (bold := true) (size := .heading)), paragraph body,
    row [spacer, button cancel onCancel "cancel",
      Node.leaf (Widgets.button (SafeText.trusted accept) onAccept (designated := true) (kind := acceptKind)) "accept"]
      (px 6)] (px 12))
    onCancel

/-- A link with `caption`, asking for `onOpen` when activated; the app opens it with
`Effect.openLink key link`, which needs the user's designation of this widget. Where it really goes,
its scheme and host, is shown in a tooltip on hover and focus, whatever the caption says. -/
def externalLink (caption : SafeText) (link : Link) (onOpen : Msg) (key : String) : Node Msg :=
  tooltip (Uri.destination link.uri) (Node.leaf (Widgets.link caption (SafeText.filter link.uri) onOpen) key)

/-- `child`, which can be dragged, giving `payload` to a drop target. -/
def draggable {α : Type} [TypeName α] (payload : α) (child : Node Msg) (key : Option String := none) : Node Msg :=
  Node.containerWith (Widgets.draggable payload) (box { expand := true }) [child] key

/-- `child`, on which values of type `α` can be dropped, each asking for `accept`. -/
def dropTarget {α : Type} [TypeName α] (accept : α → Msg) (child : Node Msg) (key : Option String := none) :
    Node Msg :=
  Node.containerWith (Widgets.dropTarget accept) (box { expand := true }) [child] key

/-- `child` with a shadow `depth` units deep around it, `radius` round: the shadow is drawn within
the room kept for it, never outside. -/
def boxShadow (child : Node Msg) (depth : Int := px 8) (radius : Int := px 6) : Node Msg :=
  Node.containerWith (Widgets.shadow depth radius) (padLayout depth) [child]

/-- A switch between themes: `child` with `theme`. -/
def themeSwitch (theme : Theme) (child : Node Msg) : Node Msg := themed theme child

/-- Sliders and fields for the red, green and blue of `value`, and its alpha if `alpha`, beside a
swatch of it. -/
def colorPicker (value : Color) (onChange : Color → Msg) (alpha : Bool := false) (key : Option String := none) :
    Node Msg :=
  let channel (name : String) (get : Color → UInt8) (set : Color → UInt8 → Color) : Node Msg :=
    let v : Widgets.Ranged 0 255 := ⟨(get value).toNat, by have := (get value).toNat_lt; omega⟩
    let to (x : Widgets.Ranged 0 255) : Msg := onChange (set value x.1.toNat.toUInt8)
    row [width (px 16) (label name), width (px 160) (hslider v to (key := s!"{name}Slider")),
      width (px 64) (numericField v to (key := s!"{name}Field"))]
  let channels := [channel "R" (·.r) fun c x => { c with r := x }, channel "G" (·.g) fun c x => { c with g := x },
    channel "B" (·.b) fun c x => { c with b := x }] ++
    (if alpha then [channel "A" (·.a) fun c x => { c with a := x }] else [])
  row [Node.leaf (Widgets.swatch value (size := px 48)), col channels (px 4)] (px 12) key

/-- A swatch of `value` that, clicked, opens a color picker below it while `isOpen`. -/
def colorPopup (value : Color) (onChange : Color → Msg) (isOpen : Bool) (onOpen : Bool → Msg)
    (alpha : Bool := false) (key : Option String := none) : Node Msg :=
  popup isOpen (Node.leaf (Widgets.swatch value (some (onOpen !isOpen))) key)
    (pad (px 8) (colorPicker value onChange alpha)) (onOpen false)

/-- `child` on a framed panel of the theme's surface. -/
def panel (child : Node Msg) (padding : Int := px 12) : Node Msg :=
  Node.containerWith tipPanel (padLayout padding) [child]
