/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Runtime
import Paw.Ui
import Paw.Tests.Util
import Paw.Tests.Rejects

/-! # Styles and themes

Which state's style a widget takes, the contrast measure, the shipped themes, widgets drawn by
their styles, subtrees with themes of their own, and the pointer's shape. -/

namespace Paw.Tests.Style

open Paw

def c (n : UInt8) : Color := Color.rgb n n n

/-- A style whose states each set a different background, and focus a border. -/
def marked : Style := {
  basic := { bg := c 1, fg := c 0, border := c 9 }
  hover := { bg := some (c 2) }
  focus := { bg := some (c 3), border := some (c 8) }
  focusHover := { bg := some (c 4) }
  active := { bg := some (c 5) }
  disabled := { bg := some (c 6) } }

def bg (i : Interaction) : UInt8 := (marked.current i).bg.r

inductive Msg where
  | go
  | typed (s : String)
  deriving Repr, BEq, Inhabited

def view (dark : Bool) (_ : Nat) : Node Msg :=
  let body := Ui.col [Ui.textField "" .typed {} "field", Ui.button "Go" .go "go",
    Ui.enabled false (Ui.button "Off" .go "off"), Ui.label "words" "words",
    Ui.tooltip "tip" (Ui.button "Tip" .go "tipped")]
  if dark then Ui.themed Theme.dark body else body

def appOf (dark : Bool) : App [] :=
  { Model := Nat, Msg := Msg, init := 0, view := view dark
    update := fun _ m => match m with
      | .go => modify fun (n, cs) => (n + 1, cs)
      | .typed _ => pure () }

def startOf (dark : Bool) : Runtime (appOf dark) :=
  (Runtime.start (appOf dark) (Rect.ofXYWH 0 0 (px 300) (px 300)) 0 Env.mock.measure).1

def scene {app : App []} (rt : Runtime app) : Scene :=
  match rt.present with
  | .request (.present s) => s
  | _ => Scene.empty

/-- What is drawn inside the widget with key `k`. -/
def drawnIn {app : App []} (rt : Runtime app) (k : String) : List Draw :=
  match rt.tree.findKey? k with
  | some n => (scene rt).items.filterMap fun (r, d) => if r.Within n.viewport then some d else none
  | none => []

def fills (ds : List Draw) : List Color := ds.filterMap fun | .fill _ col _ => some col | _ => none
def strokes (ds : List Draw) : List (Color × Int) := ds.filterMap fun | .stroke _ col w _ => some (col, w) | _ => none
def textColors (ds : List Draw) : List Color := ds.filterMap fun | .text _ _ s => some s.color | _ => none

def center {app : App []} (rt : Runtime app) (k : String) : Point :=
  match rt.tree.findKey? k with
  | some n => ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
  | none => ⟨-1, -1⟩

