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

**Rust** holds what talks to the platform: Linux desktop, on X11 and Wayland, and Android.

| Concern | Crate | Why |
| --- | --- | --- |
| Windows and input | winit 0.30, driven with `pump_app_events`; its IME events for input methods. On Android, winit on GameActivity | Lean owns the loop and polls, as monomer polls SDL; no Lean code runs inside a winit callback. winit picks Wayland or X11 at startup |
| Drawing a Scene | tiny-skia, shown with softbuffer | Draws on the CPU, so the same scene gives the same pixels everywhere: golden images can be compared exactly, and no GPU is needed under Xvfb or a headless compositor |
| Decoding images | image, with only its PNG and JPEG decoders | No SVG and no other formats, so that less code reads content from elsewhere |
| Text shaping, measuring, drawing | cosmic-text, with DejaVu Sans bundled | Measuring and drawing use one font system, so text is drawn as wide as layout measured it. Offscreen renders use only the bundled fonts; a window adds the system's for characters they lack |
| Clipboard | arboard, with Wayland's data-control protocol; android_clipboard on Android | The clipboard is read only when the user presses Ctrl-V, which becomes a `paste` event |
| Opening links | webbrowser, which runs the user's browser with the link as one argument, never through a shell, and on Android sends it as an intent | Lean has already checked the link |
| Notifications | `notify-send`, run with the text as arguments; on Android, the notification manager, through JNI | |
| Accessibility | AccessKit 0.25 with `accesskit_winit` 0.34, over AT-SPI and Android's accessibility framework | Widgets describe themselves in Lean; Rust only passes the tree on |

Some platform facts the guidelines rely on, as they stand on Linux:

- **Synthetic input on X11.** winit reads the pointer through XInput2. A click another client sends with `XSendEvent` is a core event, not an XInput2 one, so it never reaches Paw; the end-to-end test checks this. Keys are different: winit reads them from core events and does not pass on the flag that marks one sent by another client, so keys sent with `XSendEvent` arrive as if typed, and so does any input sent through XTEST. `Input.synthetic` is never set on Linux. This is the guidelines' point that X11 has no trusted path between programs: any client on the display can type into any window. The end-to-end test reports it rather than hiding it.
- **Synthetic input on Wayland.** A client cannot send input to another client's window. Input that a compositor's virtual-keyboard or virtual-pointer protocol injects, as the end-to-end tests do, arrives as the compositor's own, which only programs the compositor trusts can use.
- **Keys held when focus arrives.** winit reports keys held while the window gains focus as synthetic key events. The Rust layer drops them, because they were not pressed in this window.
- **A lost display.** When the compositor or X server goes away, winit's loop exits, and the Rust layer reports `close`.
- **Focus and visibility.** winit's `Focused` and `Occluded` become `WindowEvent.focus` and `WindowEvent.visible`. Not every compositor reports occlusion; where none does, the window counts as seen.

On Android the app is one shared library, `libmain.so`, holding Lean's runtime, the C that Lean emits for the app and every module it imports, the stdlib among them, and the Rust layer. `android/build.sh` builds it with the NDK and packages it with GameActivity, from pinned sources and libraries. The Lean API is the same as on Linux; these are the platform's differences:

