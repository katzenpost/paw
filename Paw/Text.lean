/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # Text from elsewhere

Text the program did not write itself, such as a message, a file name or a name someone chose, can
carry characters that hide, reorder or break up what is shown. Widgets draw only `SafeText` and
`SafeName`, whose `ok` fields prove that every character passed the allowlist. Filtering keeps a
character only when it is allowed, and replaces any other with a visible stand-in, so that an
attempt shows: a control character becomes its Control Picture (`␛` for ESC, `␊` for a newline),
DEL becomes `␡`, and every other character refused becomes `␦`.

Body text keeps bidi controls, which right-to-left writing needs; each field is laid out as its own
paragraph, so its direction cannot leak into the text around it. Names are stricter: no bidi
controls, joiners, variation selectors or badge-like symbols. -/

namespace Paw.Text

def inRanges (n : Nat) (rs : List (Nat × Nat)) : Bool := rs.any fun (lo, hi) => lo ≤ n && n ≤ hi

/-- C0, DEL and C1. -/
def control (n : Nat) : Bool := n < 0x20 || (0x7F ≤ n && n < 0xA0)

/-- Characters drawn as nothing: the soft hyphen, zero-width space, word joiner and invisible
operators, the byte order mark, the Mongolian vowel separator and tag characters. -/
def invisible (n : Nat) : Bool :=
  n == 0xAD || n == 0x200B || n == 0xFEFF || n == 0x180E ||
    inRanges n [(0x2060, 0x2064), (0xE0000, 0xE007F)]

def lineSeparator (n : Nat) : Bool := n == 0x2028 || n == 0x2029

/-- Private use: glyphs whose look only a particular font decides. -/
def privateUse (n : Nat) : Bool := inRanges n [(0xE000, 0xF8FF), (0xF0000, 0x10FFFF)]

def noncharacter (n : Nat) : Bool := inRanges n [(0xFDD0, 0xFDEF)] || n % 0x10000 ≥ 0xFFFE

/-- Allowed in text. -/
def allowed (c : Char) : Bool :=
  let n := c.toNat
  !(control n || invisible n || lineSeparator n || privateUse n || noncharacter n)

def bidiControl (n : Nat) : Bool :=
  inRanges n [(0x202A, 0x202E), (0x2066, 0x2069)] || n == 0x200E || n == 0x200F || n == 0x61C

/-- Locks, check marks and shields, which a name could use to fake a verified or encrypted mark. -/
def badge (n : Nat) : Bool :=
  inRanges n [(0x1F50F, 0x1F513)] || n == 0x2611 || n == 0x2705 || n == 0x2713 || n == 0x2714 ||
    n == 0x1F6E1

/-- Allowed in a name. -/
def allowedInName (c : Char) : Bool :=
  let n := c.toNat
  allowed c && !(bidiControl n || n == 0x200C || n == 0x200D || inRanges n [(0xFE00, 0xFE0F)] ||
    badge n)

/-- Combining marks, kept on the character before them, a few at a time. -/
def combining (n : Nat) : Bool :=
  inRanges n [(0x300, 0x36F), (0x483, 0x489), (0x591, 0x5BD), (0x5BF, 0x5BF), (0x5C1, 0x5C2),
    (0x5C4, 0x5C5), (0x5C7, 0x5C7), (0x610, 0x61A), (0x64B, 0x65F), (0x670, 0x670),
    (0x6D6, 0x6DC), (0x6DF, 0x6E4), (0x6E7, 0x6E8), (0x6EA, 0x6ED), (0x1AB0, 0x1AFF),
    (0x1DC0, 0x1DFF), (0x20D0, 0x20FF), (0xFE20, 0xFE2F)]

/-- The stand-in for a character refused that is not C0 or DEL. -/
def substitute : Char := '␦'

/-- The Control Pictures for C0, U+2400 to U+241F. -/
def controlPictures : List Char := (List.range 32).map fun n => Char.ofNat (0x2400 + n)

theorem controlPictures_length : controlPictures.length = 32 := by simp [controlPictures]

theorem controlPictures_allowed : ∀ c ∈ controlPictures, allowedInName c = true := by decide

/-- What a character refused shows as. -/
def standIn (c : Char) : Char :=
  if h : c.toNat < 32 then controlPictures[c.toNat]'(by rw [controlPictures_length]; exact h)
  else if c.toNat == 0x7F then '␡'
  else substitute

theorem standIn_allowedInName (c : Char) : allowedInName (standIn c) = true := by
  unfold standIn
  split
  · exact controlPictures_allowed _ (List.getElem_mem _)
  · split <;> decide

theorem allowed_of_allowedInName {c : Char} (h : allowedInName c = true) : allowed c = true := by
  simp only [allowedInName, Bool.and_eq_true] at h
  exact h.1

theorem standIn_allowed (c : Char) : allowed (standIn c) = true :=
  allowed_of_allowedInName (standIn_allowedInName c)

/-- Keeps at most `maxMarks` combining marks on a base character, and replaces the rest, and any
mark with no base, by the substitute: one for a run of excess marks. -/
def capMarks (maxMarks : Nat) (cs : List Char) : List Char := Id.run do
  let mut out : Array Char := #[]
  let mut marks := 0
  let mut base := false
  for c in cs do
    if combining c.toNat then
      if base && marks < maxMarks then out := out.push c
      else if !base || marks == maxMarks then out := out.push substitute
      marks := marks + 1
    else
      out := out.push c
      marks := 0
      base := allowed c
  return out.toList

def clean (ok : Char → Bool) (c : Char) : Char := if ok c then c else standIn c

theorem clean_allowed (c : Char) : allowed (clean allowed c) = true := by
  unfold clean; split
  · assumption
  · exact standIn_allowed c