def tests : TestM Unit := do
  -- Which state wins, as in monomer.
  checkEq "basic" 1 (bg {})
  checkEq "hover" 2 (bg { hovered := true })
  checkEq "focus" 3 (bg { focused := true })
  checkEq "focus with hover beats both" 4 (bg { focused := true, hovered := true })
  checkEq "active beats focus with hover" 5 (bg { focused := true, hovered := true, active := true })
  checkEq "disabled beats everything" 6 (bg { focused := true, hovered := true, active := true, disabled := true })
  checkEq "states lie over basic: focus's border stays under hover" (c 8)
    (marked.current { focused := true, hovered := true }).border
  checkEq "and under active, while focused" (c 8) (marked.current { focused := true, active := true }).border
  checkEq "but not when not focused" (c 9) (marked.current { active := true }).border
  checkEq "sixteen combinations of states" 16 Style.interactions.length
  -- The contrast measure.
  check "black on white is 21:1" (Contrast.atLeast 21 1 Color.black Color.white)
  check "and no more" (!Contrast.atLeast 22 1 Color.black Color.white)
  check "the same color is 1:1" (Contrast.atLeast 1 1 (c 0x80) (c 0x80) && !Contrast.atLeast 11 10 (c 0x80) (c 0x80))
  check "#767676 on white is readable (4.54:1)" (Contrast.readable (c 0x76) Color.white)
  check "#777777 on white is not (4.48:1)" (!Contrast.readable (c 0x77) Color.white)
  check "the order does not matter" (Contrast.atLeast 9 2 Color.white (c 0x76))
  check "translucent text is not counted readable" (!Contrast.readable (Color.rgba 0 0 0 200) Color.white)
  -- The shipped themes pass their laws, as their types say; the bad ones in Rejects do not.
  check "the light theme is readable" Theme.light.toThemeData.readable
  check "the dark theme is readable" Theme.dark.toThemeData.readable
  check "a theme with gray text is not" (!Rejects.unreadable.readable)
  check "a theme with no focus ring does not show focus" (!Rejects.noFocusRing.focusVisible)
  -- Widgets drawn by their styles.
  let rt := startOf false
  let t := Theme.light
  checkEq "a button's background, border and text are its style's"
    ([t.button.basic.bg], [(t.button.basic.border, t.button.basic.borderWidth)], [t.button.basic.fg])
    (fills (drawnIn rt "go"), strokes (drawnIn rt "go"), textColors (drawnIn rt "go"))
  let hovered := (rt.step (.input { kind := .move (center rt "go"), time := 100 }) 100).1
  checkEq "hovered, its hover background" [(t.button.current { hovered := true }).bg] (fills (drawnIn hovered "go"))
  checkEq "a disabled button has the disabled style" [(t.button.current { disabled := true }).bg]
    (fills (drawnIn rt "off"))
  let off := (rt.step (.input { kind := .press (center rt "off") .primary, time := 1000 }) 1000).1
  let off := (off.step (.input { kind := .release (center rt "off") .primary, time := 1020 }) 1020).1
  checkEq "and does nothing when clicked" (0 : Nat) (off.model : Nat)
  checkEq "and takes no focus" none off.router.focused
  let tabbed := (rt.step (.input { kind := .key .tab {} true, time := 1000 }) 1000).1
  let tabbed := (tabbed.step (.input { kind := .key .tab {} true, time := 1001 }) 1001).1
  checkEq "focused, the ring is the focus border" [((t.button.current { focused := true }).border, px 2)]
    (strokes (drawnIn tabbed "go"))
  -- A subtree with a theme of its own.
  let dark := startOf true
  let d := Theme.dark
  checkEq "in a dark subtree, the button is dark" [d.button.basic.bg] (fills (drawnIn dark "go"))
  checkEq "and a label's text" [d.text] (textColors (drawnIn dark "words"))
  check "its background is drawn" ((scene dark).items.any fun (_, x) => match x with
    | .fill r col _ => col == d.background && r == Rect.ofXYWH 0 0 (px 300) (px 300)
    | _ => false)
  let tip := ((dark.step (.input { kind := .move (center dark "tipped"), time := 100 }) 100).1.advance 1100).1
  check "an overlay in it is drawn dark too, though drawn apart from the tree"
    ((scene tip).items.any fun (_, x) => match x with | .fill _ col _ => col == d.surface | _ => false)
  -- The pointer's shape.
  let cursors (outs : List (Output Msg)) : List Cursor :=
    outs.filterMap fun | .request (.cursor k) => some k | _ => none
  let (r1, outs) := rt.step (.input { kind := .move (center rt "field"), time := 100 }) 100
  checkEq "over a text field, the text cursor" [Cursor.text] (cursors outs)
  let (r2, outs) := r1.step (.input { kind := .move (center rt "field" + ⟨1, 0⟩), time := 110 }) 110
  checkEq "asked for once" [] (cursors outs)
  let (_, outs) := r2.step (.input { kind := .move (center rt "go"), time := 120 }) 120
  checkEq "over a button, the default again" [Cursor.default] (cursors outs)

end Paw.Tests.Style
