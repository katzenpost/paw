/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Tests.Util

/-! # Formats and fields for values

Formats read what they write, as proved, and refuse what is not a value; and the gallery's fields
send the model only values, step within their bounds, and give up invalid text on leaving. -/

namespace Paw.Tests.Input

open Paw

abbrev App := _root_.Gallery.app

def p {α : Type} (f : Format α) (s : String) : Option α := f.parse s.toList
def w {α : Type} (f : Format α) (a : α) : String := String.ofList (f.print a)

def begin : Runtime App :=
  let rt := (Paw.Runtime.start App (Rect.ofXYWH 0 0 (px 640) (px 560)) 0 Env.mock.measure).1
  let at_ := match rt.tree.findKey? "tab-Inputs" with
    | some n => (⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩ : Point)
    | none => ⟨-1, -1⟩
  let rt := (rt.step (.input { kind := .press at_ .primary, time := 100 }) 100).1
  (rt.step (.input { kind := .release at_ .primary, time := 150 }) 150).1

def step (rt : Runtime App) (k : InputKind) (t : Nat) : Runtime App := (rt.step (.input { kind := k, time := t }) t).1

def focus (rt : Runtime App) (k : String) (t : Nat) : Runtime App :=
  match rt.tree.findKey? k with
  | some n =>
    let q : Point := ⟨n.viewport.x0 + px 4, n.viewport.y0 + px 4⟩
    step (step rt (.press q .primary) t) (.release q .primary) (t + 10)
  | none => rt

def retype (rt : Runtime App) (k : String) (s : String) (t : Nat) : Runtime App :=
  step (step (focus rt k t) (.key (.char 'a') { ctrl := true } true) (t + 100)) (.text s) (t + 200)

def border (rt : Runtime App) (k : String) : Option Color :=
  (rt.tree.findKey? k).bind fun n => (n.render rt.env).items.findSome? fun (_, d) => match d with
    | .stroke _ c _ _ => some c
    | _ => none

def tests : TestM Unit := do
  -- Formats.
  checkEq "an integer" (some (-42)) (p Format.int "-42")
  checkEq "leading zeros are read" (some 7) (p Format.int "007")
  checkEq "minus zero is not written, so not read" none (p Format.int "-0")
  checkEq "nor is nothing" none (p Format.int "")
  checkEq "nor a sign alone" none (p Format.int "-")
  checkEq "two places" (some 1250) (p (Format.decimal 2 (by decide)) "12.50")
  checkEq "fewer places are places all the same" (some 150) (p (Format.decimal 2 (by decide)) "1.5")
  checkEq "a small negative" (some (-5)) (p (Format.decimal 2 (by decide)) "-0.05")
  checkEq "too many places" none (p (Format.decimal 2 (by decide)) "1.234")
  checkEq "written with every place" "-0.05" (w (Format.decimal 2 (by decide)) (-5))
  checkEq "a date" (some (2024, 2, 29)) ((p Format.date "2024-02-29").map fun d => (d.year, d.month, d.day))
  checkEq "a day that is not" none ((p Format.date "2023-02-29").map (·.day))
  checkEq "nor a month" none ((p Format.date "2026-13-01").map (·.day))
  checkEq "1900 was not a leap year, 2000 was" (false, true) (Format.leap 1900, Format.leap 2000)
  checkEq "dates are written with two-digit months and days" "2026-03-04" (w Format.date ⟨2026, 3, 4, by decide⟩)
  checkEq "a time" "09:05" (w Format.time ⟨9, 5, by decide⟩)
  checkEq "midnight is 00:00, not 24:00" none ((p Format.time "24:00").map (·.hour))
  checkEq "bounds refuse what is outside them" none ((p (Format.bounded Format.int 0 99) "100").map (·.val))
  checkEq "natural numbers" (some 120) (p Format.nat "120")
  -- A field for any value with a format.
  let field : Node Nat := Ui.inputField Format.nat 5 id "n"
  let t := (field.init 1).1.resize Env.mock (Rect.ofXYWH 0 0 (px 100) (px 30))
  checkEq "a field shows its value as its format writes it" (some "5")
    ((t.state? Widgets.InputState).map (String.ofList ·.text))
  -- Round trips on random values.
  let mut g : Rng := ⟨3⟩
  let mut ok := true
  for _ in [0:300] do
    let (n, g') := g.next 2000001
    g := g'
    let v : Int := (n : Int) - 1000000
    if p Format.int (w Format.int v) != some v then ok := false
    if p (Format.decimal 3 (by decide)) (w (Format.decimal 3 (by decide)) v) != some v then ok := false
  check "what is written reads back, for random values" ok
  -- Fields.
  let rt := begin
  checkEq "the Inputs tab" _root_.Gallery.Page.inputs rt.model.page
  let rt := retype rt "quantity" "42" 1000
  checkEq "a number typed reaches the model" 42 rt.model.quantity.val
  let rt := retype rt "quantity" "4x" 2000
  checkEq "text that is not a number does not" 42 rt.model.quantity.val
  checkEq "and the field is marked" (some Theme.light.error) (border rt "quantity")
  let rt := focus rt "price" 3000
  checkEq "leaving it gives up the text for the model's value" (some "42")
    (((rt.tree.findKey? "quantity").bind (·.state? Widgets.InputState)).map (String.ofList ·.text))
  let rt := retype rt "quantity" "100" 4000
  checkEq "a number out of bounds does not reach it" 42 rt.model.quantity.val
  let rt := step (focus rt "quantity" 5000) (.key .up {} true) 5100
  checkEq "Up steps" 43 rt.model.quantity.val
  let rt := retype rt "quantity" "99" 6000
  let rt := step rt (.key .up {} true) 6300
  checkEq "and stops at the bound" 99 rt.model.quantity.val
  let over := ((rt.tree.findKey? "quantity").map fun n => (⟨n.viewport.x0 + px 4, n.viewport.y0 + px 4⟩ : Point)).getD ⟨0, 0⟩
  let rt := step rt (.wheel over 0 1) 6400
  checkEq "the wheel steps down" 98 rt.model.quantity.val
  let acc := (rt.tree.accessTree rt.env).find? fun a => a.access.role == .spin && a.access.range.isSome
  checkEq "a spin button to assistive technology, with its range" (some (0, 99, 98)) (acc.bind (·.access.range))
  let rt := retype rt "price" "3.5" 7000
  checkEq "a price typed with fewer places" 350 rt.model.price.val
  let rt := retype rt "date" "2024-02-30" 8000
  checkEq "a date that is not a day does not reach the model" (2026, 10, 14)
    (rt.model.date.year, rt.model.date.month, rt.model.date.day)
  let rt := retype rt "date" "2024-02-29" 9000
  checkEq "one that is does" (2024, 2, 29) (rt.model.date.year, rt.model.date.month, rt.model.date.day)
  let rt := retype rt "time" "18:45" 10000
  checkEq "a time" (18, 45) (rt.model.time.hour, rt.model.time.minute)
  let rt := step (focus rt "time" 11000) (.key (.char 'z') { ctrl := true } true) 11100
  checkEq "Ctrl-Z in a field undoes typing" (9, 30) (rt.model.time.hour, rt.model.time.minute)

end Paw.Tests.Input
