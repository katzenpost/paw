/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # Byte codecs

The byte formats shared with the Rust layer. A `Codec` carries the proof that decoding what it
encodes gives the value back, whatever bytes follow; the combinators build codecs from codecs, so
a codec for a structure gets its proof from its fields'. Natural numbers are LEB128 varints,
integers are zigzag varints, and lists are a count followed by their elements.

`enc` says what the bytes are, and the proofs are about it. `put` writes the same bytes straight
into a `ByteArray`, which is how values are encoded in practice; `put_spec` proves it writes exactly
what `enc` says. A codec that gives no `put` of its own gets one that pushes `enc`'s bytes. -/

namespace Paw

theorem ByteArray.toList_push (b : ByteArray) (x : UInt8) :
    (b.push x).data.toList = b.data.toList ++ [x] := by
  simp [ByteArray.push]

theorem ByteArray.foldl_push (l : List UInt8) (b : ByteArray) :
    (l.foldl ByteArray.push b).data.toList = b.data.toList ++ l := by
  induction l generalizing b with
  | nil => simp
  | cons x xs ih => simp [List.foldl, ih]

structure Codec (α : Type) where
  enc : α → List UInt8
  dec : List UInt8 → Option (α × List UInt8)
  roundtrip : ∀ a rest, dec (enc a ++ rest) = some (a, rest)
  put : α → ByteArray → ByteArray := fun a b => (enc a).foldl ByteArray.push b
  put_spec : ∀ a b, (put a b).data.toList = b.data.toList ++ enc a := by
    intro a b; exact ByteArray.foldl_push _ _

namespace Codec

/-- `a` encoded, as bytes. -/
def bytes {α : Type} (c : Codec α) (a : α) : ByteArray := c.put a ByteArray.empty

theorem bytes_spec {α : Type} (c : Codec α) (a : α) : (c.bytes a).data.toList = c.enc a := by
  simp [bytes, c.put_spec]

def u8 : Codec UInt8 where
  enc := fun b => [b]
  dec := fun | b :: r => some (b, r) | [] => none
  roundtrip := fun _ _ => rfl
  put := fun x b => b.push x
  put_spec := fun x b => ByteArray.toList_push b x

def encNat (n : Nat) : List UInt8 :=
  if n < 128 then [UInt8.ofNat n] else UInt8.ofNat (n % 128 + 128) :: encNat (n / 128)
termination_by n
decreasing_by omega

def decNat : List UInt8 → Option (Nat × List UInt8)
  | [] => none
  | b :: rest =>
    if b.toNat < 128 then some (b.toNat, rest)
    else match decNat rest with
      | some (m, rest') => some (b.toNat - 128 + 128 * m, rest')
      | none => none

