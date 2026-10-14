/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tree
import Std.Data.HashMap

/-! # Routing input

The router turns platform input into events for widgets, as monomer's handlers do: keys, text and
pastes go to the focused widget; presses, moves and the wheel to the widget under the pointer; a
release to the widget pressed, followed by a click if the pointer is still on it.

It also decides when a click or a key counts as the user choosing the widget it reaches. Only then
does the delivery carry a `Designation`, which only this module can make, and which effects that
use authority require. A click or key designates nothing when:

- the platform says it was synthetic, sent by another program rather than typed or clicked;
- the platform says another app's window covered the widget;
- the widget appeared or moved less than `stableMs` before, so it may have slid under a pointer
  aimed at something else;
- for a key, focus reached the widget less than `stableMs` before, so typing meant for elsewhere
  may have followed it.

While an overlay is open, the topmost one takes the pointer: hits are found only within it
(`overlay_hit`), and a press outside it dismisses it and reaches nothing else (`press_outside`).
Tab moves focus only among its widgets, and Escape goes to it. A modal takes the keyboard too:
keys go to its focused widget, or to the modal itself if focus is outside it, and text for a
widget beneath it is dropped. An overlay's widgets are new when it opens, so for `stableMs`
nothing in it can be designated. A modal may open only while the input whose designation made its
`Modal` token is being handled; any other is refused, and never reached. -/

namespace Paw

/-- That the user chose `target`, a widget with `key`, with the input numbered `serial`. Only the
router makes these. -/
structure Designation where
  private mk ::
  serial : Nat
  target : WidgetId
  key : Option String
  time : Nat
  deriving Repr, DecidableEq

/-- That the user opened a modal dialog, with the input numbered `serial`. Only `Modal.open` makes
one, from a designation, so a dialog is opened only by the user's choice; and the router lets one
open only while handling the input that made it, so a token kept from earlier opens nothing. -/
structure Modal where
  private mk ::
  serial : Nat
  time : Nat
  deriving Repr, DecidableEq, TypeName

/-- A modal dialog, opened by the input `d` came with. -/
def Modal.open (d : Designation) : Modal := ⟨d.serial, d.time⟩

inductive InputKind where
  | press (p : Point) (b : MouseButton)
  | release (p : Point) (b : MouseButton)
  | move (p : Point)
  | wheel (p : Point) (dx dy : Int)
  | key (k : Key) (m : Mods) (pressed : Bool)
  | text (s : String)
  | paste (s : String)
  /-- Text an input method is composing, with its cursor in characters. -/
  | preedit (s : String) (cursor : Nat)
  /-- The pointer left the window. -/
  | leaveWindow
  deriving Repr, DecidableEq, Inhabited

/-- Keys, text and pastes: input from the keyboard. -/
def InputKind.keyboard : InputKind → Bool
  | .key .. | .text _ | .paste _ | .preedit .. => true
  | _ => false

/-- Input from the platform. -/
structure Input where
  kind : InputKind
  /-- Milliseconds since the app started. -/
  time : Nat
  /-- Sent by another program, such as an X11 `SendEvent`. -/
  synthetic : Bool := false
  /-- Another app's window covered ours where this happened. -/
  obscured : Bool := false
  deriving Repr, DecidableEq, Inhabited

/-- An event for a widget. -/
structure Delivery where
  target : WidgetId
  event : Event
  designation : Option Designation := none
  deriving Repr, DecidableEq

/-- What a draggable widget keeps: the value it gives a drop. -/
structure DragPayload where
  payload : Dynamic
  deriving TypeName

/-- A drag: the widget dragged from, where the press was, where the pointer is, and whether it has
moved far enough to be a drag rather than a click. -/
structure Drag where
  source : WidgetId
  start : Point
  at_ : Point
  active : Bool := false
  deriving Repr, DecidableEq

/-- How far the pointer moves, in units, before a press on something draggable is a drag. -/
def dragDistance : Int := px 4

