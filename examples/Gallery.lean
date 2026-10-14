/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw

/-! # Gallery

Every widget Paw has, in one window: a counter, a form with a password, a checkbox, a list whose
rows keep their state as it changes, a scrolled text, two effects that need the user's choice:
opening a link and copying, and a menu in a popup that opens an alert and a confirmation. -/

namespace Gallery

open Paw

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

instance : BEq Model where
  beq a b := a.count == b.count && a.name == b.name && a.pass.eq b.pass && a.agree == b.agree &&
    a.draft == b.draft && a.items == b.items && a.nextId == b.nextId && a.opened == b.opened &&
    a.menu == b.menu && a.about == b.about && a.clearing == b.clearing

abbrev caps : List Cap := [.openUri, .clipboardWrite]

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

def view (m : Model) : Node Msg :=
  Ui.keystroke [({ key := .char 'q', ctrl := true }, .quit)] <| Ui.pad (px 8) <| Ui.col ([
    Ui.row [Ui.button "−" .dec "dec", Ui.label s!"count: {m.count}" "count", Ui.button "+" .inc "inc",
      Ui.spacer,
      Ui.popup m.menu (Ui.button "More" (.menu true) "more")
        (Ui.col [Ui.button "About" .about "about", Ui.button "Clear list" .askClear "clear"])
        (.menu false) "menu"],
    Ui.row [Ui.label "Name", Ui.textField m.name .name { placeholder := SafeText.trusted "your name" } "name"],
    Ui.row [Ui.label "Password", Ui.passwordField m.pass .pass "pass"],
    Ui.checkbox "I agree" m.agree .agree "agree",
    Ui.row [Ui.textField m.draft .draft { placeholder := SafeText.trusted "new item" } "draft",
      Ui.button "Add" .add "add", Ui.button "Reverse" .reverse "reverse"],
    Ui.list m.items (·.1) fun (id, s) =>
      Ui.row [Ui.text (SafeText.filter s), Ui.spacer, Ui.button "Remove" (.remove id) s!"remove-{id}"],
    Ui.height (px 120) <| Ui.scroll (Ui.paragraph (String.intercalate "\n" ((List.range 12).map fun i =>
      s!"Line {i + 1} of a text longer than its box."))) "scroll",
    Ui.row [Ui.button "Open link" .openLink "link", Ui.button "Copy name" .copyName "copy",
      Ui.label s!"links opened: {m.opened}" "opened"]] ++
    (m.about.toList.map fun t => Ui.alert t (SafeName.filter "About Paw")
      "A GUI library for Lean, after monomer." .closeAbout) ++
    (m.clearing.toList.map fun t => Ui.confirm t (SafeName.filter "Clear the list?")
      s!"This removes all {m.items.length} items. It cannot be undone." .clear .keep (accept := "Clear")))

def app : App caps := { Model := Model, Msg := Msg, init := {}, update, view }

end Gallery
