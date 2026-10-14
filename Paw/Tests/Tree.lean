/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Tree
import Paw.Tests.Util

/-! # The widget tree

Init, merge, dispose, layout and rendering, with small widgets made for the tests. The merge cases
follow monomer's life-cycle tutorial: keyed children keep their state when they move. -/

namespace Paw.Tests.Tree

open Paw

inductive Msg where
  | bumped (n : Nat)
  | gone (n : Nat)
  deriving Repr, DecidableEq

structure Count where
  n : Nat
  deriving TypeName, Repr, DecidableEq, Inhabited

def r (x y w h : Int) : Rect := Rect.ofXYWH (px x) (px y) (px w) (px h)

def sz (n : Nat) : Nat := (px n).toNat

/-- A leaf that counts the clicks it gets and reports them, and says goodbye when disposed. -/
def counter (label : Nat) (width : Nat := 10) : Widget Msg := Widget.Spec.build (σ := Count) {
  kind := "counter"
  init := ⟨0⟩
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz width), SizeReq.fixedSize (sz 10))
  render := fun _ st v => Scene.draw v (.fill v (Color.rgb (UInt8.ofNat label) (UInt8.ofNat st.n) 0) 0)
  render_within := fun _ _ v => Scene.draw_within _ (Rect.within_refl v)
  handle := fun _ st _ e => match e with
    | .click .. => some (⟨st.n + 1⟩, [.emit (.bumped (st.n + 1))])
    | _ => none
  dispose := fun st => [.emit (.gone st.n)] }

/-- A leaf of another kind. -/
def plain : Widget Msg := Widget.Spec.build (σ := NoState) {
  kind := "plain"
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz 5), SizeReq.fixedSize (sz 5))
  render := fun _ _ _ => Scene.empty
  render_within := fun _ _ v => Scene.empty_within v }

/-- A leaf that draws outside its box, which `Node.render` must not allow through. -/
def unruly : Widget Msg := Widget.Spec.build (σ := NoState) {
  kind := "unruly"
  init := {}
  sizeReq := fun _ _ => (SizeReq.fixedSize (sz 5), SizeReq.fixedSize (sz 5))
  render := fun _ _ v => (Scene.draw (v.translate ⟨px 100, 0⟩) (.fill (r 0 0 999 999) Color.black 0)).clip v
  render_within := fun _ _ v => Scene.clip_within v _ }

def env : Env := Env.mock

def leaf (w : Widget Msg) (key : Option String := none) : Node Msg := Node.leaf w (key := key)

def col (children : List (Node Msg)) : Node Msg := Node.container (vstack.toLayout) children

/-- Clicks the node with `id`, as the runtime does. -/
def clickAt (n : Node Msg) (id : WidgetId) : Node Msg × List (Req Msg) :=
  let (n, reqs) := n.handleAt env id (.click ⟨0, 0⟩ .primary 1)
  (n, reqs.getD [])

def counts (n : Node Msg) : List Nat :=
  n.children.map fun c => (c.state? Count).map (·.n) |>.getD 999

