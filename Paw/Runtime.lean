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
as messages of origin `other`.

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
  deriving Repr, DecidableEq, Inhabited

inductive WindowEvent where
  | input (i : Input)
  /-- Assistive technology, such as a screen reader, acts on a widget. Any program on the session
  bus can ask this, so it is delivered without a designation. -/
  | access (target : WidgetId) (action : AccessAction)
  /-- The window's new size, in units. -/
  | resize (w h : Int)
  | close
  deriving Repr, Inhabited

/-- What the platform is asked to do. -/
inductive Request where
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

def Cmd.toOutput {Msg : Type} {caps : List Cap} {o : Origin} : Cmd Msg caps o → Output Msg
  | .effect _ (.setClipboard _ t) _ _ => .request (.setClipboard t)
  | .effect _ (.openUri _ uri _) _ _ => .request (.openUri uri)
  | .task io _ => .task io
  | .notify t b _ => .request (.notify t b)
  | .setTitle t => .request (.setTitle t)
  | .quit => .request .quit

structure Runtime {caps : List Cap} (app : App caps) where
  model : app.Model
  tree : Node app.Msg
  nextId : Nat
  router : Router
  /-- The window, in units. -/
  window : Rect
  now : Nat
  measure : TextStyle → SafeText → Int × Int
  theme : Theme := {}
  quit : Bool := false
  /-- `update` has run since the last settle, so the model may have changed. -/
  updated : Bool := false

namespace Runtime

variable {caps : List Cap} {app : App caps}

def env (rt : Runtime app) : Env :=
  { measure := rt.measure, now := rt.now, theme := rt.theme, focused := rt.router.focused,
    hovered := rt.router.hovered, pressed := rt.router.pressed }

/-- The tree placed in the window, and the router told where everything is. -/
def layout (rt : Runtime app) : Runtime app :=
  let tree := rt.tree.resize rt.env rt.window
  { rt with tree, router := rt.router.observe tree rt.now }

/-- The window's background, then the tree. -/
def present (rt : Runtime app) : Output app.Msg :=
  .request (.present (Scene.inBox rt.window [.fill rt.window rt.theme.background 0] ++ rt.tree.render rt.env))

/-- The tree as assistive technology sees it. -/
def accessOut (rt : Runtime app) : Output app.Msg :=
  .request (.access ((rt.router.focused.map (·.n)).getD 0) (rt.tree.accessTree rt.env))

/-- A new frame: the scene, and the tree for assistive technology. -/
def frame (rt : Runtime app) : List (Output app.Msg) := [rt.present, rt.accessOut]

