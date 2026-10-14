# Paw Design

*This document was written by an LLM that read the monomer source code and the CryptWalker sources cited below. It is not the original work of a human author.*

Paw is an Elm-style GUI library for Lean, for Linux desktop and Android. Its design follows [monomer](https://github.com/fjvallarino/monomer), a Haskell GUI library. Its security rules are in [GUI_SECURITY_GUIDELINES.md](GUI_SECURITY_GUIDELINES.md), and this document says how Paw enforces them. Where a rule can be stated as a proposition, Paw states it in a type, so that a widget, a layout or a component that breaks it does not compile.

## Why Lean, and why monomer

Monomer's design depends on what Haskell offers:

- widgets as records of functions;
- internal state hidden behind existential types;
- effects returned as data from pure code;
- monads to thread state through event handling.

A GUI library written in Rust is built from other parts: trait objects, interior mutability and callbacks. Translating one of those into Lean would lose the parts of the design that make it reusable. Lean has everything monomer uses, and it also has dependent types. A structure can carry propositions about its own fields, and those propositions must be proved for every instance.

CryptWalker already relies on this. `NIKE` carries `commutes` and `derive_safe`, and `KEM` carries `honestRoundTrip`. `kemOfNike` in `KEM/Adapter.lean` builds a `KEM` from any `NIKE`, and it discharges `honestRoundTrip` from the NIKE's `commutes`. So each composed scheme inherits correctness from its parts with no further work by whoever composes them. Paw applies the same pattern to a GUI:

- a widget carries the proof that it draws inside its box;
- a layout carries the proof that it places children inside its own box;
- a container built from the two gets its proof from theirs.

## Architecture

```
┌──────────────────────── Lean ───────────────────────────────────────┐
│  App components:  Model, Msg, update (UpdateM), view                │
│  Pure core:       widget tree, merge, layout, hit-testing, Scene    │
│  Runtime loop:    event queue, routing, designations, tasks         │
└────────────▲───────────────────────────────────┬────────────────────┘
             │ input events, measurements         │ Scene, platform requests
┌────────────┴─────────── Rust (FFI) ─────────────▼───────────────────┐
│  window and input, IME, text shaping, drawing, accessibility,       │
│  clipboard, portals, Android activity and JNI                       │
└──────────────────────────────────────────────────────────────────────┘
```

**Lean** holds everything that decides what the user sees and what the app may do. This covers the app's model and update, the widget tree and its merge, layout, hit-testing, focus, and the display list. All of it is pure except the runtime loop, so the laws below are theorems about the code that actually runs.

**Rust** holds what talks to the platform. On Linux desktop, X11 and Wayland both:

| Concern | Crate | Why |
| --- | --- | --- |
| Windows and input | winit 0.30, driven with `pump_app_events` | Lean owns the loop and polls, as monomer polls SDL; no Lean code runs inside a winit callback. winit picks Wayland or X11 at startup |
| Drawing a Scene | tiny-skia, shown with softbuffer | Draws on the CPU, so the same scene gives the same pixels everywhere: golden images can be compared exactly, and no GPU is needed under Xvfb or a headless compositor |
| Text shaping, measuring, drawing | cosmic-text, with DejaVu Sans bundled | Measuring and drawing use one font system, so text is drawn as wide as layout measured it. Offscreen renders use only the bundled fonts; a window adds the system's for characters they lack |
| Clipboard | arboard, with Wayland's data-control protocol | The clipboard is read only when the user presses Ctrl-V, which becomes a `paste` event |
| Opening links, notifications | `xdg-open` and `notify-send`, run with the link or text as arguments, never through a shell | Lean has already checked the link |
| Accessibility | AccessKit | |

Some platform facts the guidelines rely on, as they stand on Linux:

- **Synthetic input.** winit reads the pointer and keyboard through XInput2 on X11. Core events another client sends with `XSendEvent` are not XInput2 events, so they never reach Paw at all. winit gives no flag for synthetic input on either X11 or Wayland, so `Input.synthetic` is never set on Linux. XTEST input remains indistinguishable from the user's, as the guidelines say.
- **Keys held when focus arrives.** winit reports keys held while the window gains focus as synthetic key events. The Rust layer drops them, because they were not pressed in this window.
- **A lost display.** When the compositor or X server goes away, winit's loop exits, and the Rust layer reports `close`.

The byte formats are built from `Codec α`, a structure that carries its own law, the same pattern as the widget laws below:

```lean
structure Codec (α : Type) where
  enc : α → List UInt8
  dec : List UInt8 → Option (α × List UInt8)
  roundtrip : ∀ a rest, dec (enc a ++ rest) = some (a, rest)
```

- **Primitives.** Natural numbers are LEB128 varints, and integers zigzag varints.
- **Combinators.** Pairs, lists and refinements build codecs from codecs. A codec for `Scene` gets its round trip from its fields' codecs.
- **Decoding refuses rather than guesses.** A `SafeText` decodes only if every character passes the allowlist, so bytes from Rust cannot smuggle in a character Lean would have refused.
- **The Rust side is checked by tests, not proofs.** The proofs are about Lean's encoder and decoder. Rust's copy of the format is checked by echo functions: Rust decodes what Lean encoded and encodes it again, and a test compares the bytes on random values.

Layout needs one call into Rust: measuring shaped text. It is declared `@[extern]` and treated as a pure function of font, size and text, with results cached by the core.

## What Paw keeps from monomer

| Concept | In monomer | In Paw |
| --- | --- | --- |
| Widget interface | `Widget s e`, a record of init, merge, dispose, event and message handling, size request, resize, render (`Core/WidgetTypes.hs`) | The same record, written over the widget's own state type as a `Widget.Spec`, with law fields and a pure render; it never sees the tree |
| Leaves and containers | `Single` for leaves, `Container` for children | A leaf is a `Widget`; a container is a `Layout` with children |
| Effects as data | Every operation returns a node and a list of `WidgetRequest`s | Operations return a node and a list of `Cmd`s, typed by capability and origin |
| Rebuild and merge | The view is rebuilt from the model; `mergeChildSeq` pairs old and new children by position, then by key; unmatched new ones are initialized, unmatched old ones disposed (`Widgets/Container.hs`) | The same algorithm, with keys unique among siblings; an old child no new child merged with is disposed |
| Skipping unchanged views | A Composite rebuilds only when its model changed (`mergeRequired`) | The view is rebuilt only when the model changed; models need `BEq` |
| Identity | `Path` (child indices), `WidgetKey` (user text), `WidgetId` (creation time and path), with a runtime table from id to current path | `Path` as in monomer; a `WidgetId` is a number given when a node joins the tree and kept through merges |
| Layout | `SizeReq {fixed, flex, extra, factor}` per axis; `assignStackAreas` gives fixed sizes, shrinks flex in proportion, then shares extra space by factor (`Widgets/Containers/Stack.hs`) | The same algorithm over integers, with its laws proved |
| Event routing | Keys, text and clipboard go to the focused path; press, move and wheel go to the widget under the point; overlays become the root for hit-testing; a `Click` needs press and release on the same widget (`Main/Handlers.hs`) | The same, plus the checks from the security guidelines before a designation is made |
| Rendering | Only on request: input, `RenderOnce`, `RenderEvery`; overlays drawn after the main pass | The same; the Scene is sent to Rust only when a render is needed |
| Tasks and producers | `Task (IO e)` for one result, `Producer` for a stream, both delivered to the widget that started them | The same, delivered with origin `result` and checked against the current tree |

## What Paw changes

| In monomer | In Paw | Why |
| --- | --- | --- |
| `render` is `IO ()` that drives NanoVG | `render` returns a `Scene`, a pure display list | Drawing becomes something laws can be stated about |
| Coordinates are `Double` | Integer units (for example 1/64 px) | Ordering laws on integers are decidable and `omega` proves them |
| Clipping is opt-in (`singleUseScissor = False`) | Every widget has a law that its Scene lies within its box | Text and images from elsewhere cannot draw over neighbours |
| One `WidgetRequest` type where any widget can run IO or write the clipboard | `Cmd caps origin`: effects need a capability and a designation | Authority follows the user's choice and the component's declared capabilities |
| Task results and input arrive as the same event type | Messages arrive with an `Origin`: `user d` for the user's choice, `other` for anything else | The rule "effects come from user actions" becomes a type |
| `WidgetKey` is any `Text`, and duplicates are undefined | Keys are strings, and a key a sibling before already has is dropped, with a proof that keys are then unique | Content cannot choose a key that takes over another widget's state |
| Widget functions receive their node, and containers call their children's functions | Widget functions receive only their own state and box; `Paw.Tree` merges, lays out and draws children | Lean only accepts a node type that holds widgets if widgets do not take nodes as arguments; a widget also cannot act outside its own box |
| `Typeable` and `cast` for widget state and messages | One message type for the whole tree; widget state carried across a merge through `Dynamic`, only between widgets of the same kind | Lean's types replace runtime casts where possible |
| `Composite`: components with their own model and handler inside the tree | Elm's way: one model and one `update` at the root; a component is a view function and an update function with their own message type, mapped into the parent's | A tree whose message type changes inside it is an inductive family Lean would place in a higher universe with no gain; mapping keeps one message type |
| Lenses into the model for widget values | Widgets take values and report changes as messages, as in Elm | One direction for data to flow |
| SDL2 and NanoVG through OpenGL | The Rust layer above | Wayland, Android and accessibility support |
| A stack that lacks room places children past its box, for the parent to fix | Children are cut at the box's edge | `assign_within` holds for every layout; a scroll is how content larger than its box is shown |
| A scroll places its child past its own box | The child is laid out in a content rectangle the scroll names, and drawn clipped to the scroll's box | `assign_within` holds relative to the content rectangle; the clip law is unchanged |
| Shrinking flexible sizes in one pass, clamped at zero, so a child weighted to give up more than it has leaves the rest overflowing | Shrinking in rounds: what one child cannot give, the others give next round | Children fit whenever their rigid sizes do; a random test checks it |

## Laws in types

The definitions in this section are taken from the library, shortened where marked. `make coverage` checks that no declaration in the library uses an axiom beyond `propext`, `Classical.choice` and `Quot.sound`.

### Geometry

```lean
structure Rect where
  x0 : Int
  y0 : Int
  x1 : Int
  y1 : Int

def Rect.Within (a b : Rect) : Prop :=
  b.x0 ≤ a.x0 ∧ b.y0 ≤ a.y0 ∧ a.x1 ≤ b.x1 ∧ a.y1 ≤ b.y1

theorem Rect.Within.trans {a b c : Rect} (h₁ : a.Within b) (h₂ : b.Within c) : a.Within c := by
  unfold Rect.Within at *; omega

def Rect.inter (a b : Rect) : Rect :=
  ⟨max a.x0 b.x0, max a.y0 b.y0, min a.x1 b.x1, min a.y1 b.y1⟩

theorem Rect.inter_within (a b : Rect) : (a.inter b).Within b := by
  simp only [Rect.Within, Rect.inter]; omega
```

`Within` is decidable, so a test can check it on concrete values too.

### Text from elsewhere

`SafeText` carries the proof that every character passed the allowlist. The only way to get one from an arbitrary string is the filter, which proves it:

```lean
structure SafeText where
  text : String
  ok : text.toList.all allowed = true

def SafeText.filter (s : String) : SafeText :=
  ⟨String.ofList (s.toList.map fun c => if allowed c then c else substitute), by
    simp only [String.toList_ofList, List.all_map, List.all_eq_true]
    intro c _
    simp only [Function.comp]
    split <;> simp_all [substitute, allowed]⟩
```

Widgets that draw text accept only `SafeText`. The allowlist follows the guidelines: every rule there that is a property of single characters is part of `allowed`, and so of `ok`.

- **Names are stricter.** `SafeName` is for names, titles and file names. Its `ok` uses `allowedInName`, which also refuses bidi controls, joiners, variation selectors and badge-like symbols. Body text keeps bidi controls, which right-to-left writing needs; each field is laid out as its own paragraph, so its direction cannot leak.
- **Not every rule is about single characters.** The cap on combining marks per base character is applied by the filter but is not part of `ok`, because it constrains runs of characters. Marks beyond the cap cannot escape anyway: the clipping law below keeps whatever a text draws inside its widget.
- **Text the app wrote** goes through `SafeText.trusted`. It checks the string and filters it, should it hold a character not allowed, so even the app's own strings carry the proof.

### Scenes and clipping

A Scene is a list of draw items, each with the clip it is drawn under:

```lean
inductive Draw where
  | fill (r : Rect) (c : Color) (radius : Int)
  | stroke (r : Rect) (c : Color) (width : Int) (radius : Int)
  | text (at_ : Point) (t : SafeText) (style : TextStyle)

structure Scene where
  items : List (Rect × Draw)

def Scene.Within (s : Scene) (v : Rect) : Prop := ∀ i ∈ s.items, i.1.Within v

def Scene.clip (v : Rect) (s : Scene) : Scene := ⟨s.items.map fun (r, d) => (r.inter v, d)⟩

theorem Scene.clip_within (v : Rect) (s : Scene) : (s.clip v).Within v
```

A leaf widget whose drawing depends on content, such as a label or an image, ends its render with `Scene.clip`, and `clip_within` discharges its law.

### Widgets and layouts compose their laws

A leaf is a `Widget`, whose render carries its law. A container is a `Layout` with children. `Paw.Tree` draws a node as its widget's scene followed by its children's, clipped to the node's box (shortened):

```lean
structure Widget (Msg : Type) where
  kind : String
  State : Type
  render : Env → State → Rect → Scene
  render_within : ∀ env st v, (render env st v).Within v
  -- …

def Node.render (env : Env) : Node Msg → Scene
  | mk w st i _ cs =>
    if i.visible then w.render env st i.viewport ++ (renderList env cs).clip i.viewport
    else Scene.empty

theorem Node.render_within (env : Env) (n : Node Msg) : (n.render env).Within n.viewport := by
  rcases n with ⟨w, st, i, l, cs⟩
  · simp only [render, viewport, info]
    split
    · exact Scene.append_within (w.render_within env st i.viewport) (Scene.clip_within _ _)
    · exact Scene.empty_within _
```

This is the `kemOfNike` pattern. A tree's law comes from its widgets' `render_within` and the `Scene` laws, so a stack of grids of labels draws within the window because each part does, and nobody writes that proof for the stack, the grid or the app. The proof needs no induction over the tree, because each node clips its children. The layout laws make that clip remove nothing: `assign_within` places every child inside its parent.

The full `Widget` record also has monomer's merge, event and dispose functions. The laws, of `Widget` and of the structures around it:

| Structure | Law | Guideline it enforces |
| --- | --- | --- |
| `Widget` | `render_within`: the Scene lies inside the box | Text stays inside its box; content cannot draw over chrome |
| `Layout` | `assign_within`; `assign_length` | Children stay inside their parent |
| `Layout` for stack and grid | `assign_disjoint`: children's boxes do not overlap | Reserved regions cannot be covered by a sibling |
| `Node` | `hit_spec`: hit-testing returns only a visible node whose box contains the point; of overlapping siblings, the later, which is drawn on top | The user clicks what they see |
| `Router` | `nextFocus_mem`: focus moves only to a widget in the focus order, which holds only visible, enabled, focusable widgets | Focus is the user's |
| `Node` | keys unique among siblings, by `dedupKeys_nodup` | State is never handed to another widget |

Widgets draw with `Scene.inBox v ds`, every item clipped to the box `v`, and `Scene.inBox_within` is their `render_within`.

A container's children are laid out in its content rectangle, which its widget names: the box itself, or for a scroll, a rectangle as tall as the content, shifted up by the scroll offset and narrowed by a gutter for the scroll bar. The layout laws hold relative to the content rectangle, and `Node.render` clips the children to the box, so the tree-wide law is unchanged. Two things follow:

- **The gutter is a reserved region.** The child's box never covers it, so no content can draw over the bar.
- **Scrolling is movement.** The router sees every widget in the content move, and treats each as unstable for `stableMs`. A click right after a scroll is delivered, but designates nothing.

Stacks and grids prove `assign_disjoint` once, between them. Each is an `Axial` layout that only decides a size per child along its axis. `Axial.toSeparated` places those sizes one after another and proves all three laws from a lemma about the placement. A new layout along one axis gets the laws by supplying its size function and a proof that it returns one size per child.

Overlap is sometimes wanted, as in a z-stack or a popup. Those layouts do not carry `assign_disjoint`. A container that needs reserved regions accepts only layouts that do, which is a type constraint on the container.

### Authority and origin

Effects that use authority need two things: a capability the component declared, and a designation from the input being handled, of a widget whose key is the effect's target. The app knows its widgets' keys, such as a message's id, and never their `WidgetId`s.

```lean
inductive Cap where
  | clipboardWrite | openUri | notify | io

structure Designation where
  private mk ::
  serial : Nat
  target : WidgetId
  key : Option String
  time : Nat

inductive Origin where
  | user (d : Designation)
  | other

inductive Effect : Cap → Type where
  | setClipboard (target : String) (t : SafeText) : Effect .clipboardWrite
  | openUri (target : String) (uri : String) (ok : Uri.allowed uri = true) : Effect .openUri

def Effect.DesignatedBy (e : Effect c) (d : Designation) : Prop :=
  e.target.all (fun k => d.key == some k) = true

inductive Cmd (Msg : Type) (caps : List Cap) : Origin → Type where
  | effect {c} (d : Designation) (e : Effect c) (granted : c ∈ caps)
      (designated : e.DesignatedBy d) : Cmd Msg caps (.user d)
  | task {o} (io : IO Msg) (granted : Cap.io ∈ caps) : Cmd Msg caps o
  | notify {o} (title : SafeName) (body : SafeText) (granted : Cap.notify ∈ caps) : Cmd Msg caps o
  | setTitle {o} (title : SafeName) : Cmd Msg caps o
  | quit {o} : Cmd Msg caps o
```

How these types enforce the rules:

- **Only the router makes designations.** `Designation`'s constructor is private to `Paw.Route`, which creates one only after hit-testing has found the target and the checks in the guidelines have passed:
  - the target was visible, enabled and unmoved for long enough;
  - the touch was not obscured by another app's overlay;
  - the event was not synthetic;
  - for a key, focus has stayed on the widget for long enough, so typing meant for elsewhere did not follow a focus change.
- **A command is tied to the input being handled.** The runtime gives a widget's messages origin `user d` only while handling the input `d` came with; every other message has origin `other`. An `effect` exists only in `Cmd Msg caps (.user d)`, for that `d`, and only for a target the clicked widget's key names. A designation kept in the model from an earlier input has the wrong index, so it authorizes nothing later.
- **Nothing else can use authority.** This is a theorem, proved by case analysis:

  ```lean
  theorem Cmd.other_no_authority (cmd : Cmd Msg caps .other) : cmd.usesAuthority = false
  ```

- **Links are checked when the effect is made.** `openUri` needs a proof that the link has an allowed scheme (`https`, `http`, `mailto`), something after it, and only printable characters. `Effect.openUri?` returns `none` for anything else.
- **Notifications and titles need no designation.** A new message must be able to notify, so these take only filtered text: `SafeName` and `SafeText`.
- **Capabilities compose by inclusion.** A parent embeds a child component only with a proof that the child's capabilities are among its own. `decide` proves this for concrete lists. The child's commands are lifted with:

  ```lean
  def Cmd.lift (sub : caps ⊆ caps') : Cmd Msg caps o → Cmd Msg caps' o
  theorem Cmd.lift_usesAuthority (sub : caps ⊆ caps') (c : Cmd Msg caps o) :
      (c.lift sub).usesAuthority = c.usesAuthority
  ```

  So the capabilities an app declares at its root bound everything every nested component can do. This is the same transitive pattern as the clipping law.

### The update monad

`update` runs in a state monad over the model and the commands emitted so far, indexed by the message's origin:

```lean
abbrev UpdateM (σ Msg : Type) (caps : List Cap) (o : Origin) :=
  StateM (σ × Array (Cmd Msg caps o))

def emit (c : Cmd Msg caps o) : UpdateM σ Msg caps o Unit := modify fun (s, cs) => (s, cs.push c)

structure Component (caps : List Cap) where
  Model : Type
  Msg : Type
  update : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  view : Model → Node Msg
```

Handlers are written in `do` notation with `modify`, `get` and `emit`. An effect for the clicked item is emitted after a decidable check that the designation names it:

```lean
  | .user d, .openLink key uri => do
    match Effect.openUri? key uri with
    | some e => if h : e.DesignatedBy d then emit (.effect d e (by decide) h) else …
    | none => …
```

A component is embedded by mapping its view's messages with `Node.mapMsg` and its commands with `Cmd.mapMsg`, and lifting its commands with `Cmd.lift`. Properties of a particular handler, such as "removing an item leaves the others in order", can be stated as `Std.Do` triples about `update`, as `KEM.lean` states `generate_ok` and `decap_ok`.

### Keys

A node's constructor is private. The constructors the library offers drop a key a sibling before already has:

```lean
def Node.container (l : Layout) (children : List (Node Msg)) (key : Option String := none) :
    Node Msg :=
  mk (Widget.container l.name) ({} : NoState) { key } (some l) (dedupKeys [] children)

theorem Node.dedupKeys_nodup (cs : List (Node Msg)) :
    ((dedupKeys [] cs).filterMap (·.key)).Nodup
```

So text from elsewhere may be used as a key: a message's id, say. Two siblings never share a key, so a message cannot take over another's state by claiming its id. At worst it loses its own key and merges by position.

### Secrets

`Secret` has a private constructor and no `ToString`, `Repr` or conversion to `SafeText`. Only widgets made to show secrets accept it, such as a passphrase field drawing dots. Message recording, model snapshots and logging require `Repr`, so a model holding a `Secret` cannot be passed to them by mistake.

## What the proofs do not cover

Each law is about the Lean side. Some guarantees also depend on things outside it:

- **Rust honours the Scene.** It must draw each item under its clip. That code is small and is tested against the Scene directly.
- **Measured text matches drawn text.** Layout trusts the measurement call, and the clip law keeps a wrong measurement from drawing outside the box.
- **Platform flags are truthful.** The obscured and synthetic flags come from the platform. On X11, input injected through XTEST is indistinguishable from real input.
- **`IO` is ambient authority.** A task is arbitrary `IO`, and Lean does not confine it. Capabilities govern effects the runtime performs. Running a task is itself a capability, `io`, which the root grants to the app's own components and withholds from components that do not need it. Paw provides narrow effects (fetch a URL, read a designated file) so that most components never need `io`.
- **Private constructors are a module boundary.** They stop accidents and code outside the runtime module, not code that uses `unsafe` features.

## Runtime loop

`Runtime.step` is pure: it takes the runtime's state and one event from the window, and returns the new state and a list of outputs. An output is either a request for the platform (draw a scene, set the title, write the clipboard, open a link, notify, quit) or a task to run. Tests drive `step` directly.

One step for input, as in monomer's `mainLoop`:

1. The router finds each event's target and makes a `Designation` if the checks pass.
2. Each delivery goes to its widget, and to the widget's ancestors in turn if it does not handle it. This is how a scroll gets the wheel over its content.
3. The messages that come out go to `update`, with origin `user d` if the delivery carried a designation `d` and `other` if not. A widget's `copy` request is honoured only with a designation.
4. If the model changed, the view is rebuilt, merged with the tree on screen, laid out, and the router notes where everything now is.
5. The scene is drawn again only if the model changed, a widget handled the input, or focus, hover or press moved. Pointer movement over a place where nothing reacts draws nothing.

`Runtime.run` is the IO loop around `step`, over a `Platform`, a structure of IO functions: poll events, the time, the window size, measure text, perform a request. The Rust layer provides one, and tests a scripted fake. Tasks run with `IO.asTask`; their results are stepped in with origin `other`.

Nodes, trees and the runtime must be in `Type` for `IO` to hold them. So a widget keeps its state as a `Dynamic`. Widgets are still written over their own state type, as a `Widget.Spec Msg σ` whose `build` wraps each function, and `render_within` carries through the wrapping.

## Testing

Tests run in this order:

1. **Pure, in-process tests of the core.** Build widget trees, feed events through the runtime loop with a fake platform, and assert on the Scene, the commands and the model.
2. **Property tests** of what the types do not already state, such as merge preserving widget state across reordering.
3. **FFI tests** of the Rust layer against recorded Scenes and events.
4. **On-device runs** on a Wayland compositor, an X11 session and Android, using the corpus from the security guidelines.

## Sources

- [monomer](https://github.com/fjvallarino/monomer) at commit 5c62393: `src/Monomer/Core/WidgetTypes.hs`, `Main/Core.hs`, `Main/Handlers.hs`, `Widgets/Composite.hs`, `Widgets/Container.hs`, `Widgets/Containers/Stack.hs`, `Graphics/Types.hs`, and its tutorials
- CryptWalker: `CryptWalker/NIKE/NIKE.lean`, `CryptWalker/KEM/KEM.lean`, `CryptWalker/KEM/Adapter.lean`
- [The Elm Architecture](https://guide.elm-lang.org/architecture/)
- [GUI_SECURITY_GUIDELINES.md](GUI_SECURITY_GUIDELINES.md)
