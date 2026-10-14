/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Cmd

/-! # The runtime

`Runtime.step` takes the runtime's state and one event from the window and gives the new state and
what to do: draw a scene, set the title, write the clipboard, open a link, run a task. It is pure,
so tests drive it directly. `Runtime.run` is the loop around it: it polls the platform, steps, and
carries out what each step asks, running tasks on their own threads and stepping their results in
as messages of origin `other`. Between events it sleeps in the platform's poll until
`nextDeadline`, when `advance` gives widgets their ticks and `update` its delayed messages; with
nothing waiting, it sleeps until there is an event.

A step for input routes it, gives each delivery to its widget (and to the widget's ancestors in
turn, if it does not handle it), and runs `update` on the messages that come out. A widget's
messages have origin `user d` when the input designated it, and `other` otherwise. If the model
changed, the view is rebuilt, merged with the tree on screen and laid out again, and the router
notes where everything now is. -/

namespace Paw

/-- An app: a component at the root, with the model it starts with. -/
structure App (caps : List Cap) extends Component caps where
  init : Model
  [beq : BEq Model]

attribute [instance] App.beq

/-- What assistive technology asks of a widget. -/
inductive AccessAction where
  | press
  | focus
  /-- A step up, for a value in a range: delivered as the Up key, without a designation. -/
  | increment
  | decrement
  deriving Repr, DecidableEq, Inhabited

inductive WindowEvent where
  | input (i : Input)
  /-- Assistive technology, such as a screen reader, acts on a widget. Any program on the session
  bus can ask this, so it is delivered without a designation. -/
  | access (target : WidgetId) (action : AccessAction)
  /-- The window's new size, in units. -/
  | resize (w h : Int)
  | close
  /-- The window gained or lost keyboard focus. -/
  | focus (has : Bool)
  /-- The window can or cannot be seen: shown or minimized, or covered whole. -/
  | visible (seen : Bool)
  deriving Repr, Inhabited

/-- What the platform is asked to do. -/
inductive Request where
  /-- The pointer's shape over the window. -/
  | cursor (c : Cursor)
  /-- An input method allowed, with the caret's rectangle to place its window by, or not. -/
  | ime (area : Option Rect)
  | present (s : Scene)
  | setTitle (t : SafeName)
  | setClipboard (t : SafeText)
  | openUri (uri : String)
  | notify (title : SafeName) (body : SafeText)
  | quit
  /-- The tree as assistive technology sees it, and the focused widget's id, 0 for none. -/
  | access (focus : Nat) (nodes : List AccessNode)
  deriving Repr, DecidableEq

/-- What a step asks for: of the platform, or a task to run. -/
inductive Output (Msg : Type) where
  | request (r : Request)
  | task (io : IO Msg)
  /-- `m` to `update` in `ms` milliseconds. The runtime keeps these itself. -/
  | after (ms : Nat) (m : Msg)

def Cmd.toOutput {Msg : Type} {caps : List Cap} {o : Origin} : Cmd Msg caps o → Output Msg
  | .effect _ (.setClipboard _ t) _ _ => .request (.setClipboard t)
  | .effect _ (.openUri _ uri _) _ _ => .request (.openUri uri)
  | .task io _ => .task io
  | .notify t b _ => .request (.notify t b)
  | .setTitle t => .request (.setTitle t)
  | .quit => .request .quit
  | .after ms m => .after ms m

structure Runtime {caps : List Cap} (app : App caps) where
  model : app.Model
  tree : Node app.Msg
  nextId : Nat
  router : Router
  /-- The window, in units. -/
  window : Rect
  now : Nat
  measure : TextStyle → SafeText → Int × Int
  theme : Theme := Theme.light
  /-- The pointer's shape the platform was last asked for. -/
  cursor : Cursor := .default
  /-- What the platform was last told of input methods. -/
  ime : Option Rect := none
  quit : Bool := false
  /-- `update` has run since the last settle, so the model may have changed. -/
  updated : Bool := false
  windowFocused : Bool := true
  windowVisible : Bool := true
  /-- Animations run; false when the user asked for reduced motion. -/
  motion : Bool := true
  /-- Messages from `Cmd.after`, with when each is due. -/
  delayed : Array (Nat × app.Msg) := #[]

namespace Runtime

variable {caps : List Cap} {app : App caps}