- **Threads.** Android delivers an app's events to the thread that runs `android_main`, which has a small stack. Lean's `main` runs on a thread of its own with the stack Lean asks for, and the window's calls are run on `android_main`'s thread, which between them keeps taking in the system's events.
- **Touch.** The first finger down is the primary button: a move to where it lands, a press, and on lifting a release and the pointer leaving the window, so nothing stays hovered. Other fingers are ignored until it lifts. The router's checks apply to taps as to clicks.
- **The soft keyboard.** It is shown while a text field asks for input, and it edits a buffer of its own, GameTextInput's. The Rust layer reads that buffer after each poll: characters removed become Backspace, characters added become `text`, a newline becomes Enter, and the composing region becomes the preedit. Keys from a hardware keyboard go to winit, as on Linux. winit reports no modifier changes on Android, so they are read from the modifier keys.
- **Insets.** GameActivity draws under the system's bars and the soft keyboard. The window's size is the area clear of them, which changes as the keyboard opens and closes and the screen turns, and is reported as a resize.
- **The back key** is Escape.
- **Lifecycle.** Android takes the window's surface away while the app is in the background and gives a new one when it returns; the app keeps running, and draws again. Lean's runtime starts once per process.

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
| Rendering | Only on request: input, `RenderOnce`, `RenderEvery`; overlays drawn after the main pass | The same; the Scene is sent to Rust only when a render is needed, with overlays after the tree |
| Tasks and producers | `Task (IO e)` for one result, `Producer` for a stream, both delivered to the widget that started them | `Cmd.task` for one result and `Cmd.producer` for a stream, both delivered to `update` with origin `other`; what producers sent since the last pass arrives together, with one rebuild and one frame. `App.start` runs commands when the app starts, as monomer's `appInitEvent` does |

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
| A widget opens an overlay with the `SetOverlay` request and closes it with `ResetOverlay` | An overlay is a node of the view, marked with `Node.overlay`; it is open while the view has it | One direction for data to flow: the model says what is open |
| The image widget reads files and fetches links itself | An app gets the bytes with a task and hands a decoded `Image` to the widget, which only shows it | Widgets do no IO; reading a file or the network is an effect the app's capabilities govern |
| Images are cached by path or link | An image's pixels stay in Rust under an id from a counter, freed when Lean drops the `Image` | No content can collide a hash to draw as another image, and Lean's reference counting says exactly when the platform may let go |
| A paragraph's height is guessed from the width it had in the last layout | A widget whose height depends on its width says so with `heightFor`, and the tree lays such a subtree out twice: for widths, then with the heights those widths give | Wrapped text is the right height in the first frame, and in every layout |
| A dropdown keeps whether it is open, and a split its divider's place, inside the widget | Both are the app's: the view says whether the dropdown's popup is open and where the split's divider is, and the widgets ask for changes | Overlays and layout come from the view, so the model says what is on screen |
| A numeric field parses with `read` and shows with `show`, and nothing ties them | A `Format` carries the proof that what it writes reads back as the value, and a field's bounds are a refinement type | A value out of bounds cannot be made; what a field shows is what the model holds |
| A text area breaks lines only at newlines | It wraps each line to its width, and Up and Down keep the caret's x across rows | Long lines of notes stay readable |
| A theme is any record of colors and styles | A `Theme` carries `contrast_ok` and `focus_visible`, decided when it is written | Text is readable and focus can be seen in every state of every control; an unreadable theme does not compile |
| `RenderEvery` and `RenderStop` requests start and stop a widget's timer, and while any runs, the loop draws 60 frames a second | A widget declares `every`, how often it wants `Event.tick`, as a function of its state; the loop sleeps until the next tick is due | A widget that leaves the tree or changes state stops ticking with nothing to undo; an idle app uses no CPU |
| `alert` and `confirm` can be opened by any message, and their accept button acts on any click | A modal opens only with a `Modal` token made from the designation of the input being handled; `confirm`'s accept button acts only on a designated click | Dialogs come only from the user's actions, and ignore input until they are stable (guidelines, Input) |

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
- **What is refused shows as U+FFFD** (�), which fonts have. A terminal shows a refused control character as its Control Picture (␛), but few fonts have those, and an empty box tells the user nothing.
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
| `Router` | `overlay_hit`: while an overlay is open, the pointer reaches only widgets in it; `press_outside`: a press outside it reaches nothing else | The user clicks what they see; a popup cannot steer a click to what it covers |
| `Node` | `overlays_within`: overlays draw within the window; `Overlay.place_within` | Content cannot set its own position |
| `Runtime` | `now_le_nextDeadline`: the loop never waits for a deadline already past | Timers fire when due |
| `Wrap` | `wrap_fits`: every line fits its width, or is one character too wide for any; `wrap_flatten`: the lines put back together are the text | Text stays in its box; wrapping loses or adds nothing |
| `Format` | `roundtrip`: `parse (print v) = some v`, proved for integers, fixed-point decimals, dates and times | A field shows exactly the value the model holds |
| `Theme` | `contrast_ok`: all text at least 4.5:1 on what it is drawn on, in every state; control edges 3:1; `focus_visible`: a focus ring 2 pixels wide, 3:1 against the window | Focus is the user's, and the user can see where it is; text is readable |
| `Node` | keys unique among siblings, by `dedupKeys_nodup` | State is never handed to another widget |

