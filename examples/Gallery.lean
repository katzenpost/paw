/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw

/-! # Gallery

Every widget Paw has, in one window: a counter, a form with a password, a checkbox, a list whose
rows keep their state as it changes, a scrolled text, two effects that need the user's choice:
opening a link and copying, a menu in a popup that opens an alert and a confirmation, a tooltip,
rows that fade in, a button disabled until it has something to do, a switch to the dark
theme, icons, a picture made by a task, and notes of many lines; and on further tabs, the rest. -/

namespace Gallery

open Paw

/-- The gallery's tabs. -/
inductive Page where
  | basics
  | choices
  | inputs
  deriving Repr, BEq, Inhabited

abbrev Quantity := { x : Int // 0 ≤ x ∧ x ≤ 99 }
/-- A price in cents, at most a thousand. -/
abbrev Price := { x : Int // 0 ≤ x ∧ x ≤ 100000 }

inductive Size where
  | small
  | medium
  | large
  deriving Repr, BEq, Inhabited

inductive Align where
  | left
  | center
  | right
  deriving Repr, BEq, Inhabited

inductive Msg where
  | inc
  | dec
  | name (s : String)
  | pass (s : Secret)
  | agree (b : Bool)
  | draft (s : String)
  | add
  | remove (id : String)
  | reverse
  | openLink
  | copyName
  | quit
  | menu (shown : Bool)
  | about
  | closeAbout
  | askClear
  | clear
  | keep
  | dark (on : Bool)
  | loadPicture
  | notes (s : String)
  | page (p : Page)
  | size (s : Size)
  | align (a : Align)
  | bold (on : Bool)
  | quantity (q : Quantity)
  | price (p : Price)
  | date (d : Format.Date)
  | time (t : Format.Time)
  | picture (img : Except ImageError Image)

structure Model where
  count : Int := 0
  name : String := ""
  pass : Secret := Secret.empty
  agree : Bool := false
  draft : String := ""
  items : List (String × String) := [("1", "apples"), ("2", "pears")]
  nextId : Nat := 3
  opened : Nat := 0
  menu : Bool := false
  about : Option Modal := none
  clearing : Option Modal := none
  dark : Bool := false
  picture : Option Image := none
  notes : String := ""
  page : Page := .basics
  size : Size := .medium
  align : Align := .left
  bold : Bool := false
  quantity : Quantity := ⟨1, by decide⟩
  price : Price := ⟨1250, by decide⟩
  date : Format.Date := ⟨2026, 10, 14, by decide⟩
  time : Format.Time := ⟨9, 30, by decide⟩

instance : BEq Model where
  beq a b := a.count == b.count && a.name == b.name && a.pass.eq b.pass && a.agree == b.agree &&
    a.draft == b.draft && a.items == b.items && a.nextId == b.nextId && a.opened == b.opened &&
    a.menu == b.menu && a.about == b.about && a.clearing == b.clearing && a.dark == b.dark && a.picture == b.picture && a.notes == b.notes && a.page == b.page && a.size == b.size &&
    a.align == b.align && a.bold == b.bold && a.quantity.val == b.quantity.val && a.price.val == b.price.val &&
    a.date == b.date && a.time == b.time

abbrev caps : List Cap := [.openUri, .clipboardWrite, .io]

/-- A picture made in memory: a sunset of 96 × 48 pixels. -/
def sunset : IO (Except ImageError Image) :=
  let (w, h) := (96, 48)
  let px := (List.range (w * h)).foldl (init := ByteArray.emptyWithCapacity (w * h * 4)) fun b i =>
    let (x, y) := ((i % w : Nat), (i / w : Nat))
    let sun := (x - 48 : Int) ^ 2 + (y - 40 : Int) ^ 2 < 196
    let (r, g, bl) := if sun then (250, 210, 60) else if y > 40 then (40, 60, 90)
      else (200 - y * 2, 90 + y, 140)
    ((b.push r.toUInt8).push g.toUInt8 |>.push bl.toUInt8).push 255
  Image.ofRgba w h px

def update : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  | _, .inc => modify fun (m, cs) => ({ m with count := m.count + 1 }, cs)
  | _, .dec => modify fun (m, cs) => ({ m with count := m.count - 1 }, cs)
  | _, .name s => modify fun (m, cs) => ({ m with name := s }, cs)
  | _, .pass s => modify fun (m, cs) => ({ m with pass := s }, cs)
  | _, .agree b => modify fun (m, cs) => ({ m with agree := b }, cs)
  | _, .draft s => modify fun (m, cs) => ({ m with draft := s }, cs)
  | _, .add => modify fun (m, cs) =>
    if m.draft.isEmpty then (m, cs)
    else ({ m with items := m.items ++ [(toString m.nextId, m.draft)], draft := "",
                   nextId := m.nextId + 1 }, cs)
  | _, .remove id => modify fun (m, cs) => ({ m with items := m.items.filter (·.1 != id) }, cs)
  | _, .reverse => modify fun (m, cs) => ({ m with items := m.items.reverse }, cs)
  | .user d, .openLink => do
    if let some e := Effect.openUri? "link" "https://github.com/katzenpost" then
      if h : e.DesignatedBy d then
        emit (.effect d e (by decide) h)
        modify fun (m, cs) => ({ m with opened := m.opened + 1 }, cs)
  | .other, .openLink => pure ()
  | .user d, .copyName => do
    let e := Effect.setClipboard "copy" (SafeText.filter (← get).1.name)
    if h : e.DesignatedBy d then emit (.effect d e (by decide) h)
  | .other, .copyName => pure ()
  | _, .quit => emit .quit
  | _, .menu b => modify fun (m, cs) => ({ m with menu := b }, cs)
  | .user d, .about => modify fun (m, cs) => ({ m with menu := false, about := Modal.open d }, cs)
  | .other, .about => modify fun (m, cs) => ({ m with menu := false }, cs)
  | _, .closeAbout => modify fun (m, cs) => ({ m with about := none }, cs)
  | .user d, .askClear => modify fun (m, cs) => ({ m with menu := false, clearing := Modal.open d }, cs)
  | .other, .askClear => modify fun (m, cs) => ({ m with menu := false }, cs)
  | _, .clear => modify fun (m, cs) => ({ m with items := [], clearing := none }, cs)
  | _, .keep => modify fun (m, cs) => ({ m with clearing := none }, cs)
  | _, .dark on => modify fun (m, cs) => ({ m with dark := on }, cs)
  | _, .loadPicture => emit (.task (.picture <$> sunset) (by decide))
  | _, .picture r => modify fun (m, cs) => ({ m with picture := r.toOption }, cs)
  | _, .notes s => modify fun (m, cs) => ({ m with notes := s }, cs)
  | _, .page p => modify fun (m, cs) => ({ m with page := p }, cs)
  | _, .size x => modify fun (m, cs) => ({ m with size := x }, cs)
  | _, .align a => modify fun (m, cs) => ({ m with align := a }, cs)
  | _, .bold on => modify fun (m, cs) => ({ m with bold := on }, cs)
  | _, .quantity q => modify fun (m, cs) => ({ m with quantity := q }, cs)
  | _, .price p => modify fun (m, cs) => ({ m with price := p }, cs)
  | _, .date d => modify fun (m, cs) => ({ m with date := d }, cs)
  | _, .time t => modify fun (m, cs) => ({ m with time := t }, cs)

/-- Radio buttons, option buttons, a toggle button and separators. -/
def choicesPage (m : Model) : Node Msg :=
  Ui.col [
    Ui.label "Size" (key := "sizeLabel"),
    Ui.row [Ui.radio "Small" Size.small m.size .size "small", Ui.radio "Medium" Size.medium m.size .size "medium",
      Ui.radio "Large" Size.large m.size .size "large"] (px 16),
    Ui.separator,
    Ui.label "Alignment",
    Ui.row [Ui.optionButton "Left" Align.left m.align .align "left",
      Ui.optionButton "Center" Align.center m.align .align "center",
      Ui.optionButton "Right" Align.right m.align .align "right", Ui.separator (vertical := true),
      Ui.toggleButton "Bold" m.bold .bold "bold"]] (px 8)

/-- Fields for numbers, dates and times, which take only text that reads as one. -/
def inputsPage (m : Model) : Node Msg :=
  let field (caption : String) (n : Node Msg) := Ui.row [Ui.width (px 100) (Ui.label caption), Ui.width (px 160) n]
  Ui.col [
    field "Quantity" (Ui.numericField m.quantity .quantity "quantity"),
    field "Price" (Ui.decimalField 2 (by decide) m.price .price "price"),
    field "Date" (Ui.dateField m.date .date "date"),
    field "Time" (Ui.timeField m.time .time "time"),
    Ui.label s!"{m.quantity.val} at {m.price.val / 100}.{m.price.val % 100 / 10}{m.price.val % 10} on {m.date.year}-{m.date.month}-{m.date.day} at {m.time.hour}:{m.time.minute}" "summary"] (px 8)

/-- The first page: what the gallery had before it had tabs. -/
def basicsPage (m : Model) : Node Msg :=
  Ui.col [
    Ui.row [Ui.button "−" .dec "dec", Ui.label s!"count: {m.count}" "count", Ui.tooltip "Adds one to the count" (Ui.button "+" .inc "inc"),
      Ui.spacer, Ui.checkbox "Dark" m.dark .dark "dark",
      Ui.popup m.menu (Ui.button "More" (.menu true) "more")
        (Ui.col [Ui.button "About" .about "about", Ui.button "Clear list" .askClear "clear"])
        (.menu false) "menu"],
    Ui.row [Ui.label "Name", Ui.textField m.name .name { placeholder := SafeText.trusted "your name" } "name"],
    Ui.row [Ui.label "Password", Ui.passwordField m.pass .pass "pass"],
    Ui.checkbox "I agree" m.agree .agree "agree",
    Ui.row [Ui.textField m.draft .draft { placeholder := SafeText.trusted "new item" } "draft",
      Ui.enabled (!m.draft.isEmpty) (Ui.button "Add" .add "add"), Ui.button "Reverse" .reverse "reverse"],
    Ui.list m.items (·.1) fun (id, s) => Ui.fadeIn <|
      Ui.row [Ui.text (SafeText.filter s), Ui.spacer, Ui.button "Remove" (.remove id) s!"remove-{id}"],
    Ui.height (px 120) <| Ui.scroll (Ui.paragraph (String.intercalate "\n" ((List.range 12).map fun i =>
      s!"Line {i + 1} of a text longer than its box."))) "scroll",
    Ui.row ([Ui.icon .check, Ui.icon .warning, Ui.icon .chevronRight, Ui.button "Load picture" .loadPicture "load"] ++
      (m.picture.toList.map fun img =>
        Ui.width (px 56) (Ui.height (px 28) (Ui.image img (.text (SafeName.filter "A sunset")) .fill "picture")))),
    Ui.row [Ui.button "Open link" .openLink "link", Ui.button "Copy name" .copyName "copy",
      Ui.label s!"links opened: {m.opened}" "opened"],
    Ui.textArea m.notes .notes { rows := 3, placeholder := SafeText.trusted "notes" } "notes"]

def view (m : Model) : Node Msg :=
  Ui.keystroke [({ key := .char 'q', ctrl := true }, .quit)] <|
  Ui.themed (if m.dark then Theme.dark else Theme.light) <| Ui.pad (px 8) <| Ui.col ([
    Ui.tabs m.page .page [("Basics", .basics, basicsPage m), ("Choices", .choices, choicesPage m),
      ("Inputs", .inputs, inputsPage m)]] ++
    (m.about.toList.map fun t => Ui.alert t (SafeName.filter "About Paw")
      "A GUI library for Lean, after monomer." .closeAbout) ++
    (m.clearing.toList.map fun t => Ui.confirm t (SafeName.filter "Clear the list?")
      s!"This removes all {m.items.length} items. It cannot be undone." .clear .keep (accept := "Clear")))

def app : App caps := { Model := Model, Msg := Msg, init := {}, update, view }

end Gallery
