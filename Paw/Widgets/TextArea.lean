/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.TextField

/-! # Text areas

Text of many lines over a value from the model, edited as a text field is, with the same `Edit`
functions over the whole text, newlines and all. Each line is wrapped to the area's width, so
the text is shown as rows; a wrapped line's rows put back together are the line (`Wrap.wrap_flatten`),
so a position in the text is a row and a place in it. Up and Down keep the caret's x across rows
of different lengths. The area scrolls itself to keep the caret in view.

What is typed or pasted loses control characters but keeps newlines, and tabs become spaces. -/

namespace Paw.Widgets

/-- What typing or pasting may put in a text area: newlines, but no other control characters, and
tabs as spaces. -/
def cleanText (s : String) : List Char :=
  s.toList.filterMap fun c =>
    if c == '\n' then some c
    else if c == '\t' then some ' '
    else if Text.control c.toNat then none
    else some c

/-- A row of a text area: where it starts in the text, and its characters. -/
structure Row where
  start : Nat
  chars : List Char
  deriving Repr, DecidableEq, Inhabited

/-- `cs` as rows, each line wrapped to `width` by `ws`. -/
def rows (ws : Widths) (width : Int) (cs : List Char) : List Row :=
  let lines := cs.splitOn '\n'
  let (_, rs) := lines.foldl (init := (0, (#[] : Array Row))) fun (start, acc) line =>
    let parts := if line.isEmpty then [[]] else Wrap.wrap width ws.word ws.char line
    let (pos, acc) := parts.foldl (fun (pos, acc) p => (pos + p.length, acc.push ⟨pos, p⟩)) (start, acc)
    (pos + 1, acc)
  rs.toList

/-- Lines already wrapped, at one width: an edit changes a line or two, and only those are wrapped
again. -/
structure RowCache where
  width : Int := -1
  lines : Std.HashMap String (List (List Char)) := {}
  deriving Inhabited

/-- `cs` as rows at `width`, taking lines already wrapped from `cache`; with `keep`, also a cache of
exactly the lines of `cs`, so that it never holds more than the text does. -/
def rowsCached (env : Env) (style : TextStyle) (width : Int) (cache : RowCache) (cs : List Char)
    (keep : Bool := true) : List Row × RowCache :=
  let cache := if cache.width == width then cache else { width }
  let lines := cs.splitOn '\n'
  let missing := lines.filter fun l => !cache.lines.contains (String.ofList l)
  let ws := Widths.of env style (missing.map SafeText.filterChars)
  let (_, rs, fresh) := lines.foldl (init := (0, (#[] : Array Row), (Std.HashMap.emptyWithCapacity
      (if keep then lines.length else 0) : Std.HashMap String (List (List Char))))) fun (start, acc, fresh) line =>
    let key := String.ofList line
    let parts := match cache.lines[key]? with
      | some ps => ps
      | none => if line.isEmpty then [[]] else Wrap.wrap width ws.word ws.char line
    let (pos, acc) := parts.foldl (fun (pos, acc) p => (pos + p.length, acc.push ⟨pos, p⟩)) (start, acc)
    (pos + 1, acc, if keep then fresh.insert key parts else fresh)
  (rs.toList, { width, lines := fresh })

/-- The row the position `i` is on: the last that starts at or before it. -/
def rowOf (rs : List Row) (i : Nat) : Nat :=
  (rs.zipIdx.foldl (fun best (r, k) => if r.start ≤ i then k else best) 0)

structure TextAreaState where
  cursor : Nat := 0
  anchor : Option Nat := none
  since : Nat := 0
  history : History (List Char × Nat) := {}
  /-- The caret's x as Up and Down move it, kept across shorter rows. -/
  goalX : Option Int := none
  /-- How far the rows are scrolled up. -/
  offset : Int := 0
  /-- Text an input method is composing at the caret, and its cursor. -/
  preedit : Option (SafeText × Nat) := none
  /-- The text's lines as last wrapped. -/
  cache : RowCache := {}
  /-- The rows of the text last edited, at a width: used while the value is still that text. -/
  laid : Option (String × Int × List Row) := none
  deriving TypeName, Inhabited

structure TextAreaCfg where
  maxLength : Nat := 100000
  /-- How many rows it asks room for. -/
  rows : Nat := 4
  placeholder : SafeText := SafeText.empty
  deriving Inhabited

/-- A text of many lines showing `value`, reporting edits with `onChange`. -/
def textArea {Msg : Type} (value : String) (onChange : String → Msg) (cfg : TextAreaCfg := {}) :
    Widget Msg :=
  let chars := value.toList
  let edit (st : TextAreaState) : Edit := Edit.clamp { value := chars, cursor := st.cursor, anchor := st.anchor }
  -- The rectangle the rows are in, the rows, the height of one, and the width of the start of one.
  let inner (env : Env) (v : Rect) : Rect :=
    let (px', py) := env.theme.textField.padding
    v.shrink px' py px' py
  let layout (env : Env) (v : Rect) (st : TextAreaState) : List Row × Int :=
    let width := (inner env v).width
    let rs := match st.laid with
      | some (t, w, rs) => if w == width && t == value then rs
        else (rowsCached env (textStyle env) width st.cache chars (keep := false)).1
      | none => (rowsCached env (textStyle env) width st.cache chars (keep := false)).1
    (rs, lineHeight env (textStyle env))
  let widthOf (env : Env) (cs : List Char) : Int := (env.measure (textStyle env) (SafeText.filter (String.ofList cs))).1
  -- The offset that keeps the caret's row in view.
  let follow (env : Env) (v : Rect) (rs : List Row) (lh : Int) (cursor : Nat) (offset : Int) : Int :=
    let y := (rowOf rs cursor : Int) * lh
    let h := (inner env v).height
    let offset := if y < offset then y else if y + lh > offset + h then y + lh - h else offset
    max 0 (min offset (max 0 ((rs.length : Int) * lh - h)))
  let result (env : Env) (v : Rect) (st : TextAreaState) (e : Edit) (extra : List (Req Msg) := [])
      (goalX : Option Int := none) : Option (TextAreaState × List (Req Msg)) :=
    let same := e.value == chars
    let changed := if same then [] else [Req.emit (onChange (String.ofList e.value))]
    let history := if same then st.history else st.history.record (chars, st.cursor)
    -- Rows of the text after the edit, to keep its caret in view.
    let width := (inner env v).width
    let fresh := match st.laid with
      | some (t, w, rs) => if same && w == width && t == value then some rs else none
      | none => none
    let (rs, cache) := match fresh with
      | some rs => (rs, st.cache)
      | none => rowsCached env (textStyle env) width st.cache e.value
    let laid := some (if same then value else String.ofList e.value, width, rs)
    let offset := follow env v rs (lineHeight env (textStyle env)) e.cursor st.offset
    let st' : TextAreaState := { cursor := e.cursor, anchor := e.anchor, since := env.now, history, goalX, offset,
                                 preedit := none, cache, laid }
    some (st', extra ++ changed)
  -- The position in the row `k` of `rs` nearest `x` from its start.
  let nearest (env : Env) (rs : List Row) (k : Nat) (x : Int) : Nat :=
    match rs[k]? with
    | some r => r.start + indexAt (fun t => (env.measure (textStyle env) t).1) r.chars x
    | none => if k == 0 then 0 else chars.length
  Widget.Spec.build (σ := TextAreaState) {
    kind := "textArea"
    init := { cursor := chars.length }
    merge := fun st =>
      { st with cursor := min st.cursor chars.length, anchor := st.anchor.map (min · chars.length) }
    sizeReq := fun env _ =>
      let lh := lineHeight env (textStyle env)
      (SizeReq.minSize (px 160).toNat,
       SizeReq.minSize (cfg.rows * lh + 2 * env.theme.textField.padding.2).toNat)
    render := fun env st v =>
      let t := env.theme
      let s := env.look t.textField
      let style := { textStyle env with color := s.fg }
      let box := inner env v
      let (rs, lh) := layout env v st
      let e := edit st
      let y (k : Nat) := box.y0 + (k : Int) * lh - st.offset
      -- Only rows that can be seen are drawn.
      let first := (st.offset / max lh 1).toNat
      let seen := (rs.zipIdx.drop first).take ((box.height / max lh 1).toNat + 2)
      let text := if chars.isEmpty then [Draw.text ⟨box.x0, box.y0⟩ cfg.placeholder { style with color := t.muted }]
        else seen.map fun (r, k) => Draw.text ⟨box.x0, y k⟩ (SafeText.filter (String.ofList r.chars)) style
      let sel := match e.selection with
        | some (lo, hi) => seen.filterMap fun (r, k) =>
          let a := max lo r.start
          let b := min hi (r.start + r.chars.length)
          if a < b || (a == b && lo ≤ r.start && r.start + r.chars.length < hi) then
            let x0 := box.x0 + widthOf env (r.chars.take (a - r.start))
            let x1 := box.x0 + widthOf env (r.chars.take (b - r.start)) + (if b == r.start + r.chars.length && b < hi then px 4 else 0)
            some (Draw.fill (Rect.ofXYWH x0 (y k) (x1 - x0) lh) (Color.rgba t.accent.r t.accent.g t.accent.b 80) 0)
          else none
        | none => []
      let k := rowOf rs e.cursor
      let caretAt : Rect := match rs[k]? with
        | some r => Rect.ofXYWH (box.x0 + widthOf env (r.chars.take (e.cursor - r.start))) (y k) (px 1) lh
        | none => Rect.ofXYWH box.x0 box.y0 (px 1) lh
      let caret := if caretShown env st.since then [Draw.fill caretAt s.fg 0] else []
      let composing := match st.preedit with
        | some (p, _) => Draw.fill (Rect.ofXYWH caretAt.x0 caretAt.y0 (env.measure style p).1 lh) s.bg 0 ::
            preeditDraw env caretAt caretAt.x0 p style
        | none => []
      -- The text is clipped to the inside of the frame, then everything to the box.
      Scene.inBox v (frame v s) ++ Scene.inBox (box.inter v) (sel ++ text ++ caret ++ composing)
    render_within := fun _ _ v =>
      Scene.append_within (Scene.inBox_within v _)
        (Scene.Within.mono (Scene.inBox_within _ _) (Rect.inter_within _ _))
    handle := fun env st v ev =>
      let e := edit st
      let go (e : Edit) (extra : List (Req Msg) := []) (goalX : Option Int := none) :=
        result env v st e extra goalX
      let (rs, lh) := layout env v st
      let k := rowOf rs e.cursor
      let x := match st.goalX with
        | some x => x
        | none => match rs[k]? with
          | some r => widthOf env (r.chars.take (e.cursor - r.start))
          | none => 0
      let page := max 1 ((inner env v).height / max lh 1).toNat
      let travel (to : Option ((List Char × Nat) × History (List Char × Nat))) : Option (TextAreaState × List (Req Msg)) :=
        match to with
        | some ((v', c), history) =>
          some ({ st with cursor := c, anchor := none, since := env.now, history, goalX := none },
            [Req.emit (onChange (String.ofList v'))])
        | none => some (st, [])
      match ev with
      | .text s | .paste s => go (e.insert (cleanText s) cfg.maxLength)
      -- With Ctrl, Enter and paging are left to the widgets around, for bindings such as sending.
      | .key .enter m true => if m.ctrl then none else go (e.insert ['\n'] cfg.maxLength)
      | .key .backspace m true => go (if m.ctrl then e.deleteWordBack else e.backspace)
      | .key .delete m true => go (if m.ctrl then e.deleteWordForward else e.delete)
      | .key .left m true => go (if m.ctrl then e.wordLeft m.shift else e.left m.shift)
      | .key .right m true => go (if m.ctrl then e.wordRight m.shift else e.right m.shift)
      | .key .up m true => go (e.moveTo (if k == 0 then 0 else nearest env rs (k - 1) x) m.shift) (goalX := some x)
      | .key .down m true =>
        go (e.moveTo (if k + 1 ≥ rs.length then chars.length else nearest env rs (k + 1) x) m.shift) (goalX := some x)
      | .key .pageUp m true => if m.ctrl then none else go (e.moveTo (nearest env rs (k - page) x) m.shift) (goalX := some x)
      | .key .pageDown m true =>
        if m.ctrl then none else go (e.moveTo (if k + page ≥ rs.length then chars.length else nearest env rs (k + page) x) m.shift)
          (goalX := some x)
      | .key .home m true => go (e.moveTo (if m.ctrl then 0 else Edit.lineStart chars e.cursor) m.shift)
      | .key .end_ m true => go (e.moveTo (if m.ctrl then chars.length else Edit.lineEnd chars e.cursor) m.shift)
      | .key (.char 'a') m true => if m.ctrl then go e.selectAll else none
      | .key (.char 'c') m true =>
        if m.ctrl then go e [.copy (SafeText.filter (String.ofList e.selected))] else none
      | .key (.char 'x') m true =>
        if m.ctrl then go e.deleteSelection [.copy (SafeText.filter (String.ofList e.selected))] else none
      | .key (.char 'z') m true =>
        if !m.ctrl then none
        else if m.shift then travel (st.history.redo (chars, st.cursor)) else travel (st.history.undo (chars, st.cursor))
      | .key (.char 'Z') m true | .key (.char 'y') m true =>
        if m.ctrl then travel (st.history.redo (chars, st.cursor)) else none
      | .press p .primary =>
        let box := inner env v
        let row := ((p.y - box.y0 + st.offset) / max lh 1).toNat
        go (e.moveTo (nearest env rs (min row (rs.length - 1)) (p.x - box.x0)) false)
      | .wheel _ _ dy =>
        let maxOff := max 0 ((rs.length : Int) * lh - (inner env v).height)
        some ({ st with offset := max 0 (min maxOff (st.offset + dy * lh * 3)) }, [])
      | .preedit p c => some ({ st with preedit := if p.text.isEmpty then none else some (p, c) }, [])
      | .focus => some ({ st with since := env.now }, [])
      | .blur => some ({ st with preedit := none }, [])
      | .tick _ | .enter _ | .leave _ => some (st, [])
      | _ => none
    focusable := true
    ime := some fun env st v =>
      let box := inner env v
      let (rs, lh) := layout env v st
      let e := edit st
      let k := rowOf rs e.cursor
      match rs[k]? with
      | some r => Rect.ofXYWH (box.x0 + widthOf env (r.chars.take (e.cursor - r.start))) (box.y0 + (k : Int) * lh - st.offset) (px 1) lh
      | none => Rect.ofXYWH box.x0 box.y0 (px 1) lh
    every := some fun env _ => if env.isFocused && env.windowFocused then some blinkMs else none
    cursor := fun env _ => (env.look env.theme.textField).cursor
    access := fun _ _ =>
      some { role := .textInput, name := cfg.placeholder, value := some (joinLines (SafeText.lines value)) } }

end Paw.Widgets
