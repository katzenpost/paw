/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widget
import Paw.Wrap
import Std.Data.HashMap

/-! # Labels, buttons and checkboxes

Each widget draws with `Scene.inBox`, every item clipped to its box, so its law is
`Scene.inBox_within`. Controls look as the theme's style for their kind says, in the state they
are in. Text is `SafeText`: the app's own strings through `SafeText.trusted`, text
from elsewhere through `SafeText.filter`. -/

namespace Paw.Widgets

open SizeReq

/-- The space between a checkbox and its caption. -/
def captionGap : Int := px 8

def textStyle (env : Env) : TextStyle := { size := env.theme.fontSize, color := env.theme.text }

/-- A control's box drawn as `s` says: its background, then its border. -/
def frame (v : Rect) (s : StyleState) : List Draw :=
  [.fill v s.bg s.radius, .stroke v s.border s.borderWidth s.radius]

/-- Text vertically centered in `v`, starting at `x`. -/
def centeredText (env : Env) (v : Rect) (x : Int) (t : SafeText) (style : TextStyle) : Draw :=
  let (_, h) := env.measure style t
  .text ⟨x, v.y0 + (v.height - h) / 2⟩ t style

/-- What a text does with what does not fit its box. -/
inductive TextOverflow where
  /-- Cut at the box's edge. -/
  | clip
  /-- Cut short with an ellipsis, drawn by Paw. -/
  | ellipsis
  deriving Repr, DecidableEq, Inhabited

/-- How a block of text is laid out. -/
structure TextCfg where
  bold : Bool := false
  /-- Wrap to the box's width. -/
  wrap : Bool := false
  /-- At most this many lines are shown. -/
  maxLines : Option Nat := none
  overflow : TextOverflow := .clip
  deriving Repr, DecidableEq, Inhabited

/-- Widths of words and of characters, each measured once. -/
structure Widths where
  words : Std.HashMap String Int
  chars : Std.HashMap Char Int

/-- The widths of every word and character in `lines`, in `style`. -/
def Widths.of (env : Env) (style : TextStyle) (lines : List SafeText) : Widths :=
  let width (s : String) := (env.measure style (SafeText.trusted s)).1
  lines.foldl (init := { words := {}, chars := {} }) fun acc l =>
    let cs := l.text.toList
    let chars := cs.foldl (fun m c => if m.contains c then m else m.insert c (width c.toString)) acc.chars
    let words := (Wrap.words cs).foldl (fun m (w, _) =>
      let k := String.ofList w
      if m.contains k then m else m.insert k (width k)) acc.words
    { words, chars }

def Widths.word (ws : Widths) (w : List Char) : Int := ws.words.getD (String.ofList w) 0
def Widths.char (ws : Widths) (c : Char) : Int := ws.chars.getD c 0

/-- The ellipsis Paw draws where it cuts text short. -/
def ellipsisChar : Char := '…'

/-- The longest start of `cs` that fits `room`, measured by `cw`. -/
def fitPrefix (cw : Char → Int) : Int → List Char → List Char
  | _, [] => []
  | room, c :: cs => if cw c ≤ room then c :: fitPrefix cw (room - cw c) cs else []

/-- `cs` cut short with an ellipsis to fit `width`, measured by `cw`, with no space before the
ellipsis: always if `more` was left out after it, else only if it does not fit. -/
def ellipsize (cw : Char → Int) (width : Int) (cs : List Char) (more : Bool := false) : List Char :=
  if !more && (cs.map cw).sum ≤ width then cs
  else ((fitPrefix cw (width - cw ellipsisChar) cs).reverse.dropWhile (· == ' ')).reverse ++ [ellipsisChar]

/-- The width of `t` on one line as wrapping measures it, so that a box this wide holds it on one
line. -/
def Widths.line (ws : Widths) (t : SafeText) : Int :=
  match Wrap.lines (2 ^ 40) ws.word ws.char t.text.toList with
  | [l] => Wrap.lineWidth Wrap.Piece.core Wrap.Piece.full l
  | _ => 0

/-- The lines a block of text shows in a box `width` wide: wrapped if it wraps, at most
`maxLines`, and with the last cut short by an ellipsis if text was left out and it asks. -/
def TextCfg.layout (cfg : TextCfg) (env : Env) (style : TextStyle) (width : Int) (lines : List SafeText) :
    List SafeText :=
  let ws := Widths.of env style (lines ++ [SafeText.trusted ellipsisChar.toString])
  let broken := if cfg.wrap then lines.flatMap fun l =>
      if l.text.isEmpty then [l]
      else (Wrap.wrap width ws.word ws.char l.text.toList).map (SafeText.trusted ∘ String.ofList)
    else lines
  let shown := match cfg.maxLines with
    | some n => broken.take n
    | none => broken
  let cut := shown.length < broken.length
  match cfg.overflow, shown.getLast? with
  | .ellipsis, some last =>
    shown.dropLast ++ [SafeText.trusted (String.ofList (ellipsize ws.char width last.text.toList cut))]
  | _, _ => shown

/-- The height of a line of text in `style`. -/
def lineHeight (env : Env) (style : TextStyle) : Int := (env.measure style (SafeText.trusted "M")).2

/-- Lines joined by spaces, as a screen reader reads a paragraph. -/
def joinLines (lines : List SafeText) : SafeText :=
  lines.foldl (fun acc l => if acc.text.isEmpty then l else acc ++ SafeText.trusted " " ++ l) SafeText.empty

