/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # Wrapping text

A line of text broken into lines no wider than a width, greedily, as a paragraph is laid out. The
text is cut into pieces, each a word and the spaces after it. A line takes pieces while they fit;
the spaces at its end hang past the edge, as in a browser, so they never push a word onto the
next line, and the lines put back together are the text exactly (`wrap_flatten`). A word wider
than the line is first cut into runs of characters that fit. So every line fits, or is a single
character too wide for any line (`wrap_fits`).

Widths are what `measure` gives for a word, and the sum of characters' widths for a run cut from a
word too long for a line, so the width of each word is measured once. -/

namespace Paw.Wrap

variable {α : Type}

/-- A line's width, when an element `x` takes `full x` with something after it, and `core x` at
the end of the line. -/
def lineWidth (core full : α → Int) : List α → Int
  | [] => 0
  | [x] => core x
  | x :: xs => full x + lineWidth core full xs

def fullSum (full : α → Int) (xs : List α) : Int := (xs.map full).sum

theorem lineWidth_append (core full : α → Int) (cur : List α) (x : α) (h : cur ≠ []) :
    lineWidth core full (cur ++ [x]) = fullSum full cur + core x := by
  induction cur with
  | nil => exact absurd rfl h
  | cons y ys ih =>
    cases ys with
    | nil => simp [lineWidth, fullSum]
    | cons z zs =>
      have := ih (by simp)
      simp only [List.cons_append, lineWidth] at this ⊢
      rw [this]
      simp [fullSum]
      omega

/-- Elements packed greedily into lines no wider than `w`, onto the line `cur` begun so far, of
full width `f`: an element joins the line if the line still fits with it at the end. -/
def pack (core full : α → Int) (w : Int) : List α → Int → List α → List (List α)
  | cur, _, [] => if cur.isEmpty then [] else [cur]
  | cur, f, x :: xs =>
    if cur.isEmpty then pack core full w [x] (full x) xs
    else if f + core x ≤ w then pack core full w (cur ++ [x]) (f + full x) xs
    else cur :: pack core full w [x] (full x) xs