structure Router where
  focused : Option WidgetId := none
  /-- When focus last moved. -/
  focusedAt : Nat := 0
  hovered : Option WidgetId := none
  pressed : Option WidgetId := none
  /-- The last click: its widget, time and count. -/
  lastClick : Option (WidgetId × Nat × Nat) := none
  /-- Each visible widget's box, and since when it has had it. -/
  placed : Std.HashMap WidgetId (Rect × Nat) := {}
  /-- Each widget's path from the root, as child indices, for delivering to it directly. -/
  paths : Std.HashMap WidgetId (List Nat) := {}
  /-- The topmost open overlay, and its kind. -/
  overlay : Option (WidgetId × Overlay) := none
  /-- The serial of the input being handled, if it designated something: a modal whose token
  names it may open. -/
  consent : Option Nat := none
  /-- Open modals the router let open. -/
  opened : Std.HashSet WidgetId := {}
  /-- Modals that opened other than by the user's input, and overlays inside them: never drawn,
  never reached. -/
  refused : Std.HashSet WidgetId := {}
  /-- The overlays to draw, bottom first, with their paths and kinds: those open and not refused. -/
  shown : Array (WidgetId × List Nat × Overlay) := #[]
  /-- Widgets that want ticks: how often, and when the next is due. -/
  ticks : Std.HashMap WidgetId (Nat × Nat) := {}
  /-- When the pointer came to rest on the hovered widget. -/
  hoverSince : Nat := 0
  /-- How long the pointer rests on something before its tooltip shows. -/
  tipMs : Nat := 1000
  /-- A press on something draggable, and the drag it may become. -/
  drag : Option Drag := none
  /-- What the last input dropped: the widget it was dragged from. -/
  dropped : Option WidgetId := none
  /-- Inputs routed so far. -/
  serial : Nat := 0
  stableMs : Nat := 500
  doubleClickMs : Nat := 400

namespace Router

variable {Msg : Type}

