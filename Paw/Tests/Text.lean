/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Text
import Paw.Tests.Util

/-! # Text from elsewhere

Random and known-hostile text, filtered: nothing forbidden survives, and what is refused shows. -/

namespace Paw.Tests.Text

open Paw Paw.Text

/-- A character that must never reach a text widget. -/
def forbidden (c : Char) : Bool :=
  let n := c.toNat
  n < 0x20 || (0x7F ≤ n && n < 0xA0) || n == 0x2028 || n == 0x2029 || n == 0xAD ||
    n == 0x200B || (0x2060 ≤ n && n ≤ 0x2064) || n == 0xFEFF || n == 0x180E ||
    (0xE0000 ≤ n && n ≤ 0xE007F) || (0xE000 ≤ n && n ≤ 0xF8FF) || 0xF0000 ≤ n ||
    (0xFDD0 ≤ n && n ≤ 0xFDEF) || n % 0x10000 ≥ 0xFFFE

/-- Additionally forbidden in a name. -/
def forbiddenInName (c : Char) : Bool :=
  let n := c.toNat
  forbidden c || (0x202A ≤ n && n ≤ 0x202E) || (0x2066 ≤ n && n ≤ 0x2069) || n == 0x200E ||
    n == 0x200F || n == 0x61C || n == 0x200C || n == 0x200D || (0xFE00 ≤ n && n ≤ 0xFE0F) ||
    (0x1F50F ≤ n && n ≤ 0x1F513) || n == 0x2611 || n == 0x2705 || n == 0x2713 || n == 0x2714 ||
    n == 0x1F6E1

def randomChar (g : Rng) : Char × Rng :=
  let (kind, g) := g.next 6
  let (n, g) := match kind with
    | 0 => g.next 0x40
    | 1 => let (n, g) := g.next 0x21; (0x7F + n, g)
    | 2 => let (n, g) := g.next 0x80; (0x2000 + n, g)
    | 3 => let (n, g) := g.next 0xB00; (0x1F000 + n, g)
    | 4 => let (n, g) := g.next 0x70; (0x300 + n, g)
    | _ => g.next 0x110000
  (Char.ofNat (if 0xD800 ≤ n && n ≤ 0xDFFF then 0x41 else n), g)