Widgets draw with `Scene.inBox v ds`, every item clipped to the box `v`, and `Scene.inBox_within` is their `render_within`.

A container's children are laid out in its content rectangle, which its widget names: the box itself, or for a scroll, a rectangle as tall as the content, shifted up by the scroll offset and narrowed by a gutter for the scroll bar. The layout laws hold relative to the content rectangle, and `Node.render` clips the children to the box, so the tree-wide law is unchanged. Two things follow:

- **The gutter is a reserved region.** The child's box never covers it, so no content can draw over the bar.
- **Scrolling is movement.** The router sees every widget in the content move, and treats each as unstable for `stableMs`. A click right after a scroll is delivered, but designates nothing.

Stacks and grids prove `assign_disjoint` once, between them. Each is an `Axial` layout that only decides a size per child along its axis. `Axial.toSeparated` places those sizes one after another and proves all three laws from a lemma about the placement. A new layout along one axis gets the laws by supplying its size function and a proof that it returns one size per child.

Overlap is sometimes wanted, as in a z-stack. That layout does not carry `assign_disjoint`. A container that needs reserved regions accepts only layouts that do, which is a type constraint on the container. A popup is not a layout at all, but an overlay.

### Overlays

A popup, a menu or a dialog draws above the rest of the window and takes input first. In Paw it is a node of the view like any other, marked as an overlay with `Node.overlay`, so it is open exactly while the view has it. The tree treats an overlay differently from its siblings in four places:

- **Layout.** Its parent's layout gives it no room. It is placed by `Overlay.place`, which puts a popup below its parent's box, or above it if there is no room below, and a modal over the whole window. Either way the result lies within the window: `Overlay.place_within`.
- **Drawing.** `Node.render` leaves overlays out, and `Node.renderOverlays` draws them afterwards, clipped to the window, so the base keeps `render_within` and the overlays have their own law, `overlays_within`.
- **Hit-testing and focus.** `hit?` and `focusables` do not enter overlays. The router starts from the topmost one instead.
- **Bubbling.** An event a widget in an overlay does not handle goes up to the overlay and stops there. Nothing bubbles out of an overlay into what lies beneath it.

While an overlay is open, the router gives it the pointer:

```lean
theorem Router.overlay_hit (ho : rt.overlayNode tree = some o) (h : rt.hitAt tree p = some m) :
    m.id ∈ o.ids

theorem Router.press_outside (hk : i.kind = .press p b) (ho : rt.overlay = some (o, k))
    (hm : (rt.hitAt tree p).filter (·.enabled) = none) :
    (rt.route tree i).2 = [{ target := o, event := .dismiss }]
```

A press outside the overlay reaches nothing but the overlay, as `Event.dismiss`, so a click aimed at a control that a popup has just covered does not land on it. The two kinds differ in what they take beyond the pointer:

- **A popup** leaves the keyboard alone: keys and text still go to the focused widget, which is how a field with suggestions keeps its typing. Escape goes to the popup, and Tab moves focus only among its widgets.
- **A modal** takes the keyboard too. Keys go to its focused widget, or to the modal itself if focus is outside it; text for a widget beneath it is dropped; assistive technology cannot act on anything beneath it. It dims the window, so what cannot be reached also looks it.

An overlay's widgets are new to the router when it opens, so for `stableMs` nothing in it can be designated. This is the guidelines' delay for dialogs, and it costs nothing extra.

A modal can be opened only by the user's input. `Ui.dialog`, and `alert` and `confirm` built on it, take a `Modal`, which has a private constructor:

```lean
structure Modal where
  private mk ::
  serial : Nat
  time : Nat

def Modal.open (d : Designation) : Modal := ⟨d.serial, d.time⟩
```

So an app can open one only in `update` at origin `user d`. A `Modal` can still be kept in the model and used later, as on a task's result, so the router also checks freshness. A modal may first appear only while the router handles the input whose designation made its token. Any other modal is refused: it is never drawn, input and assistive technology never reach it, and it is sent `dismiss` so that the app's model closes it.