/-- Notes where every widget is at `now`, after a layout, and its path for delivering to it, and
which overlays are open. -/
def observe (rt : Router) (tree : Node Msg) (now : Nat) (env : Env := Env.mock) : Router :=
  let index := tree.index { env with now }
  let idx := index.nodes
  let (placed, paths) := idx.foldl (init := (Std.HashMap.emptyWithCapacity idx.size,
      Std.HashMap.emptyWithCapacity idx.size))
    fun ((placed : Std.HashMap WidgetId (Rect × Nat)), (paths : Std.HashMap WidgetId (List Nat)))
        (id, r, path, moving) =>
      let since := match rt.placed[id]? with
        | some (r', t) => if r' == r && !moving then t else now
        | none => now
      (placed.insert id (r, since), paths.insert id path)
  -- A modal may open only with a token from the input being handled.
  let (ok, shown, opened, refused, _) := index.overlays.foldl
    (init := (([] : List (WidgetId × Overlay)), (#[] : Array (WidgetId × List Nat × Overlay)),
      ({} : Std.HashSet WidgetId), ({} : Std.HashSet WidgetId), ([] : List (List Nat))))
    fun (ok, shown, opened, refused, refusedPaths) (o, path) =>
      let refuse := (ok, shown, opened, refused.insert o.id, path :: refusedPaths)
      if refusedPaths.any (·.isPrefixOf path) then refuse
      else match o.info.overlay with
        | some .modal =>
          if rt.opened.contains o.id ||
              (!rt.refused.contains o.id && (o.state? Modal).any (some ·.serial == rt.consent)) then
            ((o.id, .modal) :: ok, shown.push (o.id, path, .modal), opened.insert o.id, refused, refusedPaths)
          else refuse
        -- A tooltip takes no input, so it is never the overlay input goes to.
        | some .tip => (ok, shown.push (o.id, path, .tip), opened, refused, refusedPaths)
        | some k => ((o.id, k) :: ok, shown.push (o.id, path, k), opened, refused, refusedPaths)
        | none => (ok, shown, opened, refused, refusedPaths)
  -- Focus, hover and press on a widget that left the tree go with it. One scrolled out of view is
  -- not in `paths` but is still in the tree.
  let here (id : Option WidgetId) := id.filter fun i => paths.contains i || (tree.find? i).isSome
  -- A ticker keeps its next tick if it still ticks as often; a new one is due a period from now.
  let ticks := index.tickers.foldl (init := Std.HashMap.emptyWithCapacity index.tickers.size)
    fun (m : Std.HashMap WidgetId (Nat × Nat)) (id, ms) =>
      let due := match rt.ticks[id]? with
        | some (ms', d) => if ms' == ms then d else now + ms
        | none => now + ms
      m.insert id (ms, due)
  { rt with placed, paths, opened, refused, shown, ticks, overlay := ok.head?, focused := here rt.focused,
            hovered := here rt.hovered, pressed := here rt.pressed }

/-- Whether the pointer or focus is in the parent of the overlay at `path`: its anchor. -/
def inAnchor (rt : Router) (path : List Nat) (id : Option WidgetId) : Bool :=
  (id.bind (rt.paths[·]?)).any path.dropLast.isPrefixOf

/-- The tooltip at `path` shows at `now`: the pointer has rested on its anchor for `tipMs`, or
focus is in it. -/
def tipShown (rt : Router) (path : List Nat) (now : Nat) : Bool :=
  (rt.inAnchor path rt.hovered && now ≥ rt.hoverSince + rt.tipMs) || rt.inAnchor path rt.focused

/-- When tooltips waiting for the pointer to rest are due to show. -/
def tipDeadlines (rt : Router) (now : Nat) : List Nat :=
  rt.shown.toList.filterMap fun (_, path, k) =>
    if k == .tip && rt.inAnchor path rt.hovered && !rt.tipShown path now then
      some (rt.hoverSince + rt.tipMs)
    else none

/-- The topmost open overlay's node. -/
def overlayNode (rt : Router) (tree : Node Msg) : Option (Node Msg) :=
  rt.overlay.bind fun (o, _) => rt.paths[o]?.bind (tree.get? ·)

/-- The widget is in the topmost open overlay, or none is open. -/
def trapped (rt : Router) (id : WidgetId) : Bool :=
  match rt.overlay with
  | none => true
  | some (o, _) => match rt.paths[o]?, rt.paths[id]? with
    | some po, some pi => po.isPrefixOf pi
    | _, _ => false

/-- The node with `id`, or the nearest around it, whose widget is of `kind`. -/
def around (rt : Router) (tree : Node Msg) (id : WidgetId) (kind : String) : Option (Node Msg) :=
  (rt.paths[id]?).bind fun path =>
    (List.range (path.length + 1)).reverse.findSome? fun k => (tree.get? (path.take k)).filter (·.kind == kind)

/-- The topmost visible node at `p`: in the topmost overlay if one is open, else in the tree. -/
def hitAt (rt : Router) (tree : Node Msg) (p : Point) : Option (Node Msg) :=
  match rt.overlay with
  | some _ => (rt.overlayNode tree).bind (·.hit? p)
  | none => tree.hit? p

/-- While an overlay is open, the pointer reaches only widgets in it. -/
theorem overlay_hit {rt : Router} {tree o m : Node Msg} {p : Point}
    (ho : rt.overlayNode tree = some o) (h : rt.hitAt tree p = some m) : m.id ∈ o.ids := by
  unfold hitAt at h
  split at h
  · rw [ho] at h
    exact Node.hit_mem_ids p o m h
  · rename_i hn
    simp [overlayNode, hn] at ho

/-- The widget has kept its box since `stableMs` before `now`. -/
def stable (rt : Router) (id : WidgetId) (now : Nat) : Bool :=
  match rt.placed[id]? with
  | some (_, t) => now ≥ t + rt.stableMs
  | none => false

/-- A designation of `target`, with `key`, by input `i`, numbered `serial`, if the checks pass. -/
def designate (rt : Router) (serial : Nat) (i : Input) (target : WidgetId) (key : Option String)
    (isKey : Bool) : Option Designation :=
  let focusHeld := !isKey || i.time ≥ rt.focusedAt + rt.stableMs
  if !i.synthetic && !i.obscured && rt.stable target i.time && focusHeld then
    some ⟨serial, target, key, i.time⟩
  else none

/-- Moves focus to `to`, with blur and focus events. -/
def moveFocus (rt : Router) (to : Option WidgetId) (now : Nat) : Router × List Delivery :=
  if to == rt.focused then (rt, [])
  else
    let blur := rt.focused.toList.map fun id => { target := id, event := .blur }
    let focus := to.toList.map fun id => { target := id, event := .focus }
    ({ rt with focused := to, focusedAt := now }, blur ++ focus)

/-- The id after `current` in `order`, wrapping around, or the first. -/
def pick (order : List WidgetId) (current : Option WidgetId) : Option WidgetId :=
  match current.bind (order.idxOf? ·) with
  | some i => order[(i + 1) % order.length]?
  | none => order.head?

theorem pick_mem {order : List WidgetId} {current : Option WidgetId} {id : WidgetId}
    (h : pick order current = some id) : id ∈ order := by
  unfold pick at h
  split at h
  · exact List.mem_of_getElem? h
  · exact List.mem_of_mem_head? h

/-- The focusable after (or before) the focused one, wrapping around. -/
def nextFocus (order : List WidgetId) (current : Option WidgetId) (back : Bool) : Option WidgetId :=
  pick (if back then order.reverse else order) current

/-- Focus only ever moves to a widget in the focus order: visible, enabled and focusable. -/
theorem nextFocus_mem {order : List WidgetId} {current : Option WidgetId} {back : Bool}
    {id : WidgetId} (h : nextFocus order current back = some id) : id ∈ order := by
  have := pick_mem h
  split at this
  · exact List.mem_reverse.mp this
  · exact this

def hover (rt : Router) (to : Option WidgetId) (p : Point) (now : Nat) : Router × List Delivery :=
  if to == rt.hovered then (rt, [])
  else
    let leave := rt.hovered.toList.map fun id => { target := id, event := .leave p }
    let enter := to.toList.map fun id => { target := id, event := .enter p }
    ({ rt with hovered := to, hoverSince := now }, leave ++ enter)

/-- Routes one input through `tree`: the router after it, and the events it gives widgets. -/
def route (rt : Router) (tree : Node Msg) (i : Input) : Router × List Delivery :=
  let serial := rt.serial
  let rt := { rt with serial := rt.serial + 1, consent := none, dropped := none }
  let at? (p : Point) := (rt.hitAt tree p).filter (·.enabled)
  -- Where keys go: the focused widget, unless a modal is open and focus is outside it, when they go
  -- to the modal; Escape goes to the topmost overlay unless focus is in it.
  let inside := (rt.focused.filter rt.trapped)
  let keyTarget (k : Key) : Option WidgetId := match rt.overlay with
    | some (o, .modal) => inside.orElse fun _ => some o
    | some (o, _) => if k == .escape then inside.orElse fun _ => some o else rt.focused
    | none => rt.focused
  -- Text goes to the focused widget, unless a modal is open and focus is outside it.
  let textTarget := match rt.overlay with
    | some (_, .modal) => inside
    | _ => rt.focused
  match i.kind with
  | .press p b =>
    match at? p with
    | some n =>
      let (rt, focus) := if n.focusable then rt.moveFocus (some n.id) i.time else (rt, [])
      let drag := if b == .primary then (rt.around tree n.id "draggable").map fun s => { source := s.id, start := p, at_ := p }
        else none
      ({ rt with pressed := some n.id, drag }, focus ++ [{ target := n.id, event := .press p b }])
    | none =>
      ({ rt with pressed := none, drag := none }, rt.overlay.toList.map fun (o, _) => { target := o, event := .dismiss })
  | .release p b =>
    match rt.pressed with
    | some id =>
      let rel : Delivery := { target := id, event := .release p b }
      let drag := rt.drag
      let rt := { rt with pressed := none, drag := none }
      -- A drag ends in a drop on the target under the pointer, which the user chose as they would
      -- by clicking it: designated only if the checks pass. It is not also a click.
      if let some d := drag.filter (·.active) then
        match (at? p).bind fun n => rt.around tree n.id "dropTarget" with
        | some t =>
          let des := rt.designate serial i t.id t.key false
          ({ rt with dropped := some d.source, consent := des.map (·.serial) },
            [rel, { target := t.id, event := .drop p, designation := des }])
        | none => (rt, [rel])
      else if let some n := (at? p).filter (·.id == id) then
        let count := match rt.lastClick with
          | some (last, t, c) => if last == id && i.time ≤ t + rt.doubleClickMs then c + 1 else 1
          | none => 1
        let des := rt.designate serial i id n.key false
        let click : Delivery := { target := id, event := .click p b count, designation := des }
        ({ rt with lastClick := some (id, i.time, count), consent := des.map (·.serial) }, [rel, click])
      else (rt, [rel])
    | none => (rt, [])
  | .move p =>
    let target := (at? p).map (·.id)
    let moved (d : Drag) : Drag :=
      { d with at_ := p, active := d.active || (p.x - d.start.x).natAbs + (p.y - d.start.y).natAbs > dragDistance.natAbs }
    let rt := { rt with drag := rt.drag.map moved }
    let (rt, hov) := rt.hover target p i.time
    let moveTo := rt.pressed.orElse fun _ => target
    (rt, hov ++ moveTo.toList.map fun id => { target := id, event := .move p })
  | .leaveWindow =>
    let (rt, hov) := rt.hover none ⟨0, 0⟩ i.time
    (rt, hov)
  | .wheel p dx dy =>
    (rt, ((at? p).map (·.id)).toList.map fun id => { target := id, event := .wheel p dx dy })
  -- Escape during a drag cancels it, and goes nowhere else.
  | .key .escape m true =>
    if rt.drag.any (·.active) then ({ rt with drag := none }, [])
    else
      let id := (keyTarget .escape).getD tree.id
      let des := rt.designate serial i id ((tree.find? id).bind (·.key)) true
      ({ rt with consent := des.map (·.serial) }, [{ target := id, event := .key .escape m true, designation := des }])
  | .key .tab m true =>
    let order := match rt.overlay with
      | some _ => ((rt.overlayNode tree).map (·.focusables)).getD []
      | none => tree.focusables
    let to := nextFocus order rt.focused m.shift
    rt.moveFocus to i.time
  | .key k m pressed =>
    -- With nothing focused, keys go to the root, so that bindings around the whole view work.
    let id := (keyTarget k).getD tree.id
    let des := rt.designate serial i id ((tree.find? id).bind (·.key)) true
    ({ rt with consent := des.map (·.serial) }, [{ target := id, event := .key k m pressed, designation := des }])
  | .text s => (rt, textTarget.toList.map fun id => { target := id, event := .text s })
  | .paste s => (rt, textTarget.toList.map fun id => { target := id, event := .paste s })
  | .preedit s c =>
    (rt, textTarget.toList.map fun id => { target := id, event := .preedit (SafeText.filter s) c })

/-- A press outside the open overlay goes to nothing but the overlay, as a dismissal. -/
theorem press_outside {rt : Router} {tree : Node Msg} {i : Input} {p : Point} {b : MouseButton}
    {o : WidgetId} {k : Overlay} (hk : i.kind = .press p b) (ho : rt.overlay = some (o, k))
    (hm : (rt.hitAt tree p).filter (·.enabled) = none) :
    (rt.route tree i).2 = [{ target := o, event := .dismiss }] := by
  have : ({ rt with serial := rt.serial + 1, consent := none, dropped := none } : Router).hitAt tree p =
    rt.hitAt tree p := rfl
  simp only [route, hk, this, hm]
  simp [ho]

/-- Every designation the router gives names the widget its delivery goes to. -/
def designationsAgree (ds : List Delivery) : Bool :=
  ds.all fun d => d.designation.all (·.target == d.target)

end Router

end Paw