def env (rt : Runtime app) : Env :=
  { measure := rt.measure, now := rt.now, theme := rt.theme, focused := rt.router.focused,
    hovered := rt.router.hovered, pressed := rt.router.pressed, window := rt.window,
    windowFocused := rt.windowFocused, motion := rt.motion,
    dragAt := (rt.router.drag.filter (·.active)).map (·.at_) }

/-- The tree placed in the window, and the router told where everything is. -/
def layout (rt : Runtime app) : Runtime app :=
  let tree := rt.tree.resize rt.env rt.window
  { rt with tree, router := rt.router.observe tree rt.now rt.env }

/-- The overlays to draw now, bottom first, with their paths: those the router lets be seen, and of
tooltips, those showing. -/
def visibleOverlays (rt : Runtime app) : List (WidgetId × List Nat) :=
  rt.router.shown.toList.filterMap fun (id, p, k) =>
    if k != .tip || rt.router.tipShown p rt.now then some (id, p) else none

/-- What the overlays to draw now draw, bottom first. -/
def overlayScene (rt : Runtime app) : Scene :=
  Node.renderOverlays rt.window (rt.visibleOverlays.filterMap fun (_, p) =>
    (rt.tree.get? p).map (rt.tree.envAlong rt.env p, ·))

/-- While something is dragged: a faint copy of it, following the pointer, within the window. -/
def dragScene (rt : Runtime app) : Scene :=
  match rt.router.drag.filter (·.active) with
  | some d => match (rt.router.paths[d.source]?).bind fun p => (rt.tree.get? p).map (p, ·) with
    | some (p, n) =>
      (((n.render (rt.tree.envAlong rt.env p)).translate ⟨d.at_.x - d.start.x, d.at_.y - d.start.y⟩).withAlpha 140).clip rt.window
    | none => Scene.empty
  | none => Scene.empty

/-- The window's background, then the tree, then its open overlays, then what is being dragged. -/
def present (rt : Runtime app) : Output app.Msg :=
  .request (.present (Scene.inBox rt.window [.fill rt.window rt.theme.background 0] ++
    rt.tree.render rt.env ++ rt.overlayScene ++ rt.dragScene))

/-- The tree as assistive technology sees it. -/
def accessOut (rt : Runtime app) : Output app.Msg :=
  let hidden := rt.router.shown.toList.filterMap fun (id, p, k) =>
    if k == .tip && !rt.router.tipShown p rt.now then some id else none
  .request (.access ((rt.router.focused.map (·.n)).getD 0)
    (rt.tree.accessTree rt.env fun id => rt.router.refused.contains id || hidden.contains id))

/-- A new frame: the scene, and the tree for assistive technology if it may have changed. That
tree does not depend on hover or press, so a frame for those alone leaves it out. -/
def frame (rt : Runtime app) (access : Bool := true) : List (Output app.Msg) :=
  if access then [rt.present, rt.accessOut] else [rt.present]