theorem clean_allowedInName (c : Char) : allowedInName (clean allowedInName c) = true := by
  unfold clean; split
  · assumption
  · exact standIn_allowedInName c

theorem all_map_clean (cs : List Char) : (cs.map (clean allowed)).all allowed = true := by
  simp only [List.all_map, List.all_eq_true]
  intro c _
  exact clean_allowed c

theorem all_map_cleanName (cs : List Char) :
    (cs.map (clean allowedInName)).all allowedInName = true := by
  simp only [List.all_map, List.all_eq_true]
  intro c _
  exact clean_allowedInName c

end Paw.Text

namespace Paw

open Text

/-- Text that may be drawn: one line, every character allowed. -/
structure SafeText where
  text : String
  ok : text.toList.all allowed = true

instance : BEq SafeText := ⟨fun a b => a.text == b.text⟩
instance : Repr SafeText := ⟨fun s _ => repr s.text⟩
instance : Inhabited SafeText := ⟨⟨"", rfl⟩⟩

namespace SafeText

def empty : SafeText := ⟨"", rfl⟩

/-- One line of text from elsewhere, filtered. -/
def filter (s : String) (maxMarks : Nat := 4) : SafeText :=
  ⟨String.ofList ((capMarks maxMarks s.toList).map (clean allowed)), by
    rw [String.toList_ofList]; exact all_map_clean _⟩

/-- Text the program wrote itself, if every character is allowed. -/
def trusted? (s : String) : Option SafeText :=
  if h : s.toList.all allowed = true then some ⟨s, h⟩ else none

/-- Text the program wrote itself; should it hold a character not allowed, it is filtered. -/
def trusted (s : String) : SafeText := (trusted? s).getD (filter s)

instance : Append SafeText := ⟨fun a b => ⟨a.text ++ b.text, by
  rw [String.toList_append, List.all_append, a.ok, b.ok]; rfl⟩⟩

/-- A text as its lines, filtered: tabs become spaces, a carriage return before a newline goes,
and of more than `maxLines` lines, the last kept says how many more there were. -/
def lines (s : String) (maxLines : Nat := 20) (tabWidth : Nat := 4) : List SafeText :=
  let tab := String.ofList (List.replicate tabWidth ' ')
  let ls := ((s.replace "\r\n" "\n").splitOn "\n").map fun l => filter (l.replace "\t" tab)
  if ls.length ≤ maxLines then ls
  else ls.take (maxLines - 1) ++ [trusted s!"[{ls.length - (maxLines - 1)} more lines not shown]"]

end SafeText

/-- A name that may be drawn: stricter than `SafeText`, for names, titles and file names. -/
structure SafeName where
  text : String
  ok : text.toList.all allowedInName = true

instance : BEq SafeName := ⟨fun a b => a.text == b.text⟩
instance : Repr SafeName := ⟨fun s _ => repr s.text⟩

namespace SafeName

def filter (s : String) (maxMarks : Nat := 4) : SafeName :=
  ⟨String.ofList ((capMarks maxMarks s.toList).map (clean allowedInName)), by
    rw [String.toList_ofList]; exact all_map_cleanName _⟩

def toText (n : SafeName) : SafeText := ⟨n.text, by
  have h := n.ok
  simp only [List.all_eq_true] at h ⊢
  exact fun c hc => allowed_of_allowedInName (h c hc)⟩

end SafeName

namespace Text

/-- Letters of other scripts drawn like Latin ones, and digits and symbols drawn like letters, as
the Latin letter they pass for: a small part of Unicode's confusables (UTS #39). -/
def confusables : List (Char × Char) :=
  [('а', 'a'), ('е', 'e'), ('о', 'o'), ('р', 'p'), ('с', 'c'), ('у', 'y'), ('х', 'x'),
   ('і', 'i'), ('ј', 'j'), ('ѕ', 's'), ('һ', 'h'), ('ԁ', 'd'), ('ɡ', 'g'), ('ӏ', 'l'),
   ('α', 'a'), ('ο', 'o'), ('ν', 'v'), ('ρ', 'p'), ('τ', 't'), ('ι', 'i'), ('κ', 'k'),
   ('А', 'a'), ('В', 'b'), ('Е', 'e'), ('К', 'k'), ('М', 'm'), ('Н', 'h'), ('О', 'o'),
   ('Р', 'p'), ('С', 'c'), ('Т', 't'), ('Х', 'x'), ('Α', 'a'), ('Β', 'b'), ('Ε', 'e'),
   ('Ζ', 'z'), ('Η', 'h'), ('Ι', 'i'), ('Κ', 'k'), ('Μ', 'm'), ('Ν', 'n'), ('Ο', 'o'),
   ('Ρ', 'p'), ('Τ', 't'), ('Χ', 'x'), ('Υ', 'y'),
   ('0', 'o'), ('1', 'l'), ('I', 'l'), ('|', 'l'), ('5', 's'), ('$', 's')]

/-- What a name looks like, ignoring case, look-alike letters, accents and separators: two names
with one skeleton are easily taken for each other. -/
def skeleton (s : String) : String :=
  String.ofList <| (SafeName.filter s).text.toList.filterMap fun c =>
    if combining c.toNat || c == ' ' || c == '_' || c == '-' || c == '.' then none
    else some ((confusables.lookup c).getD c.toLower)

/-- Whether a name mixes Latin letters with Greek or Cyrillic ones, as a forged name might. -/
def mixedScript (s : String) : Bool :=
  s.any (fun c => c.isAlpha) && s.any fun c => 0x370 ≤ c.toNat && c.toNat ≤ 0x52F

end Text

end Paw
