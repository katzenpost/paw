/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # Formats

How a value is written as text in a field, and read back: a `Format` carries the law that what it
writes reads back as the value written, as a `Codec` carries its round trip. Numbers are written
in decimal digits, by functions over characters whose round trips are proved here. -/

namespace Paw

structure Format (α : Type) where
  parse : List Char → Option α
  print : α → List Char
  roundtrip : ∀ v, parse (print v) = some v

namespace Format

/-- The digit for `d`, below ten. -/
def digit (d : Nat) : Char := Char.ofNat (48 + d)

/-- A digit's value. -/
def digitVal (c : Char) : Option Nat := if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - 48) else none

theorem digitVal_digit : ∀ d, d < 10 → digitVal (digit d) = some d := by decide

def isDigit (c : Char) : Bool := (digitVal c).isSome

theorem isDigit_digit (d : Nat) (h : d < 10) : isDigit (digit d) = true := by
  simp [isDigit, digitVal_digit d h]

theorem not_isDigit_of (c : Char) (h : digitVal c = none) : isDigit c = false := by simp [isDigit, h]

/-- `n`'s digits, least significant first. -/
def digitsRev (n : Nat) : List Char :=
  if n < 10 then [digit n] else digit (n % 10) :: digitsRev (n / 10)
termination_by n
decreasing_by omega

/-- The number whose digits, least significant first, are `cs`. -/
def ofDigitsRev : List Char → Option Nat
  | [] => none
  | [c] => digitVal c
  | c :: cs => do
    let d ← digitVal c
    let r ← ofDigitsRev cs
    pure (d + 10 * r)

theorem digitsRev_ne_nil (n : Nat) : digitsRev n ≠ [] := by
  unfold digitsRev; split <;> simp

theorem ofDigitsRev_digitsRev (n : Nat) : ofDigitsRev (digitsRev n) = some n := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    unfold digitsRev
    split
    · rename_i h; simp [ofDigitsRev, digitVal_digit n h]
    · rename_i h
      have hr := ih (n / 10) (by omega)
      have hne := digitsRev_ne_nil (n / 10)
      match hd : digitsRev (n / 10) with
      | [] => exact absurd hd hne
      | c :: cs =>
        rw [hd] at hr
        simp only [ofDigitsRev, digitVal_digit (n % 10) (Nat.mod_lt _ (by omega)), hr]
        simp; omega

theorem digitsRev_digits (n : Nat) : ∀ c ∈ digitsRev n, isDigit c = true := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    unfold digitsRev
    split
    · rename_i h; simp [isDigit_digit n h]
    · intro c hc
      simp only [List.mem_cons] at hc
      rcases hc with rfl | hc
      · exact isDigit_digit _ (Nat.mod_lt _ (by omega))
      · exact ih (n / 10) (by omega) c hc

/-- `n` in decimal. -/
def showNat (n : Nat) : List Char := (digitsRev n).reverse

/-- A number in decimal, all of `cs`. -/
def parseNat (cs : List Char) : Option Nat := ofDigitsRev cs.reverse

theorem parseNat_showNat (n : Nat) : parseNat (showNat n) = some n := by
  simp [parseNat, showNat, ofDigitsRev_digitsRev]

theorem showNat_digits (n : Nat) : ∀ c ∈ showNat n, isDigit c = true := by
  intro c hc; exact digitsRev_digits n c (List.mem_reverse.mp hc)

theorem showNat_ne_nil (n : Nat) : showNat n ≠ [] := by simp [showNat, digitsRev_ne_nil]

/-- Natural numbers. -/
def nat : Format Nat := { parse := parseNat, print := showNat, roundtrip := parseNat_showNat }