A dialog's own buttons follow the same rule. `confirm`'s accept button sends its message with `Req.choose`, which the runtime passes to `update` only when the input designated the button. So a click within `stableMs` of the dialog appearing, a synthetic click or a press from a screen reader cannot confirm. Escape, Enter and the cancel button take the safe choice.

### Styles and themes

A control's look comes from a `Style` for its kind: a basic `StyleState` (background, text color, border, its width, radius, pointer shape), and what hover, focus, focus with hover, press and being disabled change in it. `Style.current` picks the state with monomer's priority, disabled first, then pressed, focus with hover, hover and focus, each laid over the basic look. A `Theme` holds a style for each kind of control and the window's colors, and two laws:

```lean
structure Theme extends ThemeData where
  contrast_ok : toThemeData.readable = true
  focus_visible : toThemeData.focusVisible = true
```

`readable` checks every text against what it is drawn on, in all sixteen combinations of states, by WCAG's measure: a contrast ratio of at least 4.5:1, with both colors opaque. It checks the window's text on the window and on panels, placeholders, and each control's text on its own background; and that each enabled control's border has 3:1 against the window, so the control's edge can be seen. `focusVisible` checks that each control's focused border differs from its unfocused one, is at least 2 pixels wide, and has 3:1 against the window.

The ratio needs relative luminance, which is defined with real numbers. Paw computes it exactly instead: a table holds each sRGB channel value's linear light in ten-millionths, luminance is a weighted sum of three entries, and the ratio (L₁ + 0.05) / (L₂ + 0.05) is compared with the threshold by cross-multiplying natural numbers. So `decide` checks a theme as it is written, and a theme with unreadable text or an invisible focus ring does not compile; `Tests/Rejects.lean` pins the error for each. Rounding in the table moves a ratio by far less than the threshold's precision.

`Ui.themed theme child` gives a subtree a theme of its own, on that theme's background. The tree passes the nearest theme down as it measures, places, draws and delivers, and an overlay drawn apart from the tree takes the theme of its ancestors, so a popup in a dark part of the window is dark too. `PAW_THEME=dark` picks the theme the app starts with. A disabled node (`Ui.enabled false`) takes no input or focus and is drawn in its style's disabled look. The pointer takes the shape the widget under it names, such as the text cursor over a field, and the platform is asked only when that changes.

### Text

`Wrap.wrap` breaks a line of text into lines that fit a width, greedily, as a paragraph is laid out. The text is cut into pieces, each a word and the spaces after it, and a line takes pieces while it fits with the next at its end. The spaces at a line's end hang past its edge, as in a browser: they never push a word onto the next line, and they are still part of the text. So the lines put back together are the text exactly, which is a theorem rather than a test:

```lean
theorem Wrap.wrap_flatten (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) :
    (wrap w measure cw cs).flatten = cs

theorem Wrap.wrap_fits (w : Int) (measure : List Char → Int) (cw : Char → Int) (cs : List Char) :
    ∀ l ∈ lines w measure cw cs, lineWidth Piece.core Piece.full l ≤ w ∨ ∃ p, l = [p] ∧ p.word.length ≤ 1
```

A word wider than the line is first cut into runs of characters that fit. Both laws come from one about packing anything greedily (`pack_fits`, `pack_flatten`), which wraps words into lines and characters into runs alike. Each distinct word is measured once per layout, and a run cut from a long word is measured by its characters. Drawing still draws each line as one run of text, clipped to the box, so a line whose shaped width differs from the sum of its words' widths by a pixel cannot draw outside it.

A wrapped paragraph's height depends on the width it gets, which a size request made before layout cannot know. A widget whose height depends on its width says so with `heightFor`. `measure` marks every node that is, or holds in flow, such a widget, and `place` lays out the children of a marked node twice: once to learn each child's width, then with each wrapping child's height at that width. Nothing else pays for it. The layout laws keep their form, since a layout is still given a box and items. Monomer instead uses the width from the previous layout, which is wrong for the first frame and after every resize.

Text blocks (`Ui.label`, `Ui.text`, `Ui.paragraph`) can wrap, show at most so many lines, and end with an ellipsis Paw draws (`TextOverflow`) rather than being cut at the edge. The ellipsis is drawn by Paw, so content cannot fake the end of a text.