/-- Every line fits, or holds a single element. -/
theorem pack_fits (core full : α → Int) (w : Int) (xs : List α) :
    ∀ (cur : List α) (f : Int), f = fullSum full cur →
      (cur = [] ∨ cur.length = 1 ∨ lineWidth core full cur ≤ w) →
      ∀ l ∈ pack core full w cur f xs, l.length = 1 ∨ lineWidth core full l ≤ w := by
  induction xs with
  | nil =>
    intro cur f _ hinv l hl
    simp only [pack] at hl
    split at hl
    · cases hl
    · rename_i hne
      simp only [List.mem_singleton] at hl
      subst hl
      rcases hinv with h | h | h
      · simp [h] at hne
      · exact Or.inl h
      · exact Or.inr h
  | cons x xs ih =>
    intro cur f hf hinv l hl
    simp only [pack] at hl
    split at hl
    · exact ih [x] (full x) (by simp [fullSum]) (Or.inr (Or.inl rfl)) l hl
    · rename_i hne
      have hne' : cur ≠ [] := by simpa using hne
      split at hl
      · rename_i hfit
        refine ih (cur ++ [x]) (f + full x) (by simp [fullSum, hf]) (Or.inr (Or.inr ?_)) l hl
        rw [lineWidth_append core full cur x hne', ← hf]
        exact hfit
      · simp only [List.mem_cons] at hl
        rcases hl with rfl | hl
        · rcases hinv with h | h | h
          · exact absurd h hne'
          · exact Or.inl h
          · exact Or.inr h
        · exact ih [x] (full x) (by simp [fullSum]) (Or.inr (Or.inl rfl)) l hl

/-- Packing loses and adds nothing. -/
theorem pack_flatten (core full : α → Int) (w : Int) (xs : List α) :
    ∀ (cur : List α) (f : Int), (pack core full w cur f xs).flatten = cur ++ xs := by
  induction xs with
  | nil => intro cur f; simp only [pack]; split <;> simp_all
  | cons x xs ih =>
    intro cur f
    simp only [pack]
    split
    · rename_i h; simp at h; subst h; simp [ih]
    · split <;> simp [ih]

/-- No line is empty. -/
theorem pack_ne_nil (core full : α → Int) (w : Int) (xs : List α) :
    ∀ (cur : List α) (f : Int), ∀ l ∈ pack core full w cur f xs, l ≠ [] := by
  induction xs with
  | nil => intro cur f l hl; simp only [pack] at hl; split at hl <;> simp_all
  | cons x xs ih =>
    intro cur f l hl
    simp only [pack] at hl
    split at hl
    · exact ih _ _ l hl
    · split at hl
      · exact ih _ _ l hl
      · rename_i hne _
        simp only [List.mem_cons] at hl
        rcases hl with rfl | hl
        · simpa using hne
        · exact ih _ _ l hl

/-- A word and the spaces after it. -/
structure Piece where
  word : List Char
  spaces : List Char
  /-- The word's width. -/
  core : Int
  /-- With its spaces. -/
  full : Int
  deriving Repr, Inhabited

def Piece.chars (p : Piece) : List Char := p.word ++ p.spaces

/-- `cs` as words, each with the spaces after it; spaces at the start come first, with no word. -/
def words (cs : List Char) : List (List Char × List Char) :=
  cs.foldr (init := []) fun c acc =>
    if c == ' ' then
      match acc with
      | ([], sp) :: rest => ([], c :: sp) :: rest
      | _ => ([], [c]) :: acc
    else
      match acc with
      | (w, sp) :: rest => (c :: w, sp) :: rest
      | [] => [([c], [])]

theorem words_flatten (cs : List Char) : ((words cs).map fun (w, s) => w ++ s).flatten = cs := by
  induction cs with
  | nil => rfl
  | cons c cs ih =>
    simp only [words, List.foldr_cons] at ih ⊢
    split
    · split
      · rename_i sp rest h
        rw [h] at ih
        simp_all
      · simp_all
    · split
      · rename_i w sp rest h
        rw [h] at ih
        simp_all
      · rename_i h
        rw [h] at ih
        simp_all

/-- Runs of a word's characters as pieces, measured by `cw`; the last keeps the spaces `sp` after
the word, `spw` wide. -/
def attach (cw : Char → Int) (sp : List Char) (spw : Int) : List (List Char) → List Piece
  | [] => []
  | [r] => [{ word := r, spaces := sp, core := (r.map cw).sum, full := (r.map cw).sum + spw }]
  | r :: rs => { word := r, spaces := [], core := (r.map cw).sum, full := (r.map cw).sum } :: attach cw sp spw rs

/-- The pieces of a word too wide for `w`, cut into runs of characters that fit, measured by
`cw`; the last keeps the spaces after the word. -/
def cut (w : Int) (cw : Char → Int) (word sp : List Char) (spw : Int) : List Piece :=
  attach cw sp spw (pack cw cw w [] 0 word)

/-- The pieces of `cs` for a line `w` wide: each word measured by `measure`, and one wider than
the line cut by characters. -/
def pieces (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) : List Piece :=
  (words cs).flatMap fun (word, sp) =>
    let core := measure word
    let spw := (sp.map cw).sum
    if core ≤ w || word.length ≤ 1 then [{ word, spaces := sp, core, full := core + spw }]
    else cut w cw word sp spw

/-- `cs` broken into lines that fit `w`, as pieces. -/
def lines (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) : List (List Piece) :=
  pack Piece.core Piece.full w [] 0 (pieces w measure cw cs)

/-- `cs` broken into lines that fit `w`. -/
def wrap (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) : List (List Char) :=
  (lines w measure cw cs).map (·.flatMap Piece.chars)

theorem attach_chars (cw : Char → Int) (sp : List Char) (spw : Int) :
    ∀ (rs : List (List Char)), rs ≠ [] → (attach cw sp spw rs).flatMap Piece.chars = rs.flatten ++ sp
  | [], h => absurd rfl h
  | [r], _ => by simp [attach, Piece.chars]
  | r :: r' :: rs, _ => by
    have := attach_chars cw sp spw (r' :: rs) (by simp)
    simp only [attach, List.flatMap_cons, Piece.chars, List.append_nil] at this ⊢
    rw [this]
    simp

theorem attach_mem (cw : Char → Int) (sp : List Char) (spw : Int) :
    ∀ (rs : List (List Char)), ∀ p ∈ attach cw sp spw rs, p.word ∈ rs ∧ p.core = (p.word.map cw).sum
  | [], p, h => by simp [attach] at h
  | [r], p, h => by simp only [attach, List.mem_singleton] at h; subst h; simp
  | r :: r' :: rs, p, h => by
    simp only [attach, List.mem_cons] at h
    rcases h with rfl | h
    · simp
    · have := attach_mem cw sp spw (r' :: rs) p (by simpa [attach] using h)
      exact ⟨List.mem_cons_of_mem _ this.1, this.2⟩

theorem lineWidth_same (f : α → Int) : ∀ (xs : List α), lineWidth f f xs = (xs.map f).sum
  | [] => rfl
  | [x] => by simp [lineWidth]
  | x :: y :: ys => by
    have := lineWidth_same f (y :: ys)
    simp only [lineWidth, List.map_cons, List.sum_cons] at this ⊢
    rw [this]

theorem cut_chars (w : Int) (cw : Char → Int) (word sp : List Char) (spw : Int) (h : word ≠ []) :
    (cut w cw word sp spw).flatMap Piece.chars = word ++ sp := by
  unfold cut
  have hf := pack_flatten cw cw w word [] 0
  rw [List.nil_append] at hf
  rw [attach_chars cw sp spw _ (by intro e; rw [e] at hf; exact h hf.symm), hf]

theorem flatten_map_flatMap {β : Type} (f : α → List β) (ls : List (List α)) :
    (ls.map (·.flatMap f)).flatten = ls.flatten.flatMap f := by
  induction ls <;> simp_all [List.flatMap_append]

/-- The lines put back together are the text. -/
theorem wrap_flatten (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) :
    (wrap w measure cw cs).flatten = cs := by
  have hl : ((lines w measure cw cs).map (·.flatMap Piece.chars)).flatten =
      (pieces w measure cw cs).flatMap Piece.chars := by
    have := pack_flatten Piece.core Piece.full w (pieces w measure cw cs) [] 0
    rw [List.nil_append] at this
    unfold lines
    rw [flatten_map_flatMap, this]
  unfold wrap
  rw [hl]
  conv => rhs; rw [← words_flatten cs]
  unfold pieces
  rw [List.flatMap_assoc]
  simp only [List.flatMap_def]
  congr 1
  apply List.map_congr_left
  intro ⟨word, sp⟩ _
  split
  · simp [Piece.chars]
  · rename_i h
    have hne : word ≠ [] := by intro e; subst e; simp at h
    rw [← List.flatMap_def, cut_chars w cw word sp _ hne]

/-- Every piece fits the line, or is a single character too wide for any. -/
theorem pieces_fit (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) :
    ∀ p ∈ pieces w measure cw cs, p.core ≤ w ∨ p.word.length ≤ 1 := by
  intro p hp
  simp only [pieces, List.mem_flatMap] at hp
  obtain ⟨⟨word, sp⟩, -, hp⟩ := hp
  split at hp
  · rename_i h
    simp only [List.mem_singleton] at hp
    subst hp
    simpa using h
  · obtain ⟨hr, hc⟩ := attach_mem cw sp _ _ p hp
    rcases pack_fits cw cw w word [] 0 (by simp [fullSum]) (Or.inl rfl) p.word hr with h | h
    · exact Or.inr (by omega)
    · rw [lineWidth_same] at h
      exact Or.inl (hc ▸ h)

/-- Every line fits the width, or is a single piece too wide for any line, which is a single
character. -/
theorem wrap_fits (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) :
    ∀ l ∈ lines w measure cw cs, lineWidth Piece.core Piece.full l ≤ w ∨
      ∃ p, l = [p] ∧ p.word.length ≤ 1 := by
  intro l hl
  rcases pack_fits Piece.core Piece.full w _ [] 0 (by simp [fullSum]) (Or.inl rfl) l hl with h | h
  · match l, h with
    | [p], _ =>
      have hp : p ∈ pieces w measure cw cs := by
        have := pack_flatten Piece.core Piece.full w (pieces w measure cw cs) [] 0
        rw [List.nil_append] at this
        rw [← this]
        exact List.mem_flatten.mpr ⟨[p], hl, List.mem_singleton_self p⟩
      rcases pieces_fit w measure cw cs p hp with h' | h'
      · exact Or.inl (by simpa [lineWidth] using h')
      · exact Or.inr ⟨p, rfl, h'⟩
  · exact Or.inl h

end Paw.Wrap