theorem nat_roundtrip (n : Nat) (rest : List UInt8) : decNat (encNat n ++ rest) = some (n, rest) := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    rw [encNat]
    split
    · simp only [List.singleton_append, decNat, UInt8.toNat_ofNat', Nat.reducePow]
      rw [if_pos (by omega)]
      simp only [Option.some.injEq, Prod.mk.injEq, and_true]; omega
    · simp only [List.cons_append, decNat, UInt8.toNat_ofNat', Nat.reducePow]
      rw [if_neg (by omega), ih (n / 128) (by omega)]
      simp only [Option.some.injEq, Prod.mk.injEq, and_true]; omega

def putNat (n : Nat) (b : ByteArray) : ByteArray :=
  if n < 128 then b.push (UInt8.ofNat n) else putNat (n / 128) (b.push (UInt8.ofNat (n % 128 + 128)))
termination_by n
decreasing_by omega

theorem putNat_spec (n : Nat) (b : ByteArray) :
    (putNat n b).data.toList = b.data.toList ++ encNat n := by
  induction n using Nat.strongRecOn generalizing b with
  | ind n ih =>
    rw [putNat, encNat]
    split
    · simp
    · rw [ih (n / 128) (by omega), ByteArray.toList_push]; simp

def nat : Codec Nat :=
  { enc := encNat, dec := decNat, roundtrip := nat_roundtrip, put := putNat, put_spec := putNat_spec }

def pair {α β : Type} (a : Codec α) (b : Codec β) : Codec (α × β) where
  enc := fun (x, y) => a.enc x ++ b.enc y
  dec := fun bs => do
    let (x, r) ← a.dec bs
    let (y, r) ← b.dec r
    pure ((x, y), r)
  roundtrip := by
    intro (x, y) rest
    simp [List.append_assoc, a.roundtrip, b.roundtrip]
  put := fun (x, y) bs => b.put y (a.put x bs)
  put_spec := by
    intro (x, y) bs
    simp [a.put_spec, b.put_spec, List.append_assoc]

def decMany {α : Type} (a : Codec α) : Nat → List UInt8 → Option (List α × List UInt8)
  | 0, r => some ([], r)
  | k + 1, r => do
    let (x, r) ← a.dec r
    let (xs, r) ← a.decMany k r
    pure (x :: xs, r)

theorem decMany_enc {α : Type} (a : Codec α) (xs : List α) (rest : List UInt8) :
    a.decMany xs.length (xs.flatMap a.enc ++ rest) = some (xs, rest) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.length_cons, List.flatMap_cons, List.append_assoc, decMany, a.roundtrip,
      Option.bind_eq_bind, Option.bind_some, ih, Option.pure_def]

def list {α : Type} (a : Codec α) : Codec (List α) where
  enc := fun xs => encNat xs.length ++ xs.flatMap a.enc
  dec := fun bs => do
    let (n, r) ← decNat bs
    a.decMany n r
  roundtrip := by
    intro xs rest
    simp only [List.append_assoc, nat_roundtrip, Option.bind_eq_bind, Option.bind_some,
      decMany_enc]
  put := fun xs bs => xs.foldl (fun acc x => a.put x acc) (putNat xs.length bs)
  put_spec := by
    intro xs bs
    have h : ∀ (ys : List α) (acc : ByteArray),
        (ys.foldl (fun acc x => a.put x acc) acc).data.toList = acc.data.toList ++ ys.flatMap a.enc := by
      intro ys
      induction ys with
      | nil => simp
      | cons y ys ih => intro acc; simp [List.foldl, ih, a.put_spec, List.append_assoc]
    rw [h, putNat_spec, List.append_assoc]

/-- A codec for `β` through one for `α`, given a way back that `f` undoes. -/
def map {α β : Type} (a : Codec α) (f : α → β) (g : β → α) (h : ∀ y, f (g y) = y) : Codec β where
  enc := fun y => a.enc (g y)
  dec := fun bs => (a.dec bs).map fun (x, r) => (f x, r)
  roundtrip := by intro y rest; simp [a.roundtrip, h]
  put := fun y bs => a.put (g y) bs
  put_spec := fun y bs => a.put_spec (g y) bs

/-- A codec for `β` through one for `α`, where decoding may refuse what is not a `β`. -/
def refine {α β : Type} (a : Codec α) (f : α → Option β) (g : β → α) (h : ∀ y, f (g y) = some y) :
    Codec β where
  enc := fun y => a.enc (g y)
  dec := fun bs => do
    let (x, r) ← a.dec bs
    let y ← f x
    pure (y, r)
  roundtrip := by intro y rest; simp [a.roundtrip, h]
  put := fun y bs => a.put (g y) bs
  put_spec := fun y bs => a.put_spec (g y) bs

def zig (i : Int) : Nat := if 0 ≤ i then 2 * i.toNat else 2 * (-i).toNat - 1

def unzig (n : Nat) : Int := if n % 2 = 0 then (n / 2 : Nat) else -((n + 1) / 2 : Nat)

theorem unzig_zig (i : Int) : unzig (zig i) = i := by
  unfold zig unzig; split <;> split <;> omega

def int : Codec Int := nat.map unzig zig unzig_zig

def bool : Codec Bool :=
  nat.refine (fun | 0 => some false | 1 => some true | _ => none) (fun b => if b then 1 else 0)
    (by intro b; cases b <;> rfl)

def char : Codec Char :=
  nat.refine (fun n => let c := Char.ofNat n; if c.toNat = n then some c else none) Char.toNat
    (by intro c; simp [Char.ofNat_toNat])

def string : Codec String :=
  (list char).map String.ofList String.toList (fun _ => String.ofList_toList)

/-- Decodes `bytes` as exactly one value, with nothing left over. -/
def decodeAll {α : Type} (c : Codec α) (bytes : List UInt8) : Option α :=
  match c.dec bytes with
  | some (a, []) => some a
  | _ => none

theorem decodeAll_enc {α : Type} (c : Codec α) (a : α) : c.decodeAll (c.enc a) = some a := by
  have h := c.roundtrip a []
  rw [List.append_nil] at h
  simp [decodeAll, h]

def toBytes (bs : List UInt8) : ByteArray := ⟨bs.toArray⟩

def ofBytes (b : ByteArray) : List UInt8 := b.data.toList

end Codec

end Paw