**Editing.** A text field and a text area edit through the same pure `Edit` functions: insertion, deletion, selection, moving by characters and by words (Ctrl-←/→, Ctrl-Backspace, Ctrl-Delete), and lines (Home and End). Ctrl-Z and Ctrl-Shift-Z undo and redo, up to 100 steps. A password field's history holds `Secret`s, and it is forgotten when the field loses focus, so no earlier secret outlives the editing of it.

**Text areas.** A text area wraps each line to its width, so its text is shown as rows; by `wrap_flatten`, a position in the text is a row and a place in it. Up, Down, Page Up and Page Down keep the caret's x across rows of different lengths, and the area scrolls itself to keep the caret in view. Typing keeps newlines, and only in a text area. A text area keeps the rows of its text as last edited, with the text they were built from, and the wrapped rows of each line, so an edit wraps only the line it changed.

**Input methods.** A widget that takes text an input method composes says where its caret is (`Widget.ime`), and the runtime tells the platform, which turns the input method on, and places its window by the caret, only while such a widget and the window have focus. Text being composed arrives as `InputKind.preedit` and is drawn underlined at the caret, not yet part of the value; what the input method commits arrives as text. A password field gives no caret, so the input method is off while it has focus: a candidate window or a learning input method would otherwise see the secret.

### Widgets

Beyond labels, buttons, fields and scrolls, Paw has the rest of monomer's widgets, each with an
accessibility role, a section in the gallery and pure tests.

- **Choices.** Radio buttons, option buttons, toggle buttons and tabs are one widget, as in monomer's `makeOptionButton`, chosen or not and asking for their choice when activated. Their looks are two theme styles, `toggle` and `toggleOn`, which the theme's laws cover like every other control. Tabs are option buttons over a stack of pages; a page not shown keeps its state.
- **Fields for values.** `inputField` takes any type with a `Format`, a structure that carries the law that what it writes reads back as the value written. The digit functions for integers, fixed-point decimals, dates and times have their round trips proved, with no reals and no strings parsed by functions whose behaviour is only tested. The field keeps the text being typed; the model hears only of text that reads as a value, the field is marked while its text does not, and on leaving it gives the text up for the model's value. A number's bounds are a refinement type, `{x // lo ≤ x ∧ x ≤ hi}`, so stepping by Up, Down or the wheel clamps, and a value out of bounds cannot be made.
- **Sliders and dials** hold values of the same refinement type. A slider takes the value under the pointer when pressed and while dragged; a dial turns as it is dragged up or down; both step by keys and the wheel, and assistive technology's increment and decrement arrive as Up and Down.
- **Lists.** A select list's rows are lazy and keyed, so a list where one row changes costs about one row; keys choose and scroll to the item chosen. A dropdown is a button over a select list in a popup, open while the model says so.
- **Scrolls and splits.** A scroll scrolls down, across, or both, with a bar and gutter for each. A split shares its room between two children by a share the app holds; its divider is dragged, or moved by keys, with the resize pointer.
- **Links.** A link's caption may be anything, so where it goes, its scheme and host, is shown in a tooltip Paw draws, on hover and on focus. Opening it is an `Effect.openLink` of a `Link`, whose type carries the proof that its scheme is allowed, and needs the user's designation. Links have a theme color under the contrast law, since the accent is too faint for text on the light theme's background.
- **Drag and drop.** The router turns a press and a move of a few pixels on something `draggable` into a drag, and the release into `Event.drop` on the `dropTarget` under the pointer, with the dragged value as a `Dynamic` that the target reads at its own type. A drop is designated only as a click would be: not synthetic, not obscured, and the target still for `stableMs`. The drag is drawn faint under the pointer, Escape cancels it, and it stays within the window: values from other apps are pasted.
- **Colors and shadows.** A color picker is a slider and a field per channel beside a swatch; a color popup opens one from a swatch. A shadow is a few faint fills within the room its widget keeps around its child, so it needs no new kind of drawing and keeps the clipping law. `themeSwitch` is `Ui.themed`.

### Images

