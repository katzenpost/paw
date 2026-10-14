/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Scene

/-! # Styles and themes

A widget's look in each state it can be in, as in monomer: a basic style, and what hover, focus,
focus with hover, press and being disabled change in it. `Style.current` picks the state with
monomer's priority: disabled, then active, then focus with hover, then hover, then focus.

A `Theme` holds a style for each kind of widget, and carries two laws, decided when the theme is
written:

- `contrast_ok`: every text is readable on what it is drawn on, in every state, by WCAG's
  measure: a contrast of at least 4.5:1. Control borders have at least 3:1 against the window, so
  a control's edge can be seen.
- `focus_visible`: a focused control's border differs from its unfocused one, is at least two
  pixels wide, and has at least 3:1 contrast against the window, so the user can always see where
  the keyboard is.

Contrast is computed exactly, without real numbers: a table gives each sRGB channel value its
linear light in millionths, and the ratio is compared by cross-multiplying. So `decide` checks a
theme, and a theme with unreadable text does not compile. -/

namespace Paw

/-- The pointer's shape over a widget. -/
inductive Cursor where
  | default
  | pointer
  | text
  | resizeH
  | resizeV
  deriving Repr, DecidableEq, Inhabited

/-- How a widget looks in one state. -/
structure StyleState where
  bg : Color
  fg : Color
  border : Color
  borderWidth : Int := px 1
  radius : Int := px 4
  cursor : Cursor := .default
  deriving Repr, DecidableEq, Inhabited

/-- What a state changes in the basic style. -/
structure StyleOver where
  bg : Option Color := none
  fg : Option Color := none
  border : Option Color := none
  borderWidth : Option Int := none
  deriving Repr, DecidableEq, Inhabited

/-- `s` with what `o` changes. -/
def StyleState.over (s : StyleState) (o : StyleOver) : StyleState :=
  { s with bg := o.bg.getD s.bg, fg := o.fg.getD s.fg, border := o.border.getD s.border,
           borderWidth := o.borderWidth.getD s.borderWidth }

/-- A widget's state, as styles see it. -/
structure Interaction where
  hovered : Bool := false
  focused : Bool := false
  /-- Pressed. -/
  active : Bool := false
  disabled : Bool := false
  deriving Repr, DecidableEq, Inhabited

/-- How a kind of widget looks: its padding, and its look in each state. -/
structure Style where
  /-- Horizontal and vertical space between the border and the content. -/
  padding : Int × Int := (px 8, px 4)
  basic : StyleState
  hover : StyleOver := {}
  focus : StyleOver := {}
  focusHover : StyleOver := {}
  active : StyleOver := {}
  disabled : StyleOver := {}
  deriving Repr, DecidableEq, Inhabited

namespace Style

/-- The look for `i`, with monomer's priority: disabled, then active, then focus with hover, then
hover, then focus; each laid over the basic style. -/
def current (s : Style) (i : Interaction) : StyleState :=
  if i.disabled then s.basic.over s.disabled
  else if i.active then
    ((if i.focused then s.basic.over s.focus else s.basic).over s.hover).over s.active
  else if i.hovered && i.focused then ((s.basic.over s.focus).over s.hover).over s.focusHover
  else if i.hovered then s.basic.over s.hover
  else if i.focused then s.basic.over s.focus
  else s.basic

/-- Every combination of states a widget can be in. -/
def interactions : List Interaction :=
  [false, true].flatMap fun h => [false, true].flatMap fun f => [false, true].flatMap fun a =>
    [false, true].map fun d => { hovered := h, focused := f, active := a, disabled := d }

/-- The look in every combination of states. -/
def states (s : Style) : List StyleState := interactions.map s.current

end Style

namespace Contrast