/-- Integers, with a minus sign before a negative one. -/
def int : Format Int where
  parse := fun
    | '-' :: cs => (parseNat cs).bind fun n => if n = 0 then none else some (-(n : Int))
    | cs => (parseNat cs).map (Int.ofNat ·)
  print := fun v => if v < 0 then '-' :: showNat v.natAbs else showNat v.toNat
  roundtrip := by
    intro v
    by_cases h : v < 0
    · simp only [h, if_true, parseNat_showNat, Option.bind_some]
      rw [if_neg (by omega)]
      simp; omega
    · simp only [h, if_false]
      have hd := showNat_digits v.toNat
      match hs : showNat v.toNat with
      | [] => exact absurd hs (showNat_ne_nil _)
      | c :: cs =>
        have hc : c ≠ '-' := by
          intro e
          have := hd c (by rw [hs]; exact List.mem_cons_self ..)
          rw [e] at this
          exact absurd this (by decide)
        rw [← hs]
        split
        · rename_i cs' heq
          rw [hs] at heq
          injection heq with h1
          exact absurd h1 hc
        · rw [parseNat_showNat]
          simp; omega

/-- `cs` with zeros before it to make it `width` long. -/
def padTo (width : Nat) (cs : List Char) : List Char := List.replicate (width - cs.length) '0' ++ cs

