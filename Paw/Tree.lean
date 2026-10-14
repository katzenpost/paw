/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widget

/-! # The widget tree

A node holds a widget, its state, its place in the tree and, for a container, a layout and
children. The view builds a fresh tree on every change; `merge` matches it against the tree on
screen, as monomer's does: a new child takes over the state of the old child in the same place if
both are of the same kind with the same key, and otherwise of the old child with its key. Children
that match nothing are new, and old children left unmatched are disposed.

Keys are unique among siblings: the only ways to build a node drop a key a sibling before already
has, so text from elsewhere used as a key cannot take over another widget's state.

`render` clips each node's children to the node's box, so a whole tree draws within its root's
box whatever its widgets or layouts do. -/

namespace Paw

structure NodeInfo where
  id : WidgetId := ⟨0⟩
  key : Option String := none
  visible : Bool := true
  enabled : Bool := true
  viewport : Rect := default
  deriving Repr, Inhabited

inductive Node (Msg : Type) where
  | private mk (w : Widget Msg) (st : w.State) (info : NodeInfo) (layout : Option Layout)
      (children : List (Node Msg))

/-- A node's kind, key and visibility, and its children's, without state. -/
inductive Shape where
  | mk (kind : String) (key : Option String) (visible : Bool) (children : List Shape)
  deriving Repr, BEq

namespace Node

variable {Msg : Type}

def widget : Node Msg → Widget Msg | mk w .. => w
def info : Node Msg → NodeInfo | mk _ _ i _ _ => i
def children : Node Msg → List (Node Msg) | mk _ _ _ _ cs => cs
def id (n : Node Msg) : WidgetId := n.info.id
def key (n : Node Msg) : Option String := n.info.key
def visible (n : Node Msg) : Bool := n.info.visible
def viewport (n : Node Msg) : Rect := n.info.viewport
def enabled (n : Node Msg) : Bool := n.info.enabled
def kind (n : Node Msg) : String := n.widget.kind

/-- Whether the node can take keyboard focus. -/
def focusable (n : Node Msg) : Bool := n.widget.focusable && n.enabled && n.visible

/-- The node's state, if it is an `α`. -/
def state? (α : Type) [TypeName α] : Node Msg → Option α
  | mk _ st .. => (Dynamic.mk st).get? α

def withInfo (f : NodeInfo → NodeInfo) : Node Msg → Node Msg
  | mk w st i l cs => mk w st (f i) l cs

@[simp] theorem key_withInfo (f : NodeInfo → NodeInfo) (n : Node Msg) :
    (n.withInfo f).key = (f n.info).key := by cases n; rfl

def hide (n : Node Msg) : Node Msg := n.withInfo ({ · with visible := false })

def disable (n : Node Msg) : Node Msg := n.withInfo ({ · with enabled := false })

/-- Children with any key a sibling before already has dropped. -/
def dedupKeys (seen : List String) : List (Node Msg) → List (Node Msg)
  | [] => []
  | c :: cs => match c.key with
    | some k =>
      if k ∈ seen then c.withInfo ({ · with key := none }) :: dedupKeys seen cs
      else c :: dedupKeys (k :: seen) cs
    | none => c :: dedupKeys seen cs

theorem dedupKeys_spec (seen : List String) (cs : List (Node Msg)) :
    ((dedupKeys seen cs).filterMap (·.key)).Nodup ∧
      ∀ k ∈ (dedupKeys seen cs).filterMap (·.key), k ∉ seen := by
  induction cs generalizing seen with
  | nil => simp [dedupKeys]
  | cons c cs ih =>
    unfold dedupKeys
    split
    · rename_i k hk
      split
      · simp only [List.filterMap_cons, key_withInfo]
        exact ih seen
      · rename_i hnot
        have ⟨h1, h2⟩ := ih (k :: seen)
        simp only [List.filterMap_cons, hk, List.nodup_cons, List.mem_cons, not_or] at h2 ⊢
        refine ⟨⟨fun hm => (h2 k hm).1 rfl, h1⟩, ?_⟩
        intro k' hk'
        rcases hk' with rfl | hk'
        · exact hnot
        · exact (h2 k' hk').2
    · rename_i hk
      simp only [List.filterMap_cons, hk]
      exact ih seen