/-- The linear light of each sRGB channel value, in ten-millionths. -/
def linear : List Nat := [
  0, 3035, 6071, 9106, 12141, 15176, 18212, 21247, 24282, 27317, 30353, 33465,
  36765, 40247, 43914, 47770, 51815, 56054, 60488, 65121, 69954, 74990, 80232, 85681,
  91341, 97212, 103298, 109601, 116122, 122865, 129830, 137021, 144438, 152085, 159963, 168074,
  176420, 185002, 193824, 202886, 212190, 221739, 231534, 241576, 251869, 262412, 273209, 284260,
  295568, 307134, 318960, 331048, 343398, 356013, 368895, 382044, 395462, 409152, 423114, 437350,
  451862, 466651, 481718, 497066, 512695, 528606, 544803, 561285, 578054, 595112, 612461, 630100,
  648033, 666259, 684782, 703601, 722719, 742136, 761854, 781874, 802198, 822827, 843762, 865005,
  886556, 908417, 930590, 953075, 975873, 998987, 1022417, 1046165, 1070231, 1094617, 1119324, 1144354,
  1169707, 1195384, 1221388, 1247718, 1274377, 1301365, 1328683, 1356333, 1384316, 1412633, 1441285, 1470273,
  1499598, 1529262, 1559265, 1589608, 1620294, 1651322, 1682694, 1714411, 1746474, 1778884, 1811642, 1844750,
  1878208, 1912017, 1946178, 1980693, 2015563, 2050787, 2086369, 2122308, 2158605, 2195262, 2232280, 2269659,
  2307400, 2345506, 2383976, 2422811, 2462013, 2501583, 2541521, 2581829, 2622507, 2663556, 2704978, 2746773,
  2788943, 2831487, 2874408, 2917706, 2961383, 3005438, 3049873, 3094689, 3139887, 3185468, 3231432, 3277781,
  3324515, 3371636, 3419144, 3467041, 3515326, 3564001, 3613068, 3662526, 3712377, 3762621, 3813260, 3864294,
  3915725, 3967552, 4019778, 4072402, 4125426, 4178851, 4232677, 4286905, 4341536, 4396572, 4452012, 4507858,
  4564110, 4620770, 4677838, 4735315, 4793202, 4851499, 4910208, 4969330, 5028865, 5088813, 5149177, 5209956,
  5271151, 5332764, 5394795, 5457245, 5520114, 5583404, 5647115, 5711248, 5775804, 5840784, 5906188, 5972018,
  6038273, 6104956, 6172066, 6239604, 6307571, 6375969, 6444797, 6514056, 6583748, 6653873, 6724432, 6795425,
  6866853, 6938718, 7011019, 7083758, 7156935, 7230551, 7304607, 7379104, 7454042, 7529422, 7605245, 7681511,
  7758222, 7835378, 7912979, 7991027, 8069523, 8148466, 8227858, 8307699, 8387990, 8468732, 8549926, 8631572,
  8713671, 8796224, 8879231, 8962694, 9046612, 9130987, 9215819, 9301109, 9386857, 9473065, 9559734, 9646862,
  9734453, 9822506, 9911021, 10000000]

/-- Relative luminance, as WCAG defines it, in units of 10⁻¹¹. -/
def luminance (c : Color) : Nat :=
  2126 * linear.getD c.r.toNat 0 + 7152 * linear.getD c.g.toNat 0 + 722 * linear.getD c.b.toNat 0

/-- The contrast ratio of `a` and `b` is at least `num`/`den`: (L₁ + 0.05) / (L₂ + 0.05), with
the lighter on top, compared by cross-multiplying. -/
def atLeast (num den : Nat) (a b : Color) : Bool :=
  let la := luminance a + 5000000000
  let lb := luminance b + 5000000000
  let (hi, lo) := if la ≥ lb then (la, lb) else (lb, la)
  hi * den ≥ lo * num

/-- Text in `fg` on `bg` is readable: both opaque, and contrast at least 4.5:1. -/
def readable (fg bg : Color) : Bool := fg.a == 255 && bg.a == 255 && atLeast 9 2 fg bg

/-- `a` can be told from `b`, as a control's edge or a focus ring must be: at least 3:1. -/
def distinct (a b : Color) : Bool := atLeast 3 1 a b

end Contrast

/-- A theme's colors and styles, before its laws are checked. -/
structure ThemeData where
  /-- The window's background. -/
  background : Color
  /-- Panels: dialogs, popups, tooltips. -/
  surface : Color
  text : Color
  /-- Text of less weight, such as a field's placeholder. -/
  muted : Color
  /-- Checked marks, selections. -/
  accent : Color
  /-- Edges of panels and scroll bars. -/
  border : Color
  /-- What marks input that is not valid. -/
  error : Color
  /-- Links' text. -/
  link : Color
  fontSize : Int := px 14
  button : Style
  checkbox : Style
  textField : Style
  /-- A toggle, option button or tab, not chosen. -/
  toggle : Style
  /-- And chosen. -/
  toggleOn : Style
  deriving Repr, DecidableEq, Inhabited

namespace ThemeData

/-- The styles of widgets that take focus. -/
def controls (t : ThemeData) : List Style := [t.button, t.checkbox, t.textField, t.toggle, t.toggleOn]

/-- Every text is readable on what it is drawn on, and every control's edge can be seen. -/
def readable (t : ThemeData) : Bool :=
  Contrast.readable t.text t.background && Contrast.readable t.text t.surface &&
  Contrast.readable t.link t.background && Contrast.readable t.link t.surface &&
  Contrast.readable t.muted t.textField.basic.bg && Contrast.readable t.muted t.background &&
  Contrast.distinct t.accent t.checkbox.basic.bg &&
  Contrast.distinct t.error t.textField.basic.bg && Contrast.distinct t.error t.background &&
  t.controls.all fun s =>
    (s.states.all fun st => Contrast.readable st.fg st.bg) &&
    Style.interactions.all fun i => i.disabled || Contrast.distinct (s.current i).border t.background