theorem ofDigitsRev_zeros (cs : List Char) (k : Nat) (h : cs ≠ []) :
    ofDigitsRev (cs ++ List.replicate k '0') = ofDigitsRev cs := by
  induction k with
  | zero => simp
  | succ k ih =>
    rw [List.replicate_succ', ← List.append_assoc]
    have hne : cs ++ List.replicate k '0' ≠ [] := by simp [h]
    generalize hx : cs ++ List.replicate k '0' = xs at hne ih
    rw [← ih]
    clear ih hx
    induction xs with
    | nil => exact absurd rfl hne
    | cons y ys iy =>
      cases ys with
      | nil =>
        show ofDigitsRev [y, '0'] = ofDigitsRev [y]
        simp only [ofDigitsRev]
        cases digitVal y <;> simp [digitVal]
      | cons z zs =>
        have := iy (by simp)
        simp only [List.cons_append, ofDigitsRev] at this ⊢
        rw [this]

theorem parseNat_padTo (w n : Nat) : parseNat (padTo w (showNat n)) = some n := by
  simp only [parseNat, padTo, List.reverse_append, List.reverse_replicate]
  rw [ofDigitsRev_zeros _ _ (by simpa using showNat_ne_nil n)]
  exact parseNat_showNat n

theorem padTo_digits (w : Nat) (cs : List Char) (h : ∀ c ∈ cs, isDigit c = true) :
    ∀ c ∈ padTo w cs, isDigit c = true := by
  intro c hc
  simp only [padTo, List.mem_append, List.mem_replicate] at hc
  rcases hc with ⟨-, rfl⟩ | hc
  · decide
  · exact h c hc

/-- Digits at the start of `cs`, as a number, and what follows. -/
def num (cs : List Char) : Option (Nat × List Char) :=
  (parseNat (cs.takeWhile isDigit)).map (·, cs.dropWhile isDigit)

theorem num_append (ds rest : List Char) (hd : ∀ c ∈ ds, isDigit c = true)
    (hr : ∀ c ∈ rest.head?, isDigit c = false) :
    num (ds ++ rest) = (parseNat ds).map (·, rest) := by
  have ht : (ds ++ rest).takeWhile isDigit = ds := by
    rw [List.takeWhile_append_of_pos hd]
    cases rest with
    | nil => simp
    | cons r rs => simp [hr r (by simp)]
  have hdr : (ds ++ rest).dropWhile isDigit = rest := by
    rw [List.dropWhile_append_of_pos hd]
    cases rest with
    | nil => simp
    | cons r rs => simp [hr r (by simp)]
  simp [num, ht, hdr]

/-- Values of `f` between `lo` and `hi`: read only if within them. -/
def bounded {α : Type} [LE α] [DecidableRel (α := α) (· ≤ ·)] (f : Format α) (lo hi : α) :
    Format { x : α // lo ≤ x ∧ x ≤ hi } where
  parse := fun cs => (f.parse cs).bind fun x => if h : lo ≤ x ∧ x ≤ hi then some ⟨x, h⟩ else none
  print := fun v => f.print v.val
  roundtrip := by intro ⟨v, h⟩; simp [f.roundtrip, h]

theorem digitsRev_length_le (n k : Nat) (h : n < 10 ^ k) (hk : 1 ≤ k) : (digitsRev n).length ≤ k := by
  induction n using Nat.strongRecOn generalizing k with
  | _ n ih =>
    unfold digitsRev
    split
    · simp; omega
    · rename_i hn
      have hk2 : 2 ≤ k := by
        rcases Nat.lt_or_ge k 2 with hk' | hk'
        · have : k = 1 := by omega
          subst this; omega
        · exact hk'
      have hlt : n / 10 < 10 ^ (k - 1) := by
        have : 10 ^ k = 10 * 10 ^ (k - 1) := by
          rw [← Nat.pow_succ']; congr 1; omega
        rw [this] at h
        exact Nat.div_lt_of_lt_mul h
      have := ih (n / 10) (by omega) (k - 1) hlt (by omega)
      simp; omega

theorem showNat_length_le (n k : Nat) (h : n < 10 ^ k) (hk : 1 ≤ k) : (showNat n).length ≤ k := by
  simpa [showNat] using digitsRev_length_le n k h hk

theorem padTo_length (w : Nat) (cs : List Char) (h : cs.length ≤ w) : (padTo w cs).length = w := by
  simp [padTo]; omega

/-- Numbers with `places` digits after the decimal point, as integers in units of `10 ^ -places`:
1.5 with two places is 150. -/
def decimal (places : Nat) (hp : 1 ≤ places) : Format Int where
  parse := fun cs =>
    let (neg, cs) := match cs with
      | '-' :: rest => (true, rest)
      | _ => (false, cs)
    (num cs).bind fun (q, rest) => match rest with
      | '.' :: frac =>
        if frac.length ≤ places then
          (parseNat frac).bind fun r =>
            let a := q * 10 ^ places + r * 10 ^ (places - frac.length)
            if neg then (if a = 0 then none else some (-(a : Int))) else some a
        else none
      | _ => none
  print := fun v =>
    let a := v.natAbs
    (if v < 0 then ['-'] else []) ++ showNat (a / 10 ^ places) ++ '.' :: padTo places (showNat (a % 10 ^ places))
  roundtrip := by
    intro v
    have hlen : (padTo places (showNat (v.natAbs % 10 ^ places))).length = places :=
      padTo_length _ _ (showNat_length_le _ _ (Nat.mod_lt _ (Nat.pow_pos (by omega))) hp)
    have hnum : num (showNat (v.natAbs / 10 ^ places) ++ '.' :: padTo places (showNat (v.natAbs % 10 ^ places))) =
        some (v.natAbs / 10 ^ places, '.' :: padTo places (showNat (v.natAbs % 10 ^ places))) := by
      rw [num_append _ _ (showNat_digits _) (by intro c hc; simp at hc; subst hc; decide), parseNat_showNat]
      rfl
    have hval : v.natAbs / 10 ^ places * 10 ^ places + v.natAbs % 10 ^ places = v.natAbs := Nat.div_add_mod' _ _
    by_cases h : v < 0
    · simp only [h, if_true, List.cons_append, List.nil_append]
      simp only [hnum, Option.bind_some, hlen, Nat.le_refl, if_true, parseNat_padTo, Nat.sub_self, Nat.pow_zero,
        Nat.mul_one, hval]
      rw [if_neg (by omega)]
      simp; omega
    · simp only [h, if_false, List.nil_append]
      have hd := showNat_digits (v.natAbs / 10 ^ places)
      match hs : showNat (v.natAbs / 10 ^ places) with
      | [] => exact absurd hs (showNat_ne_nil _)
      | c :: cs =>
        have hc : c ≠ '-' := by
          intro e
          have := hd c (by rw [hs]; exact List.mem_cons_self ..)
          rw [e] at this
          exact absurd this (by decide)
        rw [← hs]
        have : (match showNat (v.natAbs / 10 ^ places) ++ '.' :: padTo places (showNat (v.natAbs % 10 ^ places)) with
            | '-' :: rest => (true, rest)
            | _ => (false, showNat (v.natAbs / 10 ^ places) ++ '.' :: padTo places (showNat (v.natAbs % 10 ^ places)))) =
            (false, showNat (v.natAbs / 10 ^ places) ++ '.' :: padTo places (showNat (v.natAbs % 10 ^ places))) := by
          rw [hs]; simp [hc]
        simp only [this, hnum, Option.bind_some, hlen, Nat.le_refl, if_true, parseNat_padTo, Nat.sub_self, Nat.pow_zero,
          Nat.mul_one, hval]
        simp; omega

/-- Whether `y` is a leap year. -/
def leap (y : Nat) : Bool := y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)

def daysIn (y m : Nat) : Nat :=
  match m with
  | 2 => if leap y then 29 else 28
  | 4 | 6 | 9 | 11 => 30
  | _ => 31

/-- A day of the calendar. -/
structure Date where
  year : Nat
  month : Nat
  day : Nat
  valid : 1 ≤ month ∧ month ≤ 12 ∧ 1 ≤ day ∧ day ≤ daysIn year month
  deriving Repr, DecidableEq

instance : Inhabited Date := ⟨⟨2026, 1, 1, by decide⟩⟩

/-- Dates as year, month and day: 2026-10-14. -/
def date : Format Date where
  parse := fun cs => (num cs).bind fun (y, r1) => match r1 with
    | '-' :: r1 => (num r1).bind fun (m, r2) => match r2 with
      | '-' :: r2 => (num r2).bind fun (d, r3) =>
        if r3.isEmpty then
          if h : 1 ≤ m ∧ m ≤ 12 ∧ 1 ≤ d ∧ d ≤ daysIn y m then some ⟨y, m, d, h⟩ else none
        else none
      | _ => none
    | _ => none
  print := fun x => showNat x.year ++ ('-' :: (padTo 2 (showNat x.month) ++ ('-' :: padTo 2 (showNat x.day))))
  roundtrip := by
    intro ⟨y, m, d, h⟩
    have dash : ∀ c ∈ ('-' :: ([] : List Char)).head?, isDigit c = false := by intro c hc; simp at hc; subst hc; decide
    have dash' (rest : List Char) : ∀ c ∈ ('-' :: rest).head?, isDigit c = false := by
      intro c hc; simp at hc; subst hc; decide
    simp only
    rw [num_append _ _ (showNat_digits y) (dash' _), parseNat_showNat]
    simp only [Option.map_some, Option.bind_some]
    rw [num_append _ _ (padTo_digits 2 _ (showNat_digits m)) (dash' _), parseNat_padTo]
    simp only [Option.map_some, Option.bind_some]
    rw [← List.append_nil (padTo 2 (showNat d)), num_append _ _ (padTo_digits 2 _ (showNat_digits d)) (by simp),
      parseNat_padTo]
    simp [h]

/-- A time of day. -/
structure Time where
  hour : Nat
  minute : Nat
  valid : hour < 24 ∧ minute < 60
  deriving Repr, DecidableEq

instance : Inhabited Time := ⟨⟨0, 0, by decide⟩⟩

/-- Times as hours and minutes: 09:30. -/
def time : Format Time where
  parse := fun cs => (num cs).bind fun (h, r1) => match r1 with
    | ':' :: r1 => (num r1).bind fun (m, r2) =>
      if r2.isEmpty then (if hv : h < 24 ∧ m < 60 then some ⟨h, m, hv⟩ else none) else none
    | _ => none
  print := fun t => padTo 2 (showNat t.hour) ++ (':' :: padTo 2 (showNat t.minute))
  roundtrip := by
    intro ⟨h, m, hv⟩
    simp only
    rw [num_append _ _ (padTo_digits 2 _ (showNat_digits h)) (by intro c hc; simp at hc; subst hc; decide),
      parseNat_padTo]
    simp only [Option.map_some, Option.bind_some]
    rw [← List.append_nil (padTo 2 (showNat m)), num_append _ _ (padTo_digits 2 _ (showNat_digits m)) (by simp),
      parseNat_padTo]
    simp [hv]

end Format

end Paw