def tests : TestM Unit := do
  -- Init gives every node a distinct id.
  let (t, next) := (col [leaf (counter 1), leaf (counter 2)]).init 1
  checkEq "init assigns ids" [1, 2, 3] (t.ids.map (·.n))
  checkEq "the next id" 4 next
  -- Handling an event at a node changes only that node.
  let (t, reqs) := clickAt t ⟨3⟩
  checkEq "the click reaches the second counter" [0, 1] (counts t)
  checkEq "and it reports" [Req.emit (Msg.bumped 1)] reqs
  let (t, _) := clickAt t ⟨3⟩
  let (t, _) := clickAt t ⟨2⟩
  checkEq "state after three clicks" [1, 2] (counts t)
  checkEq "an unknown id changes nothing" [1, 2] (counts (clickAt t ⟨77⟩).1)
  -- Positional merge keeps state.
  let (m, reqs, next) := (col [leaf (counter 1), leaf (counter 2)]).merge env t next
  checkEq "same kinds in the same places keep their state" [1, 2] (counts m)
  checkEq "and their ids" [1, 2, 3] (m.ids.map (·.n))
  checkEq "nothing disposed" [] reqs
  checkEq "no new ids" 4 next
  -- Unkeyed children moved: state stays with the position, as in monomer.
  let (m, _, _) := (col [leaf (counter 2), leaf (counter 1)]).merge env t next
  checkEq "unkeyed children keep state by position" [1, 2] (counts m)
  -- Keyed children keep their own state when they move.
  let (k, next) := (col [leaf (counter 1) "a", leaf (counter 2) "b"]).init next
  let (k, _) := clickAt k ⟨k.children[1]!.id.n⟩
  let (k, _) := clickAt k ⟨k.children[1]!.id.n⟩
  let (k, _) := clickAt k ⟨k.children[0]!.id.n⟩
  checkEq "a=1, b=2" [1, 2] (counts k)
  let bId := k.children[1]!.id
  let (m, reqs, next') := (col [leaf (counter 2) "b", leaf (counter 1) "a"]).merge env k next
  checkEq "keyed children keep state when they move" [2, 1] (counts m)
  checkEq "and their ids" bId m.children[0]!.id
  checkEq "moved children are not disposed" [] reqs
  checkEq "no new ids for moved children" next next'
  -- A child of a new kind is new; the old children after it still match the new ones after it,
  -- so an insertion keeps the state of what follows, and the old child left over is disposed.
  let (m, reqs, next') := (col [leaf plain, leaf (counter 2)]).merge env t next
  checkEq "an inserted child starts fresh and the next keeps its state" [999, 1] (counts m)
  checkEq "the old child left over is disposed" [Req.emit (Msg.gone 2)] reqs
  checkEq "the new child gets a new id" next m.children[0]!.id.n
  checkEq "one new id" (next + 1) next'
  -- Removed children are disposed; a removed keyed child too.
  let (m, reqs, _) := (col [leaf (counter 2) "b"]).merge env k next
  checkEq "the keyed survivor keeps its state" [2] (counts m)
  checkEq "the removed keyed child is disposed" [Req.emit (Msg.gone 1)] reqs
  -- Keys are unique among siblings: a duplicate loses its key.
  let dup := col [leaf (counter 1) "x", leaf (counter 2) "x"]
  checkEq "a duplicate key is dropped" [some "x", none] (dup.children.map (·.key))
  check "keys are unique" (dup.children.filterMap (·.key)).Nodup
  -- Merge always gives the shape of the new view.
  check "merge has the new view's shape"
    (((col [leaf plain, leaf (counter 1) "a"]).merge env k next).1.shape ==
      (col [leaf plain, leaf (counter 1) "a"]).shape)
  -- Layout and rendering.
  let root := (col [leaf (counter 1 (width := 20)), leaf plain, leaf (counter 3)]).init 1 |>.1
  checkEq "a stack wants its children's sizes" (SizeReq.fixedSize (sz 20), SizeReq.fixedSize (sz 25))
    (root.sizeReq env)
  let laid := root.resize env (r 0 0 100 100)
  checkEq "children get their places" [r 0 0 100 10, r 0 10 100 5, r 0 15 100 10]
    (laid.children.map (·.viewport))
  checkEq "the root keeps its box" (r 0 0 100 100) laid.viewport
  let scene := laid.render env
  checkEq "the scene draws each counter" 2 scene.items.length
  check "the scene lies within the root" (decide (scene.Within (r 0 0 100 100)))
  let hidden := (Node.container (vstack.toLayout) [leaf (counter 1), (leaf (counter 2)).hide]).init 1 |>.1
  checkEq "a hidden child draws nothing" 1 ((hidden.resize env (r 0 0 50 50)).render env).items.length
  let bad := ((col [leaf unruly]).init 1).1.resize env (r 0 0 10 10)
  check "a widget's drawing stays in its box" (decide ((bad.render env).Within (r 0 0 10 5)))
  checkEq "find a node" (some ⟨2⟩) ((laid.find? ⟨2⟩).map (·.id))
  checkEq "find nothing" none ((laid.find? ⟨42⟩).map (·.id))
  checkEq "paths" [(1, []), (2, [0]), (3, [1]), (4, [2])] (laid.paths.map fun (i, p) => (i.n, p))
  checkEq "a mock measure" (px 30, px 20) (env.measure {} (SafeText.trusted "abc"))

end Paw.Tests.Tree