An app decodes an image with `Image.decode`, from bytes it got with a task, or makes one from pixels with `Image.ofRgba`. The Rust layer decodes PNG and JPEG only, reads the image's size from its header, and refuses one wider or taller than 8192 pixels or larger than 64 MiB of RGBA before allocating anything, so a small file that claims a huge canvas, or inflates to one, costs nothing. The tests decode such files from `tests/fixtures`.

The pixels stay in the Rust layer, where they are drawn. Lean's `Image` holds them through an external object whose finalizer releases them, so the platform keeps an image exactly as long as the app refers to it, and no request is needed to add or drop one. A scene names an image by id: `Draw.image r id alpha`, scaled into `r`, which `ImageFit` computes in Lean, and clipped like any other item. The id comes from a counter in the Rust layer, and `Image`'s constructor is private, so two images never share an id and an app cannot name one it does not hold. A content hash would let content crafted to collide it draw as another image, a trusted icon say.

An image widget must say what the image is to assistive technology, by its type:

```lean
inductive ImageAlt where
  | text (alt : SafeName)
  | decorative
```

There is no default: an image is described, or explicitly decoration that a screen reader passes over.

Icons are drawn from paths, `Draw.path`, in the theme's text color: close, plus, minus, check, two chevrons and a warning sign.

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
  | producer {o} (run : (Msg → IO Unit) → IO Unit) (granted : Cap.io ∈ caps) : Cmd Msg caps o
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
  mk (Widget.container l.name) (Dynamic.mk ({} : NoState)) { key } (some l) (dedupKeys ∅ children)

theorem Node.dedupKeys_nodup (cs : List (Node Msg)) :
    ((dedupKeys ∅ cs).filterMap (·.key)).Nodup
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
4. If the model changed, the view is rebuilt, merged with the tree on screen, laid out, and the router notes where everything now is and which overlays are open. Focus, hover and press on a widget that left the tree go with it. A modal that opened other than by this input is dismissed, and the view rebuilt again.
5. The scene is drawn again only if the model changed, a widget handled the input, or focus, hover or press moved. Pointer movement over a place where nothing reacts draws nothing.

`Runtime.run` is the IO loop around `step`, over a `Platform`, a structure of IO functions: poll events, the time, the window size, measure text, perform a request. The Rust layer provides one, and tests a scripted fake. Tasks run with `IO.asTask`; their results are stepped in with origin `other`. A producer runs on a dedicated thread and is given a `send`, which queues a message for the loop and wakes it. When the app quits, producers still running are cancelled, and their next `send` throws.

Nodes, trees and the runtime must be in `Type` for `IO` to hold them. So a widget keeps its state as a `Dynamic`. Widgets are still written over their own state type, as a `Widget.Spec Msg σ` whose `build` wraps each function, and `render_within` carries through the wrapping.

## Time

Widgets that change with time, such as a blinking caret or an animation, declare it: a widget's `every` gives how often it wants `Event.tick`, as a function of its state and the environment. This is Elm's rule for subscriptions, which are a function of the model. A text field ticks every 500 ms while it and the window have focus; an animation ticks each frame until it ends; a widget that leaves the tree, or whose state says it is done, stops ticking with nothing to undo. Monomer's `RenderEvery` and `RenderStop` requests need a widget to start and stop its own timer, and a widget in Paw cannot start anything when it appears, because it gets no event then.

The router keeps the schedule as it indexes the tree after each layout: a widget that still ticks as often keeps its next tick, a new one is due a period later. `Runtime.advance` is the step for time passing. It gives each widget whose tick is due an `Event.tick`, to that widget alone, and hands messages from `Cmd.after` that are due to `update`, with origin `other`, so a timer carries no authority whatever started it.

The loop sleeps in the platform's poll until an event or `Runtime.nextDeadline`, the earliest tick, delayed message or tooltip due. With nothing waiting it sleeps with no timeout, so an idle app uses no CPU; the end-to-end tests check this. Monomer instead draws 60 frames a second while anything is scheduled and polls otherwise. A task finishing and a producer sending wake the platform through `Platform.wake`, which sends winit a user event through its `EventLoopProxy`, so neither makes the loop poll; a wake or an event that comes between two polls ends the next one at once; on a platform that cannot be woken, the loop waits at most 16 ms while they run. While the window cannot be seen, widgets do not tick at all.