theorem dedupKeys_nodup (cs : List (Node Msg)) : ((dedupKeys [] cs).filterMap (·.key)).Nodup :=
  (dedupKeys_spec [] cs).1

/-- A widget with no children. -/
def leaf (w : Widget Msg) (key : Option String := none) : Node Msg := mk w w.init { key } none []

/-- Children laid out by `l`. -/
def container (l : Layout) (children : List (Node Msg)) (key : Option String := none) : Node Msg :=
  mk (Widget.container l.name) ({} : NoState) { key } (some l) (dedupKeys [] children)

instance : Inhabited (Node Msg) := ⟨leaf (Widget.container "")⟩

mutual
/-- Gives the node and its descendants ids from `next` on, in preorder. -/
def init : Node Msg → Nat → Node Msg × Nat
  | mk w st i l cs, next =>
    let (cs', next') := initList cs (next + 1)
    (mk w st { i with id := ⟨next⟩ } l cs', next')

def initList : List (Node Msg) → Nat → List (Node Msg) × Nat
  | [], next => ([], next)
  | c :: cs, next =>
    let (c', n1) := init c next
    let (cs', n2) := initList cs n1
    (c' :: cs', n2)
end

mutual
def ids : Node Msg → List WidgetId
  | mk _ _ i _ cs => i.id :: idsList cs

def idsList : List (Node Msg) → List WidgetId
  | [] => []
  | c :: cs => ids c ++ idsList cs
end

mutual
/-- What the node and its descendants ask for when they leave the tree. -/
def dispose : Node Msg → List (Req Msg)
  | mk w st _ _ cs => w.dispose st ++ disposeList cs

def disposeList : List (Node Msg) → List (Req Msg)
  | [] => []
  | c :: cs => dispose c ++ disposeList cs
end

mutual
def shape : Node Msg → Shape
  | mk w _ i _ cs => .mk w.kind i.key i.visible (shapeList cs)

def shapeList : List (Node Msg) → List Shape
  | [] => []
  | c :: cs => shape c :: shapeList cs
end

def layoutName : Node Msg → Option String
  | mk _ _ _ l _ => l.map (·.name)

/-- Whether `old` may pass its state to `new`. -/
def canMerge (new old : Node Msg) : Bool :=
  new.kind == old.kind && new.key == old.key && new.layoutName == old.layoutName

/-- The state `new` starts with, given the node it replaces. -/
def carryState : Node Msg → Node Msg → Node Msg
  | mk w st i l cs, mk _ ost .. =>
    match (Dynamic.mk ost).get? w.State with
    | some s => mk w (w.merge s) i l cs
    | none => mk w st i l cs

/-- The merge's running state: the next free id, requests, and ids of old nodes merged. -/
structure MergeState (Msg : Type) where
  next : Nat
  reqs : List (Req Msg) := []
  used : List WidgetId := []

/-- `n` as a new node, with fresh ids. -/
def freshen (n : Node Msg) (s : MergeState Msg) : Node Msg × MergeState Msg :=
  let (n', next) := n.init s.next
  (n', { s with next })

mutual
/-- `new` merged with `old`, which it `canMerge` with. -/
def mergeNode (env : Env) : Node Msg → Node Msg → MergeState Msg → Node Msg × MergeState Msg
  | mk w st i l cs, old, s =>
    let s := { s with used := old.id :: s.used }
    let oldKids := old.children
    let byKey := oldKids.filterMap fun c => c.key.map (·, c)
    let (cs', s) := mergeList env cs oldKids byKey s
    let gone := oldKids.filter fun c => !s.used.contains c.id
    let s := { s with reqs := s.reqs ++ gone.flatMap dispose }
    (carryState (mk w st { i with id := old.id } l cs') old, s)

/-- `n` merged with the old child with its key, if they can merge, else new. -/
def mergeKeyed (env : Env) (n : Node Msg) (byKey : List (String × Node Msg)) (s : MergeState Msg) :
    Node Msg × MergeState Msg :=
  match n.key.bind (byKey.lookup ·) with
  | some k => if canMerge n k then mergeNode env n k s else freshen n s
  | none => freshen n s

/-- monomer's `mergeChildSeq`: each new child merges with the old child in its place if they
can, else with the old child with its key if they can, else it is new. -/
def mergeList (env : Env) : List (Node Msg) → List (Node Msg) → List (String × Node Msg) →
    MergeState Msg → List (Node Msg) × MergeState Msg
  | [], _, _, s => ([], s)
  | n :: ns, o :: os, byKey, s =>
    if canMerge n o then
      let (m, s) := mergeNode env n o s
      let (ms, s) := mergeList env ns os byKey s
      (m :: ms, s)
    else
      let (m, s) := mergeKeyed env n byKey s
      let (ms, s) := mergeList env ns (o :: os) byKey s
      (m :: ms, s)
  | n :: ns, [], byKey, s =>
    let (m, s) := mergeKeyed env n byKey s
    let (ms, s) := mergeList env ns [] byKey s
    (m :: ms, s)
end

/-- The new view `new` merged with the tree `old` on screen: the merged tree, what old nodes
left behind ask on leaving, and the next free id. -/
def merge (new : Node Msg) (env : Env) (old : Node Msg) (next : Nat) :
    Node Msg × List (Req Msg) × Nat :=
  let (n, s) :=
    if canMerge new old then mergeNode env new old { next }
    else
      let (n, s) := freshen new { next }
      (n, { s with reqs := s.reqs ++ old.dispose })
  (n, s.reqs, s.next)

mutual
/-- What the node asks for: a leaf's widget decides, a container's layout. -/
def sizeReq (env : Env) : Node Msg → SizeReq × SizeReq
  | mk w st _ none _ => w.sizeReq env st
  | mk _ _ _ (some l) cs => l.sizeReq (itemList env cs)

def itemList (env : Env) : List (Node Msg) → List Item
  | [] => []
  | c :: cs =>
    let (w, h) := sizeReq env c
    { w, h, visible := c.visible } :: itemList env cs
end

mutual
/-- The node placed in `v`, and its children where its layout puts them. -/
def resize (env : Env) : Node Msg → Rect → Node Msg
  | mk w st i none cs, v => mk w st { i with viewport := v } none cs
  | mk w st i (some l) cs, v =>
    mk w st { i with viewport := v } (some l) (resizeList env cs (l.assign v (itemList env cs)))

def resizeList (env : Env) : List (Node Msg) → List Rect → List (Node Msg)
  | c :: cs, r :: rs => resize env c r :: resizeList env cs rs
  | cs, [] => cs
  | [], _ => []
end

mutual
/-- What the node and its descendants draw, within its box. -/
def render (env : Env) : Node Msg → Scene
  | mk w st i _ cs =>
    if i.visible then w.render env st i.viewport ++ (renderList env cs).clip i.viewport
    else Scene.empty

def renderList (env : Env) : List (Node Msg) → Scene
  | [] => Scene.empty
  | c :: cs => render env c ++ renderList env cs
end

theorem render_within (env : Env) (n : Node Msg) : (n.render env).Within n.viewport := by
  rcases n with ⟨w, st, i, l, cs⟩
  · simp only [render, viewport, info]
    split
    · exact Scene.append_within (w.render_within env st i.viewport) (Scene.clip_within _ _)
    · exact Scene.empty_within _

mutual
def find? (id : WidgetId) : Node Msg → Option (Node Msg)
  | n@(mk _ _ i _ cs) => if i.id == id then some n else findList? id cs

def findList? (id : WidgetId) : List (Node Msg) → Option (Node Msg)
  | [] => none
  | c :: cs => (find? id c).orElse fun _ => findList? id cs
end

mutual
/-- Every node's id and its path from the root, as child indices, in preorder. -/
def pathsFrom (path : List Nat) : Node Msg → List (WidgetId × List Nat)
  | mk _ _ i _ cs => (i.id, path) :: pathsList path 0 cs

def pathsList (path : List Nat) (idx : Nat) : List (Node Msg) → List (WidgetId × List Nat)
  | [] => []
  | c :: cs => pathsFrom (path ++ [idx]) c ++ pathsList path (idx + 1) cs
end

def paths (n : Node Msg) : List (WidgetId × List Nat) := pathsFrom [] n

mutual
/-- The node with `id` handles `e`; the tree with its new state, and its requests. -/
def handleAt (env : Env) (id : WidgetId) (e : Event) : Node Msg → Node Msg × List (Req Msg)
  | mk w st i l cs =>
    if i.id == id then
      match w.handle env st i.viewport e with
      | some (st', reqs) => (mk w st' i l cs, reqs)
      | none => (mk w st i l cs, [])
    else
      let (cs', reqs) := handleList env id e cs
      (mk w st i l cs', reqs)

def handleList (env : Env) (id : WidgetId) (e : Event) :
    List (Node Msg) → List (Node Msg) × List (Req Msg)
  | [] => ([], [])
  | c :: cs =>
    let (c', r1) := handleAt env id e c
    let (cs', r2) := handleList env id e cs
    (c' :: cs', r1 ++ r2)
end

mutual
/-- The tree with its messages mapped by `f`. -/
def mapMsg {β : Type} (f : Msg → β) : Node Msg → Node β
  | mk w st i l cs => mk (w.mapMsg f) st i l (mapMsgList f cs)

def mapMsgList {β : Type} (f : Msg → β) : List (Node Msg) → List (Node β)
  | [] => []
  | c :: cs => mapMsg f c :: mapMsgList f cs
end

mutual
/-- The topmost visible node at `p`: the deepest, and of overlapping siblings the later. -/
def hit? (p : Point) : Node Msg → Option (Node Msg)
  | n@(mk _ _ i _ cs) =>
    if i.visible && i.viewport.contains p then (hitList? p cs).orElse fun _ => some n else none

def hitList? (p : Point) : List (Node Msg) → Option (Node Msg)
  | [] => none
  | c :: cs => (hitList? p cs).orElse fun _ => hit? p c
end

mutual
theorem hit_spec (p : Point) : ∀ (n m : Node Msg), hit? p n = some m →
    m.viewport.contains p = true ∧ m.visible = true
  | mk w st i l cs, m, h => by
    simp only [hit?] at h
    split at h
    · rename_i hc
      cases hl : hitList? p cs with
      | some m' =>
        rw [hl] at h
        simp only [Option.orElse_some, Option.some.injEq] at h
        subst h
        exact hitList_spec p cs m' hl
      | none =>
        rw [hl] at h
        simp only [Option.orElse_none, Option.some.injEq] at h
        subst h
        simp only [Bool.and_eq_true] at hc
        exact ⟨hc.2, hc.1⟩
    · cases h

theorem hitList_spec (p : Point) : ∀ (cs : List (Node Msg)) (m : Node Msg), hitList? p cs = some m →
    m.viewport.contains p = true ∧ m.visible = true
  | [], m, h => by cases h
  | c :: cs, m, h => by
    simp only [hitList?] at h
    cases hl : hitList? p cs with
    | some m' =>
      rw [hl] at h
      simp only [Option.orElse_some, Option.some.injEq] at h
      subst h
      exact hitList_spec p cs m' hl
    | none =>
      rw [hl] at h
      simp only [Option.orElse_none] at h
      exact hit_spec p c m h
end

mutual
/-- The nodes that can take focus, in the order tab visits them. -/
def focusables : Node Msg → List WidgetId
  | n@(mk _ _ i _ cs) =>
    if i.visible then (if n.focusable then [i.id] else []) ++ focusablesList cs else []

def focusablesList : List (Node Msg) → List WidgetId
  | [] => []
  | c :: cs => focusables c ++ focusablesList cs
end

mutual
/-- Every visible node's id and box. -/
def placements : Node Msg → List (WidgetId × Rect)
  | mk _ _ i _ cs => if i.visible then (i.id, i.viewport) :: placementsList cs else []

def placementsList : List (Node Msg) → List (WidgetId × Rect)
  | [] => []
  | c :: cs => placements c ++ placementsList cs
end

end Node

end Paw
