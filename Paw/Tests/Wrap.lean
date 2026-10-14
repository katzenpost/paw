/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Ui
import Paw.Tests.Util

/-! # Wrapping text

Lines broken to a width, with the laws checked on random text as well as proved; text blocks with
at most so many lines and an ellipsis; and layouts that ask a paragraph its height once its width
is known. -/

namespace Paw.Tests.Wrap

open Paw Paw.Wrap

/-- Ten units a character, as `Env.mock` measures. -/
def m (cs : List Char) : Int := cs.length * 10
def cw (_ : Char) : Int := 10

def wrapS (w : Int) (s : String) : List String := (wrap w m cw s.toList).map String.ofList

def randomText (g : Rng) : String × Rng := Id.run do
  let (n, g) := g.next 40
  let mut g := g
  let mut s := ""
  for _ in [0:n] do
    let (k, g') := g.next 8
    g := g'
    s := s.push (if k < 2 then ' ' else Char.ofNat (97 + k))
  return (s, g)

def view (body : String) (width : Int) : Node Unit :=
  Ui.width width (Ui.col [Ui.paragraph body, Ui.label "end" "end"])

def env : Env := Env.mock

def placed (n : Node Unit) (h : Int := px 400) : Node Unit :=
  (n.init 1).1.resize env (Rect.ofXYWH 0 0 (px 400) h)

def tests : TestM Unit := do
  checkEq "words that fit stay on one line" ["the quick fox"] (wrapS 200 "the quick fox")
  checkEq "a line breaks after the space before the word that does not fit"
    ["the quick ", "brown fox ", "jumps"] (wrapS 100 "the quick brown fox jumps")
  checkEq "a word too long for any line is cut by characters" ["abcde", "fghij", "klm"] (wrapS 50 "abcdefghijklm")
  checkEq "and its spaces stay with its last run" ["abcde", "fg  ", "hi"] (wrapS 50 "abcdefg  hi")
  checkEq "spaces at the start are kept" ["  ab ", "cd"] (wrapS 40 "  ab cd")
  checkEq "spaces at a line's end hang past it" ["abcd   ", "e"] (wrapS 40 "abcd   e")
  checkEq "a width of nothing gives a character a line" ["a", "b", "c"] (wrapS 0 "abc")
  checkEq "nothing gives nothing" [] (wrapS 100 "")
  -- The laws, on random text at random widths.
  let mut g : Rng := ⟨7⟩
  let mut joins := true
  let mut fits := true
  for _ in [0:300] do
    let (s, g') := randomText g
    let (w, g'') := g'.next 120
    g := g''
    let cs := s.toList
    if (wrap w m cw cs).flatten != cs then joins := false
    for l in lines w m cw cs do
      if !(lineWidth Piece.core Piece.full l ≤ w || l.length == 1 && (l.head?.any (·.word.length ≤ 1))) then
        fits := false
  check "the lines put back together are the text" joins
  check "every line fits, or is a single character" fits
  let ps : List Piece := [⟨[], [], 3, 5⟩, ⟨[], [], 7, 9⟩]
  checkEq "a line's width: each piece in full but the last" (fullSum Piece.full ps.dropLast + 7)
    (lineWidth Piece.core Piece.full ps)
  -- Text blocks.
  let block (cfg : Widgets.TextCfg) (w : Int) (s : String) : List String :=
    (cfg.layout env {} (px w) [SafeText.trusted s]).map (·.text)
  checkEq "at most two lines, the last cut short with an ellipsis"
    ["the quick ", "brown fox…"] (block { wrap := true, maxLines := some 2, overflow := .ellipsis } 100 "the quick brown fox jumps")
  checkEq "a line that fits keeps its end" ["short"] (block { overflow := .ellipsis } 100 "short")
  checkEq "one that does not is cut with an ellipsis" ["a long l…"] (block { overflow := .ellipsis } 90 "a long line")
  checkEq "clipped, it is left to the box" ["a long line"] (block {} 90 "a long line")
  checkEq "with no room, only the ellipsis" ["…"] (block { overflow := .ellipsis } 5 "words")
  -- Layout: a paragraph's height at the width it is given, in windows 500 and 100 pixels wide.
  let body := "one two three four five six seven eight nine ten"
  let inWindow (w : Int) (n : Node Unit) : Node Unit := (n.init 1).1.resize env (Rect.ofXYWH 0 0 (px w) (px 400))
  let page := Ui.col [Ui.paragraph body, Ui.label "end" "end"]
  let endAt (t : Node Unit) (k : String := "end") := ((t.findKey? k).map (·.viewport.y0)).get!
  checkEq "wide, the paragraph is one line" (px 24) (endAt (inWindow 500 page))
  let narrow := inWindow 100 page
  checkEq "narrow, it is as tall as its six lines, and what follows moves down" (px 124) (endAt narrow)
  let drawn := (narrow.render env).items.filterMap fun (_, d) => match d with
    | .text _ t _ => some t.text
    | _ => none
  checkEq "and draws them, the space after each hanging past the edge"
    ["one two ", "three four ", "five six ", "seven ", "eight nine ", "ten", "end"] drawn
  check "within its box" (decide ((narrow.render env).Within narrow.viewport))
  let inRow := inWindow 500 (Ui.col [Ui.row [Ui.width (px 100) (Ui.paragraph body), Ui.label "beside"],
    Ui.label "after" "after"])
  checkEq "in a row, a wrapped paragraph makes the row as tall as its lines" (px 124) (endAt inRow "after")
  let scrolled := inWindow 108 (Ui.col [Ui.height (px 60) (Ui.scroll (Ui.paragraph body) "s")])
  let content := ((scrolled.findKey? "s").map (·.info.content.height)).get!
  checkEq "in a scroll, the content is as tall as the wrapped lines" (px 120) content
  let tip := inWindow 500 (Ui.col [Ui.tooltip body (Ui.label "anchor")])
  checkEq "a tooltip is as wide as its text when there is room"
    (px 480 + px 8) ((tip.overlays.head?.map (·.viewport.width)).get!)

end Paw.Tests.Wrap