**Animations.** `fadeIn` and `slideIn` wrap a child and bring it in over a time from their first tick. A slide moves the content rectangle, as a scroll does, so hit-testing follows what is drawn. A fade lowers the alpha of its children's drawing through `mapChildren`, which changes the scene before the tree clips it to the box, so the clipping law is unchanged. An animation is not trusted to be harmless: while it runs, its widget's `moving` is true, and the router counts everything in it as moved on every frame. A control that is still faint, or still sliding under the pointer, cannot be designated until it has been still for `stableMs`. With reduced motion (`PAW_REDUCE_MOTION=1`), every animation is at its end at once and never ticks.

**Tooltips** are overlays of their own kind, `Overlay.tip`. One shows below its anchor once the pointer has rested there for a second, or at once while keyboard focus is in the anchor, so that keyboard users see it too. It takes no input: the router never makes it the overlay input goes to, and hit-testing never enters it. Whether it shows depends only on hover and time, which the runtime knows, so no widget has to add nodes to the view.

**Window focus.** While the window lacks keyboard focus, the runtime drops key, text and paste input before routing, whatever the platform sends.

## Accessibility

A widget may describe itself with an `Access`: a role (label, button, check box, text input, password input, scroll view, dialog, image, radio button, toggle button, slider, combo box, list and list item, link, separator, tab and tab list, spin button, date, time and color inputs), a name, a value, a checked or selected state, and for a value in a range, its bounds. Names and values are `SafeText`, filtered as anything on screen is, because a screen reader speaks them in the same voice as the app's own words. `Node.accessTree` flattens the tree into what assistive technology sees: a window over the widgets that describe themselves, with containers that do not left out. Each frame sends it beside the scene, and the Rust layer hands it to AccessKit.

- **A password field has a role and no value.** Lean never sends its value, and the Rust layer would drop one if it came.
- **A dialog is modal.** Its panel has the dialog role, named by its title, and AccessKit marks it modal. While a modal is open, the runtime refuses a screen reader's actions on anything beneath it, and a refused modal is left out of the tree.
- **A screen reader's actions designate nothing.** AccessKit's action requests come back as `WindowEvent.access`: a press is delivered to the widget as a click, and a focus moves focus. AT-SPI is a session bus that any program on it can talk to, so a press from it is no evidence of the user's choice, and it carries no designation: it cannot open a link or write the clipboard. A screen reader user keeps full authority through the keyboard, which is real input: Tab to the widget, then Enter.

## Performance

Latency in a GUI is seen, so each layer has benchmarks: `make bench-lean` runs LeanBench suites for text filtering, the byte formats, layout, the tree, routing, whole runtime steps and the calls into Rust, and `make bench-rust` times decoding, drawing and measuring in Rust. The budget is one input handled, from routing to the new scene, in well under a millisecond for an ordinary view, and a frame drawn in a few milliseconds, inside the 16 ms of a 60 Hz display.

What the benchmarks have shaped so far:

- **Nothing scans a list per element.** Merge finds keyed children through a hash map and records the old nodes it used in a hash set; key de-duplication keeps the keys seen in a hash set, and its uniqueness proof is about that set.
- **An event goes straight to its widget.** The router keeps each widget's path when it notes where widgets are, and an event walks down that path once, trying the deepest widget first and then each ancestor, rather than searching the tree for each of them.
- **Overlays are found in the walk that already indexes the tree.** The router notes the open ones and their paths, and a frame draws them from those paths, without searching the tree.
- **Size requests are worked out once per layout.** `measure` computes every node's request bottom up and keeps it, and `place` lays out from the kept requests.
- **Moving the pointer over nothing that reacts costs no layout or drawing.** The scene is drawn again only if something changed.
- **Most text is ASCII**, so the character checks decide printable ASCII first.
- **A view need not be rebuilt where nothing changed.** `Ui.lazy arg view` makes a deferred node. Before a merge, `resolve` matches it against the tree on screen: if the old node was built from an argument equal to `arg`, it is kept whole, without being built, merged or disposed; otherwise `view arg` is built then. This is Elm's `Html.Lazy`. Arguments are compared with `BEq`, never a hash: text from elsewhere could be crafted to collide a hash, and a collision would leave a stale row on screen. A long list whose rows are lazy costs, when one row changes, about one row.

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