def randomString (g : Rng) (len : Nat) : String × Rng := Id.run do
  let mut g := g
  let mut s := ""
  for _ in [0:len] do
    let (c, g') := randomChar g
    s := s.push c
    g := g'
  return (s, g)

/-- Payloads that have attacked text displays. -/
def corpus : List (String × String) := [
  ("an escape sequence", "\x1b]52;c;ZXZpbA==\x07"),
  ("a one-byte CSI", "\u009b31mred"),
  ("a carriage return", "safe\rEVIL"),
  ("an RLO file-name spoof", "invoice‮fdp.exe"),
  ("Trojan Source", "access‮⁦ // admin⁩⁦"),
  ("ZWJ emoji", "👨‍👩‍👧"),
  ("VS16 emoji", "❤️ and 🚀"),
  ("Zalgo", "Z" ++ String.ofList (List.replicate 40 '́')),
  ("tag characters", "hi" ++ String.ofList [Char.ofNat 0xE0041, Char.ofNat 0xE0042]),
  ("a private-use glyph", " verified"),
  ("a line separator", "one two"),
  ("a soft hyphen", "pay­pal"),
  ("a zero-width space", "pay​pal"),
  ("a lock badge", "alice 🔒"),
  ("markup", "<b>bold</b> &amp;")]

def tests : TestM Unit := do
  -- Ordinary text passes through.
  checkEq "plain text" "hello, world" (SafeText.filter "hello, world").text
  checkEq "accents" "café naïve" (SafeText.filter "café naïve").text
  checkEq "CJK" "全角の文字" (SafeText.filter "全角の文字").text
  checkEq "Arabic keeps its marks" "سلام" (SafeText.filter "سلام").text
  checkEq "emoji" "🚀 ❤️" (SafeText.filter "🚀 ❤️").text
  checkEq "bidi controls stay in body text" "a⁧b⁩" (SafeText.filter "a⁧b⁩").text
  checkEq "markup is just text" "<b>x</b>" (SafeText.filter "<b>x</b>").text
  -- What is refused shows.
  checkEq "controls show as U+FFFD" "�]0;x�" (SafeText.filter "\x1b]0;x\x07").text
  checkEq "a newline in one line shows" "a�b" (SafeText.filter "a\nb").text
  checkEq "DEL shows" "a�b" (SafeText.filter "a\x7Fb").text
  checkEq "C1 shows" "�31m" (SafeText.filter "\u009b31m").text
  checkEq "a line separator shows" "one�two" (SafeText.filter "one two").text
  checkEq "marks are capped at four" ("e" ++ String.ofList (List.replicate 4 '́') ++ "�")
    (SafeText.filter ("e" ++ String.ofList (List.replicate 9 '́'))).text
  checkEq "a mark with no base shows" "�a" (SafeText.filter "́a").text
  checkEq "SafeText.trusted keeps its text" "x" (SafeText.trusted "x").text
  check "SafeText.trusted refuses forbidden text" (SafeText.trusted? "a\x1bb").isNone
  check "SafeText.trusted? accepts plain text" (SafeText.trusted? "ok").isSome
  checkEq "append" "ab" (SafeText.filter "a" ++ SafeText.filter "b").text
  checkEq "empty" "" (SafeText.empty).text
  check "equal texts" (SafeText.filter "a" == SafeText.trusted "a")
  check "different texts" (SafeText.filter "a" != SafeText.filter "b")
  check "equal names" (SafeName.filter "a" == SafeName.filter "a")
  check "different names" (SafeName.filter "a" != SafeName.filter "b")
  -- Lines.
  checkEq "lines split" ["one", "two"] ((SafeText.lines "one\ntwo").map (·.text))
  checkEq "CRLF" ["one", "two"] ((SafeText.lines "one\r\ntwo").map (·.text))
  checkEq "tabs become spaces" ["a    b"] ((SafeText.lines "a\tb").map (·.text))
  checkEq "lines are capped" 20 (SafeText.lines (String.intercalate "\n" (List.replicate 30 "x"))).length
  checkEq "the last line says how many more" "[11 more lines not shown]"
    ((SafeText.lines (String.intercalate "\n" (List.replicate 30 "x"))).getLast!.text)
  -- Names.
  checkEq "a plain name" "alice" (SafeName.filter "alice").text
  checkEq "bidi in a name shows" "invoice�fdp.exe" (SafeName.filter "invoice‮fdp.exe").text
  checkEq "a badge in a name shows" "alice �" (SafeName.filter "alice 🔒").text
  checkEq "a ZWJ in a name shows" "a�b" (SafeName.filter "a‍b").text
  checkEq "a name as text" "bob" (SafeName.filter "bob").toText.text
  -- Look-alike names.
  check "look-alike names share a skeleton" (skeleton "Alice" == skeleton "аlicе")
  check "separators do not matter" (skeleton "a.l-i_c e" == skeleton "alice")
  check "names that differ do not share one" (skeleton "alice" != skeleton "alicia")
  check "mixed scripts" (mixedScript "pаypal" && !mixedScript "paypal" && !mixedScript "Ελλάδα")
  -- Random and hostile text never leaves a forbidden character.
  let mut g : Rng := ⟨2026⟩
  let mut ok := true
  let mut okName := true
  for _ in [0:2000] do
    let (len, g') := g.next 80
    let (s, g'') := randomString g' len
    g := g''
    if (SafeText.filter s).text.any forbidden then ok := false
    if (SafeName.filter s).text.any forbiddenInName then okName := false
    if ((SafeText.lines s).any fun l => l.text.any forbidden) then ok := false
  check "random text never leaves a forbidden character" ok
  check "random names never leave a forbidden character" okName
  for (what, payload) in corpus do
    check s!"{what}: nothing forbidden in text" (!(SafeText.filter payload).text.any forbidden)
    check s!"{what}: nothing forbidden in a name" (!(SafeName.filter payload).text.any forbiddenInName)

end Paw.Tests.Text
