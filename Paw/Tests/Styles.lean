/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util
import Paw.Tests.Rejects

/-! # Text weights and sizes, kinds of button, badges, surfaces and rich list rows

The gallery's Styles page: text of each tone and size, the four kinds of button, a badge, and a
sidebar on a surface whose rows are built from nodes, beside them across a split whose divider is
a line. -/

namespace Paw.Tests.Styles

open Paw

abbrev App := _root_.Gallery.app

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1

def box (rt : Runtime App) (k : String) : Rect := ((rt.tree.findKey? k).map (·.viewport)).getD default

def mid (r : Rect) : Point := ⟨(r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2⟩

def click (rt : Runtime App) (k : String) (t : Nat) : Runtime App :=
  step (step rt (.press (mid (box rt k)) .primary) t) (.release (mid (box rt k)) .primary) (t + 50)

/-- What the widget keyed `k` draws, itself and everything in it. -/
def drawn (rt : Runtime App) (k : String) : List Draw :=
  ((rt.tree.findKey? k).map fun n => (n.render rt.env).items.map (·.2)).getD []

def texts (ds : List Draw) : List (String × TextStyle) :=
  ds.filterMap fun | .text _ t st => some (t.text, st) | _ => none

def fills (ds : List Draw) : List Color := ds.filterMap fun | .fill _ c _ => some c | _ => none

def strokes (ds : List Draw) : Nat := (ds.filter fun | .stroke .. => true | _ => false).length

def styles : Runtime App :=
  let rt := (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1
  click rt "tab-Styles" 100

def tests : TestM Unit := do
  let t := Theme.light
  -- Tones and sizes come from the theme.
  checkEq "normal text is the theme's text" t.text (Widgets.TextTone.normal.color t)
  checkEq "muted text is the theme's muted" t.muted (Widgets.TextTone.muted.color t)
  checkEq "an error is the theme's error" t.error (Widgets.TextTone.error.color t)
  checkEq "a caption is the caption size" t.captionSize (Widgets.TextSize.caption.size t)
  checkEq "body text is the font size" t.fontSize (Widgets.TextSize.body.size t)
  checkEq "a heading is the heading size" t.headingSize (Widgets.TextSize.heading.size t)
  checkEq "a title is the title size" t.titleSize (Widgets.TextSize.title.size t)
  checkEq "an ordinary button has the button style" t.button (Widgets.ButtonKind.normal.style t)
  checkEq "a main button has its own" t.mainButton (Widgets.ButtonKind.main.style t)
  checkEq "so does a flat one" t.flatButton (Widgets.ButtonKind.flat.style t)
  checkEq "and a destructive one" t.destructiveButton (Widgets.ButtonKind.destructive.style t)
  check "a theme whose chosen row hides muted text is not readable" (!Rejects.mutedOnSelection.readable)
  check "nor one whose flat button's caption is faint" (!Rejects.faintFlat.readable)
  let rt := styles
  let only (k : String) := texts (drawn rt k)
  check "a title is bold at the title size" ((only "titleText").all fun (_, st) => st.bold && st.size == t.titleSize)
  check "a heading is bold at the heading size" ((only "headingText").all fun (_, st) => st.bold && st.size == t.headingSize)
  check "body text is the theme's text at its size" ((only "bodyText").all fun (_, st) =>
    !st.bold && st.size == t.fontSize && st.color == t.text)
  check "a caption is muted and small" ((only "captionText").all fun (_, st) => st.color == t.muted && st.size == t.captionSize)
  check "an error is in the error color" ((only "errorText").all fun (_, st) => st.color == t.error)
  check "the page has text" !(only "titleText").isEmpty
  -- Buttons.
  check "a main button is filled with the accent" ((fills (drawn rt "mainButton")).contains t.mainButton.basic.bg)
  check "a flat button at rest draws no frame" ((fills (drawn rt "flatButton")).isEmpty && strokes (drawn rt "flatButton") == 0)
  let off := (Ui.pad (px 8) (Ui.enabled false (Ui.flatButton "Off" ())) : Node Unit)
  let offTree := (off.init 1).1.resize Env.mock (Rect.ofXYWH 0 0 (px 200) (px 60))
  check "disabled, it draws none either" ((offTree.render Env.mock).items.all fun
    | (_, .stroke ..) | (_, .fill ..) => false
    | _ => true)
  let hov := step rt (.move (mid (box rt "flatButton"))) 1000
  check "hovered, it does" (strokes (drawn hov "flatButton") == 1)
  check "a destructive button's caption is in its color" ((texts (drawn rt "destructiveButton")).all fun (_, st) =>
    st.color == t.destructiveButton.basic.fg)
  -- The badge.
  let b := box rt "badge"
  check "a badge is a pill at least as wide as it is tall" (b.width ≥ b.height && b.height > 0)
  check "filled with the badge color" ((fills (drawn rt "badge")).contains t.badgeBg)
  check "its count in the badge's text color" ((texts (drawn rt "badge")).all fun (s, st) => s == "7" && st.color == t.badgeFg)
  check "drawn within its box" ((rt.tree.findKey? "badge").all fun n => decide ((n.render rt.env).Within n.viewport))
  checkEq "and told as its count" (some "7 unread")
    (((rt.tree.findKey? "badge").bind fun n => (rt.tree.accessTree rt.env).find? (·.id == n.id.n)).map (·.access.name.text))
  -- The surface and the list on it.
  check "a sidebar is filled with the surface color" ((rt.tree.render rt.env).items.any fun
    | (_, .fill r c _) => c == t.surface && r.width > px 100
    | _ => false)
  check "the chosen row is on the selection color" ((fills (drawn rt "room-general")).contains t.selection)
  check "another is not" !((fills (drawn rt "room-design")).contains t.selection)
  check "a row holds its badge" ((texts (drawn rt "room-releases")).any (·.1 == "12"))
  check "a list in a sidebar draws no frame unfocused" (strokes (drawn rt "rooms") == 0)
  let rt2 := click rt "room-design" 2000
  checkEq "a click on a row chooses it" "design" rt2.model.room
  let listId := ((rt2.tree.findKey? "rooms").map (·.id)).getD ⟨0⟩
  let rt2 := (rt2.step (.access listId .focus) 2600).1
  check "focused, the list shows it" (strokes (drawn rt2 "rooms") ≥ 1)
  let rt3 := step rt2 (.key .down {} true) 3200
  checkEq "Down chooses the next" "releases" rt3.model.room
  let rh := (box rt "room-general").height
  checkEq "a row is a select list's row height" (Widgets.rowHeight rt.env) rh
  -- The split's line and grip.
  let s := box rt "styleSplit"
  let lines := (drawn rt "styleSplit").filter fun | .fill r c _ => c == t.divider && r.height == s.height && r.width == px 1 | _ => false
  checkEq "a split draws a line its whole height" 1 lines.length
  let grips (ds : List Draw) := (ds.filter fun | .fill r _ _ => r.height == px 24 && r.width == px 2 | _ => false).length
  checkEq "and no grip at rest" 0 (grips (drawn rt "styleSplit"))
  let d := Widgets.dividerRect false rt.model.styleShare s
  checkEq "a grip while hovered" 1 (grips (drawn (step rt (.move (mid d)) 4000) "styleSplit"))
  -- A separator with an inset, in the divider's color.
  check "a separator is drawn in the divider color, inset" ((rt.tree.render rt.env).items.any fun
    | (_, .fill r c _) => c == t.divider && r.height == px 1 && r.width + 2 * px 12 ≤ s.width
    | _ => false)
  -- A filler takes the room both ways.
  let f := (Ui.col [Ui.filler, Ui.label "x"] : Node Unit)
  let tree := (f.init 1).1.resize Env.mock (Rect.ofXYWH 0 0 (px 200) (px 200))
  check "a filler takes the room left over" (tree.children.head?.any fun n => n.viewport.height > px 100 && n.viewport.width == px 200)

end Paw.Tests.Styles