/-- `update` on one message: the runtime with the new model, and the commands' outputs. -/
def applyMsg (rt : Runtime app) (o : Origin) (m : app.Msg) : Runtime app × List (Output app.Msg) :=
  let ((), (model, cmds)) := (app.update o m).run (rt.model, #[])
  let outs := cmds.toList.map Cmd.toOutput
  let quit := rt.quit || outs.any fun | .request .quit => true | _ => false
  ({ rt with model, updated := true, quit }, outs)

/-- What a widget's request comes to, while handling a delivery with origin `o`. -/
def applyReq (rt : Runtime app) (o : Origin) : Req app.Msg → Runtime app × List (Output app.Msg)
  | .emit m => rt.applyMsg o m
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
  let (tree, reqs) := match rt.router.paths[d.target]? with
    | some path => match rt.tree.bubbleAt rt.env d.event path with
      | some (tree, reqs) => (tree, some reqs)
      | none => (rt.tree, none)
    | none => rt.tree.bubble rt.env d.target d.event
  let o : Origin := match d.designation with | some des => .user des | none => .other
  let (rt, outs) := { rt with tree }.applyReqs o (reqs.getD [])
  (rt, outs, reqs.isSome)

/-- The view rebuilt from the model, merged with the tree on screen and laid out; what nodes that
left the tree asked on leaving is handled as messages of origin `other`. -/
def rebuild (rt : Runtime app) : Runtime app × List (Output app.Msg) :=
  let view := (app.view rt.model).resolve (some rt.tree)
  let (tree, reqs, nextId) := view.merge rt.env rt.tree rt.nextId
  let (rt, outs) := { rt with tree, nextId }.applyReqs .other reqs
  (rt.layout, outs)

/-- After handling something: rebuild if the model changed, and draw if anything did. -/
def settle (before : app.Model) (changed : Bool) (rt : Runtime app) (outs : List (Output app.Msg)) :
    Runtime app × List (Output app.Msg) :=
  let wasUpdated := rt.updated
  let rt := { rt with updated := false }
  if !wasUpdated || rt.model == before then
    if changed then (rt.layout, outs ++ rt.layout.frame) else (rt, outs)
  else
    let (rt, outs') := rt.rebuild
    (rt, outs ++ outs' ++ rt.frame)

/-- The runtime for `app` in a window of `window`, at `now`, and its first scene. -/
def start (app : App caps) (window : Rect) (now : Nat)
    (measure : TextStyle → SafeText → Int × Int) : Runtime app × List (Output app.Msg) :=
  let (tree, nextId) := ((app.view app.init).resolve none).init 1
  let rt : Runtime app := { model := app.init, tree, nextId, router := {}, window, now, measure }
  let rt := rt.layout
  (rt, rt.frame)

/-- One event from the window. -/
def step (rt : Runtime app) (ev : WindowEvent) (now : Nat) : Runtime app × List (Output app.Msg) :=
  let rt := { rt with now }
  match ev with
  | .input i =>
    let before := rt.model
    let (router, ds) := rt.router.route rt.tree i
    let moved := router.focused != rt.router.focused || router.hovered != rt.router.hovered ||
      router.pressed != rt.router.pressed
    let (rt, outs, handled) := ds.foldl
      (fun (rt, outs, h) d => let (rt, o, h') := rt.deliver d; (rt, outs ++ o, h || h'))
      ({ rt with router }, [], false)
    rt.settle before (moved || handled) outs
  | .resize w h =>
    let rt := { rt with window := Rect.ofXYWH rt.window.x0 rt.window.y0 w h }.layout
    (rt, rt.frame)
  | .access id action =>
    let before := rt.model
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
    | none, _ => (rt, [])
  | .close => ({ rt with quit := true }, [])

/-- A task's result, as a message of origin `other`. -/
def taskResult (rt : Runtime app) (m : app.Msg) (now : Nat) : Runtime app × List (Output app.Msg) :=
  let before := rt.model
  let (rt, outs) := { rt with now }.applyMsg .other m
  rt.settle before false outs

end Runtime

/-- The platform as the runtime uses it: the Rust layer, or a fake in tests. -/
structure Platform where
  /-- Events from the window, waiting up to the given milliseconds for the first. -/
  poll : Nat → IO (List WindowEvent)
  /-- Milliseconds since the app started. -/
  now : IO Nat
  /-- The window's size, in units. -/
  size : IO (Int × Int)
  measure : TextStyle → SafeText → Int × Int
  perform : Request → IO Unit

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
  return tasks

/-- Runs `app` on `p` until it quits or the window closes, calling `onStep` with the runtime after
each poll. -/
partial def run (app : App caps) (p : Platform) (onStep : Runtime app → IO Unit := fun _ => pure ()) :
    IO Unit := do
  let (w, h) ← p.size
  let (rt, outs) := start app (Rect.ofXYWH 0 0 w h) (← p.now) p.measure
  loop rt (← carryOut p outs)
where
  loop (rt : Runtime app) (tasks : Array (Task (Except IO.Error app.Msg))) : IO Unit := do
    onStep rt
    if rt.quit then return
    let mut rt := rt
    let mut tasks := tasks
    for ev in ← p.poll 16 do
      let (rt', outs) := rt.step ev (← p.now)
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
