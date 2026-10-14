/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widgets.Basic

/-! # Animations

Wrappers that bring their child in over a time: `fadeIn` draws it from transparent to opaque,
`slideIn` from an offset to its place. An animation starts at its first tick after it appears, and
ticks each frame until it ends. While it runs it counts as moving, so nothing in it can be
designated until it has been still for the router's delay: a control cannot be clicked into while
it is still faint, or still sliding under the pointer. With reduced motion, an animation is at its
end at once and never ticks. -/

namespace Paw.Widgets

structure AnimState where
  /-- When the first tick came: the animation's start. -/
  start : Option Nat := none
  deriving TypeName, Repr, Inhabited

/-- How often an animation ticks: about 60 times a second. -/
def frameMs : Nat := 16

/-- How far an animation of `ms` is at `env.now`, in thousandths. -/
def AnimState.progress (st : AnimState) (env : Env) (ms : Nat) : Nat :=
  if !env.motion then 1000
  else match st.start with
    | none => 0
    | some s => min 1000 ((env.now - s) * 1000 / max ms 1)

/-- An animation of `ms` that draws its children through `draw` and lays them out in `content`,
each given the progress in thousandths. -/
def animation {Msg : Type} (kind : String) (ms : Nat) (draw : Nat → Scene → Scene)
    (content : Nat → Rect → Rect) : Widget Msg :=
  Widget.Spec.build {
    kind
    init := ({} : AnimState)
    sizeReq := fun _ _ => ({}, {})
    content := fun env st v _ => content (st.progress env ms) v
    render := fun _ _ _ => Scene.empty
    render_within := fun _ _ v => Scene.empty_within v
    handle := fun _ st _ e => match e with
      | .tick now => some ({ start := st.start.orElse fun _ => some now }, [])
      | _ => none
    every := some fun env st => if st.progress env ms < 1000 then some frameMs else none
    moving := some fun env st => st.progress env ms < 1000
    mapChildren := fun env st s => draw (st.progress env ms) s }

/-- Its children drawn from transparent to opaque over `ms`. -/
def fadeIn {Msg : Type} (ms : Nat := 250) : Widget Msg :=
  animation "fadeIn" ms (fun p s => if p ≥ 1000 then s else s.withAlpha (p * 255 / 1000)) fun _ v => v

/-- Its children moved from `offset` to their place over `ms`. -/
def slideIn {Msg : Type} (offset : Point) (ms : Nat := 250) : Widget Msg :=
  animation "slideIn" ms (fun _ s => s) fun p v =>
    let k : Int := 1000 - p
    v.translate ⟨offset.x * k / 1000, offset.y * k / 1000⟩

end Paw.Widgets
