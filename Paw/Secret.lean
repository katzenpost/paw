/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Text

/-! # Secrets

A passphrase or key the user types. `Secret` has no `ToString`, `Repr` or conversion to text, so it
cannot reach a label, a log or a model snapshot by mistake; it is drawn only as dots, and its
contents are read only through `use`. -/

namespace Paw

structure Secret where
  private mk ::
  private chars : String

namespace Secret

def empty : Secret := ⟨""⟩

def ofString (s : String) : Secret := ⟨s⟩

def length (s : Secret) : Nat := s.chars.length

def push (s : Secret) (c : Char) : Secret := ⟨s.chars.push c⟩

/-- Without its last character. -/
def pop (s : Secret) : Secret := ⟨String.ofList s.chars.toList.dropLast⟩

/-- The secret as dots, at most `max` of them. -/
def dots (s : Secret) (max : Nat := 32) : SafeText :=
  SafeText.trusted (String.ofList (List.replicate (min s.length max) '•'))

/-- Gives the UTF-8 bytes to `f`, the one way to read a secret. -/
def use {α : Type} (s : Secret) (f : ByteArray → α) : α := f s.chars.toUTF8

/-- Equality, looking at every byte whatever the first difference. -/
def eq (a b : Secret) : Bool :=
  let x := a.chars.toUTF8
  let y := b.chars.toUTF8
  x.size == y.size &&
    (List.range x.size).foldl (fun acc i => acc ||| (x.get! i ^^^ y.get! i)) 0 == 0

end Secret

end Paw