/-- `update` on one message: the runtime with the new model, and the commands' outputs. -/
def applyMsg (rt : Runtime app) (o : Origin) (m : app.Msg) : Runtime app × List (Output app.Msg) :=
  let ((), (model, cmds)) := (app.update o m).run (rt.model, #[])
  let outs := cmds.toList.map Cmd.toOutput
  let quit := rt.quit || outs.any fun | .request .quit => true | _ => false
  let delayed := rt.delayed ++ (outs.filterMap fun | .after ms m => some (rt.now + ms, m) | _ => none).toArray
  let outs := outs.filter fun | .after .. => false | _ => true
  ({ rt with model, updated := true, quit, delayed }, outs)

/-- What a widget's request comes to, while handling a delivery with origin `o`. -/
def applyReq (rt : Runtime app) (o : Origin) : Req app.Msg → Runtime app × List (Output app.Msg)
  | .emit m => rt.applyMsg o m
  | .choose m => match o with
    | .user _ => rt.applyMsg o m
    | .other => (rt, [])
  | .focus id => ({ rt with router := (rt.router.moveFocus (some id) rt.now).1 }, [])
  | .render => (rt, [])
  | .copy t => match o with
    | .user _ => (rt, [.request (.setClipboard t)])
    | .other => (rt, [])

def applyReqs (rt : Runtime app) (o : Origin) (reqs : List (Req app.Msg)) :
    Runtime app × List (Output app.Msg) :=
  reqs.foldl (fun (rt, outs) r => let (rt, o') := rt.applyReq o r; (rt, outs ++ o')) (rt, [])

/-- `d` to its widget: the runtime after, the outputs, and whether any widget handled it. -/
def deliver (rt : Runtime app) (d : Delivery) : Runtime app × List (Output app.Msg) × Bool :=
  -- A drop is delivered with what was dragged.
  let env := match d.event with
    | .drop _ =>
      let payload := (rt.router.dropped.bind (rt.router.paths[·]?)).bind fun p =>
        (rt.tree.get? p).bind fun n => (n.state? DragPayload).map (·.payload)
      { rt.env with dragged := payload }
    | _ => rt.env
  let (tree, reqs) := match rt.router.paths[d.target]? with
    | some path => match rt.tree.bubbleAt env d.event path with
      | some (tree, reqs) => (tree, some reqs)
      | none => (rt.tree, none)
    | none => rt.tree.bubble env d.target d.event
  let o : Origin := match d.designation with | some des => .user des | none => .other
  let (rt, outs) := { rt with tree }.applyReqs o (reqs.getD [])
  (rt, outs, reqs.isSome)

/-- The view rebuilt from the model, merged with the tree on screen and laid out; what nodes that
left the tree asked on leaving is handled as messages of origin `other`. A modal the router refused
to open is dismissed, and if that changes the model, the view is rebuilt again, up to `fuel` times. -/
def rebuild (rt : Runtime app) (fuel : Nat := 2) : Runtime app × List (Output app.Msg) :=
  let view := (app.view rt.model).resolve (some rt.tree)
  let (tree, reqs, nextId) := view.merge rt.env rt.tree rt.nextId
  let refusedBefore := rt.router.refused
  let (rt, outs) := { rt with tree, nextId, updated := false }.applyReqs .other reqs
  let rt := rt.layout
  let fresh := rt.router.refused.toList.filter (!refusedBefore.contains ·)
  let (rt, outs') := fresh.foldl (fun (rt, outs) id =>
    let (rt, o, _) := rt.deliver { target := id, event := .dismiss }; (rt, outs ++ o)) (rt, [])
  match fuel with
  | fuel + 1 =>
    if rt.updated then
      let (rt, outs'') := { rt with updated := false }.rebuild fuel
      (rt, outs ++ outs' ++ outs'')
    else (rt, outs ++ outs')
  | 0 => ({ rt with updated := false }, outs ++ outs')

/-- After handling something: rebuild if the model changed, and draw if anything did. `access`
says whether the tree for assistive technology may have changed short of a rebuild: a widget's
state, or focus. -/
def settle (before : app.Model) (changed : Bool) (rt : Runtime app) (outs : List (Output app.Msg))
    (access : Bool := true) : Runtime app × List (Output app.Msg) :=
  let wasUpdated := rt.updated
  let rt := { rt with updated := false }
  if !wasUpdated || rt.model == before then
    if changed then
      let rt := rt.layout
      (rt, outs ++ rt.frame access)
    else (rt, outs)
  else
    let (rt, outs') := rt.rebuild
    (rt, outs ++ outs' ++ rt.frame)

/-- The runtime for `app` in a window of `window`, at `now`, and its first scene. -/
def start (app : App caps) (window : Rect) (now : Nat)
    (measure : TextStyle → SafeText → Int × Int) (motion : Bool := true) (theme : Theme := Theme.light) :
    Runtime app × List (Output app.Msg) :=
  let (tree, nextId) := ((app.view app.init).resolve none).init 1
  let rt : Runtime app := { model := app.init, tree, nextId, router := {}, window, now, measure, motion, theme }
  let rt := rt.layout
  (rt, rt.frame)

/-- The platform asked for the pointer's shape over the widget under it, if that changed. -/
def pointCursor (rt : Runtime app) (outs : List (Output app.Msg)) : Runtime app × List (Output app.Msg) :=
  let c := match rt.router.hovered.bind (rt.router.paths[·]?) with
    | some p => ((rt.tree.get? p).map (·.cursor (rt.tree.envAlong rt.env p))).getD .default
    | none => .default
  if c == rt.cursor then (rt, outs) else ({ rt with cursor := c }, outs ++ [.request (.cursor c)])

/-- The platform told whether the focused widget takes composed text, and where its caret is, if
that changed: an input method is on only while such a widget has focus and the window does. -/
def pointIme (rt : Runtime app) (outs : List (Output app.Msg)) : Runtime app × List (Output app.Msg) :=
  let area := if !rt.windowFocused then none else
    (rt.router.focused.bind (rt.router.paths[·]?)).bind fun p =>
      (rt.tree.get? p).bind (·.imeArea (rt.tree.envAlong rt.env p))
  if area == rt.ime then (rt, outs) else ({ rt with ime := area }, outs ++ [.request (.ime area)])

/-- Input from the platform: routed, delivered, and settled. -/
def stepInput (rt : Runtime app) (i : Input) : Runtime app × List (Output app.Msg) :=
  let before := rt.model
  let (router, ds) := rt.router.route rt.tree i
  let focusMoved := router.focused != rt.router.focused
  let moved := focusMoved || router.hovered != rt.router.hovered || router.pressed != rt.router.pressed ||
    router.drag != rt.router.drag
  let (rt, outs, handled) := ds.foldl
    (fun (rt, outs, h) d => let (rt, o, h') := rt.deliver d; (rt, outs ++ o, h || h'))
    ({ rt with router }, [], false)
  let (rt, outs) := rt.settle before (moved || handled) outs (access := focusMoved || handled)
  let (rt, outs) := rt.pointCursor outs
  rt.pointIme outs

/-- One event from the window. -/
def step (rt : Runtime app) (ev : WindowEvent) (now : Nat) : Runtime app × List (Output app.Msg) :=
  let rt := { rt with now, router := { rt.router with consent := none } }
  match ev with
  | .input i =>
    -- Whatever the platform sends, keys reach no widget while the window lacks keyboard focus.
    if i.kind.keyboard && !rt.windowFocused then (rt, []) else rt.stepInput i
  | .focus has =>
    let rt := { rt with windowFocused := has }.layout
    rt.pointIme rt.frame
  | .visible seen =>
    let rt := { rt with windowVisible := seen }.layout
    (rt, if seen then rt.frame else [])
  | .resize w h =>
    let rt := { rt with window := Rect.ofXYWH rt.window.x0 rt.window.y0 w h }.layout
    (rt, rt.frame)
  | .access id action =>
    let before := rt.model
    -- While an overlay is open, nothing beneath it can be acted on.
    if !rt.router.trapped id then (rt, []) else
    match rt.tree.find? id, action with
    | some n, .press =>
      let p : Point := ⟨(n.viewport.x0 + n.viewport.x1) / 2, (n.viewport.y0 + n.viewport.y1) / 2⟩
      let (rt, outs, _) := rt.deliver { target := id, event := .click p .primary 1 }
      rt.settle before true outs
    | some n, .focus =>
      if n.focusable then
        let (router, ds) := rt.router.moveFocus (some id) now
        let (rt, outs, _) := ds.foldl
          (fun (rt, outs, h) d => let (rt, o, h') := rt.deliver d; (rt, outs ++ o, h || h'))
          ({ rt with router }, [], false)
        rt.settle before true outs
      else (rt, [])
    | some _, .increment | some _, .decrement =>
      let k := if action == .increment then Key.up else Key.down
      let (rt, outs, _) := rt.deliver { target := id, event := .key k {} true }
      rt.settle before true outs
    | none, _ => (rt, [])
  | .close => ({ rt with quit := true }, [])

/-- Time passing, at `now`: widgets due a tick get one, while the window can be seen; messages from
`Cmd.after` that are due go to `update` with origin `other`; and a frame is drawn if anything
changed, or a tooltip came or went. -/
def advance (rt : Runtime app) (now : Nat) : Runtime app × List (Output app.Msg) :=
  let tipsBefore := rt.visibleOverlays
  let rt := { rt with now, router := { rt.router with consent := none } }
  let before := rt.model
  let due := if rt.windowVisible then
      rt.router.ticks.fold (fun acc id (ms, d) => if d ≤ now then (id, ms) :: acc else acc) []
    else []
  let (rt, outs, ticked) := due.foldl (fun (rt, outs, ticked) (id, ms) =>
    let router := { rt.router with ticks := rt.router.ticks.insert id (ms, now + ms) }
    let rt := { rt with router }
    match rt.router.paths[id]?.bind (rt.tree.handleIn rt.env (.tick now) ·) with
    | some (tree, reqs) =>
      let (rt, o) := { rt with tree }.applyReqs .other reqs
      (rt, outs ++ o, true)
    | none => (rt, outs, ticked)) (rt, [], false)
  let (ready, later) := rt.delayed.partition (·.1 ≤ now)
  let (rt, outs) := ready.foldl (fun (rt, outs) (_, m) => let (rt, o) := rt.applyMsg .other m; (rt, outs ++ o))
    ({ rt with delayed := later }, outs)
  rt.settle before (ticked || rt.visibleOverlays != tipsBefore) outs (access := !ready.isEmpty)

/-- When `advance` next has something to do: the earliest tick due while the window can be seen,
message from `Cmd.after`, or tooltip waiting to show; `none` if nothing is waiting, and the loop
may sleep until the platform has an event. -/
def nextDeadline (rt : Runtime app) : Option Nat :=
  let ticks := if rt.windowVisible then rt.router.ticks.fold (fun acc _ (_, d) => d :: acc) [] else []
  ((ticks ++ rt.delayed.toList.map (·.1) ++ rt.router.tipDeadlines rt.now).map (max rt.now)).min?

/-- The deadline is never in the past, so the loop never waits a negative time. -/
theorem now_le_nextDeadline {rt : Runtime app} {d : Nat} (h : rt.nextDeadline = some d) : rt.now ≤ d := by
  unfold nextDeadline at h
  have hm := List.min?_mem h
  simp only [List.mem_map] at hm
  obtain ⟨x, -, rfl⟩ := hm
  omega

/-- A task's result, as a message of origin `other`. -/
def taskResult (rt : Runtime app) (m : app.Msg) (now : Nat) : Runtime app × List (Output app.Msg) :=
  let before := rt.model
  let (rt, outs) := { rt with now, router := { rt.router with consent := none } }.applyMsg .other m
  rt.settle before false outs

end Runtime

/-- The platform as the runtime uses it: the Rust layer, or a fake in tests. -/
structure Platform where
  /-- Events from the window, waiting up to the given milliseconds for the first, or with `none`,
  until there is one. -/
  poll : Option Nat → IO (List WindowEvent)
  /-- Milliseconds since the app started. -/
  now : IO Nat
  /-- The window's size, in units. -/
  size : IO (Int × Int)
  measure : TextStyle → SafeText → Int × Int
  perform : Request → IO Unit
  /-- Animations run; false when the user asked for reduced motion. -/
  motion : Bool := true
  /-- The theme the user chose. -/
  theme : Theme := Theme.light

namespace Runtime

variable {caps : List Cap} {app : App caps}

/-- Carries out outputs: requests go to the platform, tasks start on their own threads. -/
def carryOut (p : Platform) (outs : List (Output app.Msg)) :
    IO (Array (Task (Except IO.Error app.Msg))) := do
  let mut tasks := #[]
  for o in outs do
    match o with
    | .request r => p.perform r
    | .task io => tasks := tasks.push (← IO.asTask io)
    | .after .. => pure ()
  return tasks

/-- How long the loop may wait for the platform: until the next deadline, and while tasks are
running, no more than 16 ms, since a task finishing does not wake the platform; with nothing
waiting, until the platform has an event. -/
def waitFor (rt : Runtime app) (now : Nat) (tasksRunning : Bool) : Option Nat :=
  let untilDue := rt.nextDeadline.map (· - now)
  if tasksRunning then some ((untilDue.map (min 16)).getD 16) else untilDue

/-- Runs `app` on `p` until it quits or the window closes, calling `onStep` with the runtime after
each poll. The loop sleeps in the platform's poll until an event or the next deadline. -/
partial def run (app : App caps) (p : Platform) (onStep : Runtime app → IO Unit := fun _ => pure ()) :
    IO Unit := do
  let (w, h) ← p.size
  let (rt, outs) := start app (Rect.ofXYWH 0 0 w h) (← p.now) p.measure p.motion p.theme
  loop rt (← carryOut p outs)
where
  loop (rt : Runtime app) (tasks : Array (Task (Except IO.Error app.Msg))) : IO Unit := do
    onStep rt
    if rt.quit then return
    let mut rt := rt
    let mut tasks := tasks
    for ev in ← p.poll (rt.waitFor (← p.now) !tasks.isEmpty) do
      let (rt', outs) := rt.step ev (← p.now)
      rt := rt'
      tasks := tasks ++ (← carryOut p outs)
    let (rt', outs) := rt.advance (← p.now)
    rt := rt'
    tasks := tasks ++ (← carryOut p outs)
    let mut pending := #[]
    for t in tasks do
      if ← IO.hasFinished t then
        if let .ok m := t.get then
          let (rt', outs) := rt.taskResult m (← p.now)
          rt := rt'
          pending := pending ++ (← carryOut p outs)
      else pending := pending.push t
    loop rt pending

end Runtime

end Paw