/-- Lines of text, laid out by `cfg`. Wrapped, it asks for its natural width but takes less, and
its height at the width it is given. -/
def textBlock {Msg : Type} (lines : List SafeText) (cfg : TextCfg := {}) : Widget Msg :=
  let style (env : Env) : TextStyle := { textStyle env with bold := cfg.bold }
  let flexible := cfg.wrap || cfg.overflow == .ellipsis
  let height (env : Env) (n : Nat) : SizeReq := SizeReq.fixedSize (n * lineHeight env (style env)).toNat
  Widget.Spec.build (σ := NoState) {
    kind := "text"
    init := {}
    sizeReq := fun env _ =>
      let w := if cfg.wrap then
          let ws := Widths.of env (style env) lines
          lines.foldl (fun m t => max m (ws.line t)) 0
        else lines.foldl (fun m t => max m (env.measure (style env) t).1) 0
      let n := match cfg.maxLines with | some n => min n lines.length | none => lines.length
      (if flexible then maxSize w.toNat else fixedSize w.toNat, height env n)
    heightFor := if cfg.wrap then some fun env _ width => height env (cfg.layout env (style env) width lines).length
      else none
    render := fun env _ v =>
      let st := style env
      let shown := cfg.layout env st v.width lines
      let lh := lineHeight env st
      -- One line is centered in its box, as a label is; more go from the top.
      let items := match shown with
        | [t] => [centeredText env v v.x0 t st]
        | _ => shown.zipIdx.map fun (t, k) => Draw.text ⟨v.x0, v.y0 + k * lh⟩ t st
      Scene.inBox v items
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => some { role := .label, name := joinLines lines } }

/-- One line of text, in bold if `bold`. -/
def label {Msg : Type} (t : SafeText) (bold : Bool := false) : Widget Msg :=
  textBlock [t] { bold, maxLines := some 1 }

/-- Lines of text, one under another, each wrapped to the width given. -/
def paragraph {Msg : Type} (lines : List SafeText) : Widget Msg := textBlock lines { wrap := true }

/-- A button that emits `onClick` when clicked, or when Enter or Space is pressed on it; if
`designated`, only when that input designated it, as `Req.choose`. -/
def button {Msg : Type} (caption : SafeText) (onClick : Msg) (designated : Bool := false) : Widget Msg :=
  let act : Req Msg := if designated then .choose onClick else .emit onClick
  Widget.Spec.build (σ := NoState) {
    kind := "button"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      let (padX, padY) := env.theme.button.padding
      (fixedSize (w + 2 * padX).toNat, fixedSize (h + 2 * padY).toNat)
    render := fun env _ v =>
      let s := env.look env.theme.button
      let style := { textStyle env with color := s.fg }
      let (w, _) := env.measure style caption
      Scene.inBox v (frame v s ++ [centeredText env v (v.x0 + (v.width - w) / 2) caption style])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. => some (st, [act])
      | .key .enter _ true | .key (.char ' ') _ true => some (st, [act])
      | .enter _ | .leave _ | .press .. | .release .. | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    cursor := fun env _ => (env.look env.theme.button).cursor
    access := fun _ _ => some { role := .button, name := caption } }

/-- A checkbox showing `value`, which emits `onChange` with the other value when toggled. -/
def checkbox {Msg : Type} (caption : SafeText) (value : Bool) (onChange : Bool → Msg) :
    Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "checkbox"
    init := {}
    sizeReq := fun env _ =>
      let (w, h) := env.measure (textStyle env) caption
      (fixedSize (h + captionGap + w).toNat, fixedSize h.toNat)
    render := fun env _ v =>
      let t := env.theme
      let s := env.look t.checkbox
      -- The box is as tall as a line of the caption, centered in whatever height it is given.
      let side := min (env.measure (textStyle env) caption).2 v.height
      let boxR := Rect.ofXYWH v.x0 (v.y0 + (v.height - side) / 2) side side
      let mark := boxR.shrink (side / 4) (side / 4) (side / 4) (side / 4)
      -- The caption is on the window, not in the box: the window's text, or muted when disabled.
      let caption' := { textStyle env with color := if env.enabled then t.text else t.muted }
      Scene.inBox v (frame boxR s ++
        (if value then [.fill mark (if env.enabled then t.accent else s.fg) (px 2)] else []) ++
        [centeredText env v (v.x0 + side + captionGap) caption caption'])
    render_within := fun _ _ v => Scene.inBox_within v _
    handle := fun _ st _ e => match e with
      | .click .. | .key (.char ' ') _ true => some (st, [.emit (onChange !value)])
      | .enter _ | .leave _ | .focus | .blur => some (st, [])
      | _ => none
    focusable := true
    cursor := fun env _ => (env.look env.theme.checkbox).cursor
    access := fun _ _ => some { role := .checkBox, name := caption, checked := some value } }

/-- The theme's window background over its box: what holds a subtree with a theme of its own. -/
def backdrop {Msg : Type} : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "backdrop"
    init := {}
    sizeReq := fun _ _ => ({}, {})
    render := fun env _ v => Scene.inBox v [.fill v env.theme.background 0]
    render_within := fun _ _ v => Scene.inBox_within v _ }

/-- Empty space that takes the width left over, and no height: for pushing things apart in a
row. -/
def spacer {Msg : Type} : Widget Msg :=
  Widget.Spec.build (σ := NoState) {
    kind := "spacer"
    init := {}
    sizeReq := fun _ _ => (filler, {})
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v }

end Paw.Widgets