/-- A focused control's border differs from its unfocused one, is at least 2 pixels wide, and
can be told from the window. -/
def focusVisible (t : ThemeData) : Bool :=
  t.controls.all fun s =>
    let f := s.current { focused := true }
    let fh := s.current { focused := true, hovered := true }
    f.border != s.basic.border && f.borderWidth ≥ px 2 && Contrast.distinct f.border t.background &&
    fh.border != (s.current { hovered := true }).border && fh.borderWidth ≥ px 2

end ThemeData

/-- A theme: colors and a style for each kind of widget, whose text is readable in every state and
whose focus can always be seen. -/
structure Theme extends ThemeData where
  contrast_ok : toThemeData.readable = true
  focus_visible : toThemeData.focusVisible = true

instance : Repr Theme := ⟨fun t n => reprPrec t.toThemeData n⟩

namespace Theme

def gray (v : UInt8) : Color := Color.rgb v v v

def lightData : ThemeData :=
  let control (cursor : Cursor) : Style := {
    basic := { bg := Color.white, fg := gray 0x20, border := gray 0x8A, cursor }
    hover := { bg := some (gray 0xF0) }
    focus := { border := some (Color.rgb 0x2A 0x6F 0xDB), borderWidth := some (px 2) }
    active := { bg := some (gray 0xE2) }
    disabled := { bg := some (gray 0xEB), fg := some (gray 0x5C), border := some (gray 0xC8) } }
  { background := gray 0xF4, surface := Color.white, text := gray 0x20, muted := gray 0x6B,
    accent := Color.rgb 0x2A 0x6F 0xDB, border := gray 0x8A, error := Color.rgb 0xC6 0x28 0x28,
    link := Color.rgb 0x1A 0x5B 0xC4,
    button := control .default, checkbox := { control .default with basic.radius := px 3 },
    textField := { control .text with basic.radius := px 3, hover := {}, active := {} }
    toggle := control .default
    toggleOn := {
      basic := { bg := Color.rgb 0xDC 0xE8 0xFB, fg := gray 0x20, border := Color.rgb 0x2A 0x6F 0xDB }
      hover := { bg := some (Color.rgb 0xCD 0xDE 0xF9) }
      focus := { border := some (Color.rgb 0x12 0x3A 0x80), borderWidth := some (px 2) }
      active := { bg := some (Color.rgb 0xBE 0xD4 0xF6) }
      disabled := { bg := some (gray 0xEB), fg := some (gray 0x5C), border := some (gray 0xC8) } } }

def darkData : ThemeData :=
  let control (cursor : Cursor) : Style := {
    basic := { bg := gray 0x2B, fg := gray 0xE6, border := gray 0x8A, cursor }
    hover := { bg := some (gray 0x33) }
    focus := { border := some (Color.rgb 0x6C 0xA0 0xFF), borderWidth := some (px 2) }
    active := { bg := some (gray 0x3A) }
    disabled := { bg := some (gray 0x26), fg := some (gray 0x9A), border := some (gray 0x40) } }
  { background := gray 0x1E, surface := gray 0x2B, text := gray 0xE6, muted := gray 0xA8,
    accent := Color.rgb 0x6C 0xA0 0xFF, border := gray 0x8A, error := Color.rgb 0xFF 0x6B 0x6B,
    link := Color.rgb 0x8A 0xB4 0xFF,
    button := control .default, checkbox := { control .default with basic.radius := px 3 },
    textField := { control .text with basic.radius := px 3, hover := {}, active := {} }
    toggle := control .default
    toggleOn := {
      basic := { bg := Color.rgb 0x24 0x40 0x6E, fg := gray 0xE6, border := Color.rgb 0x6C 0xA0 0xFF }
      hover := { bg := some (Color.rgb 0x2B 0x4B 0x80) }
      focus := { border := some (Color.rgb 0xC8 0xDC 0xFF), borderWidth := some (px 2) }
      active := { bg := some (Color.rgb 0x32 0x55 0x90) }
      disabled := { bg := some (gray 0x26), fg := some (gray 0x9A), border := some (gray 0x40) } } }

/-- Dark text on light grays. -/
def light : Theme := { lightData with contrast_ok := by decide +kernel, focus_visible := by decide +kernel }

/-- Light text on dark grays. -/
def dark : Theme := { darkData with contrast_ok := by decide +kernel, focus_visible := by decide +kernel }

instance : Inhabited Theme := ⟨light⟩

end Theme

end Paw
