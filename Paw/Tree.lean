/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Widget
import Std.Data.HashSet
import Std.Data.HashMap

/-! # The widget tree

A node holds a widget, its state, its place in the tree and, for a container, a layout and
children. The view builds a fresh tree on every change; `merge` matches it against the tree on
screen, as monomer's does: a new child takes over the state of the old child in the same place if
both are of the same kind with the same key, and otherwise of the old child with its key. Children
that match nothing are new, and old children left unmatched are disposed.

Keys are unique among siblings: the only ways to build a node drop a key a sibling before already
has, so text from elsewhere used as a key cannot take over another widget's state.

`render` clips each node's children to the node's box, so a whole tree draws within its root's
box whatever its widgets or layouts do.

A view may defer part of itself with `Ui.lazy`: a deferred node holds an argument and a way to
build its subtree from it. Before a merge, `resolve` matches deferred nodes against the tree on
screen: if the old node was built from an equal argument, it is kept as it is, unbuilt and
unmerged; otherwise the subtree is built then. Arguments are compared with `BEq`, not a hash,
since content from elsewhere could be crafted to collide a hash and leave a stale subtree on
screen. Deferred nodes exist only in a view before it is resolved; every function on a resolved
tree treats one, should it meet one, as an empty leaf. -/

namespace Paw

instance : Repr Dynamic := ⟨fun _ _ => "<dynamic>"⟩

structure NodeInfo where
  id : WidgetId := ⟨0⟩
  key : Option String := none
  visible : Bool := true
  enabled : Bool := true
  viewport : Rect := default
  /-- Where the children are laid out: the viewport, or for a scroll, the shifted content. -/
  content : Rect := default
  /-- What the node asks for, as `measure` last found it. -/
  req : SizeReq × SizeReq := ({}, {})
  /-- For a node built by `Ui.lazy`, the argument it was built from. -/
  memo : Option Dynamic := none
  /-- Kept as it was by `resolve`, so that merge keeps it whole. -/
  reused : Bool := false
  /-- `req` holds for the node as it is: no state below it has changed since `measure`. -/
  measured : Bool := false
  deriving Repr, Inhabited

inductive Node (Msg : Type) where
  | private mk (w : Widget Msg) (st : Dynamic) (info : NodeInfo) (layout : Option Layout)
      (children : List (Node Msg))
  /-- A subtree to build from `arg` with `build`, unless the tree on screen has one built from an
  argument `same` holds equal. -/
  | private deferred (info : NodeInfo) (arg : Dynamic) (same : Dynamic → Bool) (build : Unit → Node Msg)

/-- A node of the accessibility tree: a widget that describes itself, with the nearest such widgets
below it as its children. -/
structure AccessNode where
  id : Nat
  access : Access
  bounds : Rect
  focusable : Bool
  disabled : Bool
  children : List Nat
  deriving Repr, DecidableEq, Inhabited

/-- A node's kind, key and visibility, and its children's, without state. -/
inductive Shape where
  | mk (kind : String) (key : Option String) (visible : Bool) (children : List Shape)
  deriving Repr, BEq

namespace Node

variable {Msg : Type}

def widget : Node Msg → Widget Msg | mk w .. => w | deferred .. => Widget.container "deferred"
def info : Node Msg → NodeInfo | mk _ _ i _ _ => i | deferred i .. => i
def children : Node Msg → List (Node Msg) | mk _ _ _ _ cs => cs | deferred .. => []
def id (n : Node Msg) : WidgetId := n.info.id
def key (n : Node Msg) : Option String := n.info.key
def visible (n : Node Msg) : Bool := n.info.visible
def viewport (n : Node Msg) : Rect := n.info.viewport

/-- The environment as the widget at `i` sees it. -/
def envAt (env : Env) (i : NodeInfo) : Env := { env with self := i.id, content := i.content }
def enabled (n : Node Msg) : Bool := n.info.enabled
def kind (n : Node Msg) : String := n.widget.kind

/-- Whether the node can take keyboard focus. -/
def focusable (n : Node Msg) : Bool := n.widget.focusable && n.enabled && n.visible

/-- The node's state, if it is an `α`. -/
def state? (α : Type) [TypeName α] : Node Msg → Option α
  | mk _ st .. => st.get? α
  | deferred .. => none

def withInfo (f : NodeInfo → NodeInfo) : Node Msg → Node Msg
  | mk w st i l cs => mk w st (f i) l cs
  | deferred i a s b => deferred (f i) a s b

@[simp] theorem key_withInfo (f : NodeInfo → NodeInfo) (n : Node Msg) :
    (n.withInfo f).key = (f n.info).key := by cases n <;> rfl

def hide (n : Node Msg) : Node Msg := n.withInfo ({ · with visible := false })

def disable (n : Node Msg) : Node Msg := n.withInfo ({ · with enabled := false })

/-- Children with any key a sibling before already has dropped. -/
def dedupKeys (seen : Std.HashSet String) : List (Node Msg) → List (Node Msg)
  | [] => []
  | c :: cs => match c.key with
    | some k =>
      if seen.contains k then c.withInfo ({ · with key := none }) :: dedupKeys seen cs
      else c :: dedupKeys (seen.insert k) cs
    | none => c :: dedupKeys seen cs

theorem dedupKeys_spec (seen : Std.HashSet String) (cs : List (Node Msg)) :
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
        have ⟨h1, h2⟩ := ih (seen.insert k)
        simp only [Std.HashSet.mem_insert, beq_iff_eq, not_or] at h2
        simp only [List.filterMap_cons, hk, List.nodup_cons, List.mem_cons]
        refine ⟨⟨fun hm => (h2 k hm).1 rfl, h1⟩, ?_⟩
        intro k' hk'
        rcases hk' with rfl | hk'
        · exact fun hm => hnot (Std.HashSet.mem_iff_contains.mp hm)
        · exact (h2 k' hk').2
    · rename_i hk
      simp only [List.filterMap_cons, hk]
      exact ih seen

theorem dedupKeys_nodup (cs : List (Node Msg)) : ((dedupKeys ∅ cs).filterMap (·.key)).Nodup :=
  (dedupKeys_spec ∅ cs).1

/-- A widget with no children. -/
def leaf (w : Widget Msg) (key : Option String := none) : Node Msg := mk w w.init { key } none []

/-- Children laid out by `l`. -/
def container (l : Layout) (children : List (Node Msg)) (key : Option String := none) : Node Msg :=
  mk (Widget.container l.name) (Dynamic.mk ({} : NoState)) { key } (some l) (dedupKeys ∅ children)

/-- Children laid out by `l`, held by a widget of the container's own, such as a scroll that draws
bars and handles the wheel. -/
def containerWith (w : Widget Msg) (l : Layout) (children : List (Node Msg))
    (key : Option String := none) : Node Msg :=
  mk w w.init { key } (some l) (dedupKeys ∅ children)

instance : Inhabited (Node Msg) := ⟨leaf (Widget.container "")⟩

/-- A subtree built from `arg` by `view`, unless the tree on screen already has one built from an
equal argument. -/
def lazy {α : Type} [BEq α] [TypeName α] (arg : α) (view : α → Node Msg)
    (key : Option String := none) : Node Msg :=
  deferred { key } (Dynamic.mk arg) (fun d => (d.get? α).any (· == arg)) (fun _ => view arg)

/-- The view `new` with its deferred nodes resolved against `old`, the tree on screen: kept from
`old` where built from an equal argument, built otherwise. Children are matched with old children
by key, else by position. -/
partial def resolve (new : Node Msg) (old : Option (Node Msg)) : Node Msg :=
  match new with
  | deferred i arg same build =>
    let fresh (o : Option (Node Msg)) :=
      (resolve (build ()) o).withInfo ({ · with memo := some arg, key := i.key, reused := false })
    match old with
    | some o =>
      if o.key == i.key && o.info.memo.any same then o.withInfo ({ · with reused := true })
      else fresh (some o)
    | none => fresh none
  | mk w st i l cs =>
    let olds := (old.map children).getD []
    let byKey : Std.HashMap String (Node Msg) :=
      olds.foldl (init := {}) fun m c => match c.key with | some k => m.insert k c | none => m
    let rec go : Nat → List (Node Msg) → List (Node Msg)
      | _, [] => []
      | idx, c :: cs =>
        let o := match c.key.bind (byKey[·]?) with
          | some o => some o
          | none => olds[idx]?
        resolve c o :: go (idx + 1) cs
    mk w st i l (go 0 cs)

mutual
/-- Gives the node and its descendants ids from `next` on, in preorder. -/
def init : Node Msg → Nat → Node Msg × Nat
  | mk w st i l cs, next =>
    let (cs', next') := initList cs (next + 1)
    (mk w st { i with id := ⟨next⟩ } l cs', next')
  | deferred i a s b, next => (deferred { i with id := ⟨next⟩ } a s b, next + 1)

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
  | deferred i .. => [i.id]

def idsList : List (Node Msg) → List WidgetId
  | [] => []
  | c :: cs => ids c ++ idsList cs
end

mutual
/-- What the node and its descendants ask for when they leave the tree. -/
def dispose : Node Msg → List (Req Msg)
  | mk w st _ _ cs => w.dispose st ++ disposeList cs
  | deferred .. => []

def disposeList : List (Node Msg) → List (Req Msg)
  | [] => []
  | c :: cs => dispose c ++ disposeList cs
end

mutual
def shape : Node Msg → Shape
  | mk w _ i _ cs => .mk w.kind i.key i.visible (shapeList cs)
  | deferred i .. => .mk "deferred" i.key i.visible []

def shapeList : List (Node Msg) → List Shape
  | [] => []
  | c :: cs => shape c :: shapeList cs
end

def layoutName : Node Msg → Option String
  | mk _ _ _ l _ => l.map (·.name)
  | deferred .. => none

/-- Whether `old` may pass its state to `new`. -/
def canMerge (new old : Node Msg) : Bool :=
  new.kind == old.kind && new.key == old.key && new.layoutName == old.layoutName

/-- `new` with the state its widget keeps from the node it replaces. -/
def carryState : Node Msg → Node Msg → Node Msg
  | mk w _ i l cs, mk _ ost .. => mk w (w.merge ost) i l cs
  | n, _ => n

/-- The merge's running state: the next free id, requests, and ids of old nodes merged. -/
structure MergeState (Msg : Type) where
  next : Nat
  reqs : Array (Req Msg) := #[]
  used : Std.HashSet WidgetId := {}

/-- `n` as a new node, with fresh ids. -/
def freshen (n : Node Msg) (s : MergeState Msg) : Node Msg × MergeState Msg :=
  let (n', next) := n.init s.next
  (n', { s with next })

mutual
/-- `new` merged with `old`, which it `canMerge` with. -/
def mergeNode (env : Env) : Node Msg → Node Msg → MergeState Msg → Node Msg × MergeState Msg
  | mk w st i l cs, old, s =>
    let s := { s with used := s.used.insert old.id }
    -- A node `resolve` kept from the tree on screen stays whole.
    if i.reused && i.id == old.id then (mk w st { i with reused := false } l cs, s) else
    let oldKids := old.children
    let byKey : Std.HashMap String (Node Msg) :=
      oldKids.foldl (init := {}) fun m c => match c.key with | some k => m.insert k c | none => m
    let (cs', s) := mergeList env cs oldKids byKey s
    let gone := oldKids.filter fun c => !s.used.contains c.id
    let s := { s with reqs := s.reqs ++ (gone.flatMap dispose).toArray }
    (carryState (mk w st { i with id := old.id } l cs') old, s)
  | n, _, s => (n, s)

/-- `n` merged with the old child with its key, if they can merge, else new. -/
def mergeKeyed (env : Env) (n : Node Msg) (byKey : Std.HashMap String (Node Msg)) (s : MergeState Msg) :
    Node Msg × MergeState Msg :=
  match n.key.bind (byKey[·]?) with
  | some k => if canMerge n k then mergeNode env n k s else freshen n s
  | none => freshen n s

/-- monomer's `mergeChildSeq`: each new child merges with the old child in its place if they
can, else with the old child with its key if they can, else it is new. -/
def mergeList (env : Env) : List (Node Msg) → List (Node Msg) → Std.HashMap String (Node Msg) →
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
      (n, { s with reqs := s.reqs ++ old.dispose.toArray })
  (n, s.reqs.toList, s.next)

mutual
/-- What the node asks for: a leaf's widget decides, a container's layout. -/
def sizeReq (env : Env) : Node Msg → SizeReq × SizeReq
  | mk w st i none _ => w.sizeReq (envAt env i) st
  | mk _ _ _ (some l) cs => l.sizeReq (itemList env cs)
  | deferred .. => ({}, {})

def itemList (env : Env) : List (Node Msg) → List Item
  | [] => []
  | c :: cs =>
    let (w, h) := sizeReq env c
    { w, h, visible := c.visible } :: itemList env cs
end

/-- Children as their layout sees them, from the size requests `measure` kept. -/
def keptItems (cs : List (Node Msg)) : List Item :=
  cs.map fun c => { w := c.info.req.1, h := c.info.req.2, visible := c.visible }

mutual
/-- The node with every node's size request worked out and kept, bottom up, once each. -/
def measure (env : Env) : Node Msg → Node Msg
  | n@(mk w st i none cs) =>
    if i.measured then n else mk w st { i with req := w.sizeReq (envAt env i) st, measured := true } none cs
  | n@(mk w st i (some l) cs) =>
    if i.measured then n
    else
      let cs := measureList env cs
      mk w st { i with req := l.sizeReq (keptItems cs), measured := true } (some l) cs
  | n@(deferred ..) => n

def measureList (env : Env) : List (Node Msg) → List (Node Msg)
  | [] => []
  | c :: cs => measure env c :: measureList env cs
end

mutual
/-- A measured node placed in `v`, and its children where its layout puts them. -/
def place (env : Env) : Node Msg → Rect → Node Msg
  | mk w st i none cs, v => mk w st { i with viewport := v, content := v } none cs
  | mk w st i (some l) cs, v =>
    let items := keptItems cs
    let content := w.content (envAt env i) st v i.req
    mk w st { i with viewport := v, content } (some l) (placeList env cs (l.assign content items))
  | deferred i a s b, v => deferred { i with viewport := v, content := v } a s b

def placeList (env : Env) : List (Node Msg) → List Rect → List (Node Msg)
  | c :: cs, r :: rs => place env c r :: placeList env cs rs
  | cs, [] => cs
  | [], _ => []
end

/-- The node placed in `v`, and its children where its layout puts them. -/
def resize (env : Env) (n : Node Msg) (v : Rect) : Node Msg := place env (measure env n) v

mutual
/-- What the node and its descendants draw, within its box, leaving out descendants wholly outside
`seen`, the part of the window its ancestors leave visible, which their clips would remove. -/
def renderIn (env : Env) (seen : Rect) : Node Msg → Scene
  | mk w st i _ cs =>
    if i.visible then
      w.render (envAt env i) st i.viewport ++ (renderList env (i.viewport.inter seen) cs).clip i.viewport
    else Scene.empty
  | deferred .. => Scene.empty

def renderList (env : Env) (seen : Rect) : List (Node Msg) → Scene
  | [] => Scene.empty
  | c :: cs =>
    if (c.viewport.inter seen).isEmpty then renderList env seen cs
    else renderIn env seen c ++ renderList env seen cs
end

/-- What the node and its descendants draw, within its box. -/
def render (env : Env) (n : Node Msg) : Scene := renderIn env n.viewport n

theorem renderIn_within (env : Env) (seen : Rect) (n : Node Msg) :
    (n.renderIn env seen).Within n.viewport := by
  match n with
  | mk w st i l cs =>
    simp only [renderIn, viewport, info]
    split
    · exact Scene.append_within (w.render_within _ st i.viewport) (Scene.clip_within _ _)
    · exact Scene.empty_within _
  | deferred .. => exact Scene.empty_within _

theorem render_within (env : Env) (n : Node Msg) : (n.render env).Within n.viewport :=
  renderIn_within env n.viewport n

mutual
def find? (id : WidgetId) : Node Msg → Option (Node Msg)
  | n@(mk _ _ i _ cs) => if i.id == id then some n else findList? id cs
  | n@(deferred i ..) => if i.id == id then some n else none

def findList? (id : WidgetId) : List (Node Msg) → Option (Node Msg)
  | [] => none
  | c :: cs => (find? id c).orElse fun _ => findList? id cs
end

mutual
/-- The first node, in preorder, with `key`. -/
def findKey? (key : String) : Node Msg → Option (Node Msg)
  | n@(mk _ _ i _ cs) => if i.key == some key then some n else findKeyList? key cs
  | n@(deferred i ..) => if i.key == some key then some n else none

def findKeyList? (key : String) : List (Node Msg) → Option (Node Msg)
  | [] => none
  | c :: cs => (findKey? key c).orElse fun _ => findKeyList? key cs
end

mutual
/-- Every node's id and its path from the root, as child indices, in preorder. -/
def pathsFrom (path : List Nat) : Node Msg → List (WidgetId × List Nat)
  | mk _ _ i _ cs => (i.id, path) :: pathsList path 0 cs
  | deferred i .. => [(i.id, path)]

def pathsList (path : List Nat) (idx : Nat) : List (Node Msg) → List (WidgetId × List Nat)
  | [] => []
  | c :: cs => pathsFrom (path ++ [idx]) c ++ pathsList path (idx + 1) cs
end

def paths (n : Node Msg) : List (WidgetId × List Nat) := pathsFrom [] n

mutual
/-- The node with `id` handles `e`: the tree with its new state, and its requests, or `none` if
it did not handle it. -/
def handleAt (env : Env) (id : WidgetId) (e : Event) : Node Msg → Node Msg × Option (List (Req Msg))
  | mk w st i l cs =>
    if i.id == id then
      match w.handle (envAt env i) st i.viewport e with
      | some (st', reqs) => (mk w st' { i with measured := false } l cs, some reqs)
      | none => (mk w st i l cs, none)
    else
      let (cs', reqs) := handleList env id e cs
      (mk w st { i with measured := reqs.isNone && i.measured } l cs', reqs)
  | n@(deferred ..) => (n, none)

def handleList (env : Env) (id : WidgetId) (e : Event) :
    List (Node Msg) → List (Node Msg) × Option (List (Req Msg))
  | [] => ([], none)
  | c :: cs =>
    let (c', r1) := handleAt env id e c
    let (cs', r2) := handleList env id e cs
    (c' :: cs', r1.orElse fun _ => r2)
end

/-- `e` to the node at `path`, and if it does not handle it, to its ancestors in turn, nearest
first: the tree with the new state, and the requests of the node that handled it; or `none`, with
the tree untouched, if none did. One walk down the path. -/
def bubbleAt (env : Env) (e : Event) : List Nat → Node Msg → Option (Node Msg × List (Req Msg))
  | path, mk w st i l cs =>
    let own (cs : List (Node Msg)) : Option (Node Msg × List (Req Msg)) :=
      (w.handle (envAt env i) st i.viewport e).map fun (st', reqs) =>
        (mk w st' { i with measured := false } l cs, reqs)
    match path with
    | [] => own cs
    | k :: rest =>
      match cs[k]? with
      | some c =>
        match bubbleAt env e rest c with
        | some (c', reqs) => some (mk w st { i with measured := false } l (cs.set k c'), reqs)
        | none => own cs
      | none => none
  | _, deferred .. => none

/-- The ids of the node with `id` and its ancestors, nearest first. -/
def lineage (n : Node Msg) (id : WidgetId) : List WidgetId :=
  let ps := n.paths
  match ps.lookup id with
  | some path => ((List.range (path.length + 1)).reverse.filterMap fun k =>
      ps.find? (·.2 == path.take k) |>.map (·.1))
  | none => []

/-- `e` to the node with `id`, and if it does not handle it, to its ancestors in turn: the tree,
and the requests of the node that handled it, or `none` if none did. -/
def bubble (env : Env) (id : WidgetId) (e : Event) (n : Node Msg) :
    Node Msg × Option (List (Req Msg)) :=
  go (n.lineage id) n
where
  go : List WidgetId → Node Msg → Node Msg × Option (List (Req Msg))
    | [], n => (n, none)
    | a :: as, n =>
      match n.handleAt env a e with
      | (n', some reqs) => (n', some reqs)
      | (n', none) => go as n'

/-- The tree with its messages mapped by `f`; a deferred subtree is mapped when built. -/
partial def mapMsg {β : Type} (f : Msg → β) : Node Msg → Node β
  | mk w st i l cs => mk (w.mapMsg f) st i l (cs.map (mapMsg f))
  | deferred i a s b => deferred i a s fun u => mapMsg f (b u)

mutual
/-- The topmost visible node at `p`: the deepest, and of overlapping siblings the later. -/
def hit? (p : Point) : Node Msg → Option (Node Msg)
  | n@(mk _ _ i _ cs) =>
    if i.visible && i.viewport.contains p then (hitList? p cs).orElse fun _ => some n else none
  | deferred .. => none

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
  | deferred .., m, h => by simp [hit?] at h

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
  | deferred .. => []

def focusablesList : List (Node Msg) → List WidgetId
  | [] => []
  | c :: cs => focusables c ++ focusablesList cs
end

mutual
/-- Every visible node with a key, and its box. -/
def keyedPlacements : Node Msg → List (String × Rect)
  | mk _ _ i _ cs =>
    if i.visible then (i.key.toList.map (·, i.viewport)) ++ keyedPlacementsList cs else []
  | deferred .. => []

def keyedPlacementsList : List (Node Msg) → List (String × Rect)
  | [] => []
  | c :: cs => keyedPlacements c ++ keyedPlacementsList cs
end

mutual
/-- Every visible node's id, box and path from the root, added to `acc` in preorder. -/
def indexInto (clip : Rect) (path : Array Nat) (acc : Array (WidgetId × Rect × List Nat)) :
    Node Msg → Array (WidgetId × Rect × List Nat)
  | mk _ _ i _ cs =>
    let seen := i.viewport.inter clip
    if i.visible && !seen.isEmpty then indexList seen path 0 (acc.push (i.id, i.viewport, path.toList)) cs
    else acc
  | deferred .. => acc

def indexList (clip : Rect) (path : Array Nat) (idx : Nat) (acc : Array (WidgetId × Rect × List Nat)) :
    List (Node Msg) → Array (WidgetId × Rect × List Nat)
  | [] => acc
  | c :: cs => indexList clip path (idx + 1) (indexInto clip (path.push idx) acc c) cs
end

/-- Every node that can be seen, its id, box and path from the root, in preorder: visible, and
not wholly clipped away by the boxes around it, such as a scroll's. -/
def index (n : Node Msg) : Array (WidgetId × Rect × List Nat) := indexInto n.viewport #[] #[] n

mutual
/-- Every visible node's id and box. -/
def placements : Node Msg → List (WidgetId × Rect)
  | mk _ _ i _ cs => if i.visible then (i.id, i.viewport) :: placementsList cs else []
  | deferred .. => []

def placementsList : List (Node Msg) → List (WidgetId × Rect)
  | [] => []
  | c :: cs => placements c ++ placementsList cs
end

mutual
/-- The accessibility nodes at and under `n`, added to `acc`, and the ids of the topmost of them:
widgets that describe themselves, with containers that do not left out. -/
def accessFrom (env : Env) : Node Msg → Array AccessNode → Array AccessNode × List Nat
  | n@(mk w st i _ cs), acc =>
    if !i.visible then (acc, [])
    else match w.access (envAt env i) st with
      | some a =>
        let (acc, kids) := accessList env cs acc
        (acc.push { id := i.id.n, access := a, bounds := i.viewport, focusable := n.focusable,
                    disabled := !i.enabled, children := kids }, [i.id.n])
      | none => accessList env cs acc
  | deferred .., acc => (acc, [])

def accessList (env : Env) : List (Node Msg) → Array AccessNode → Array AccessNode × List Nat
  | [], acc => (acc, [])
  | c :: cs, acc =>
    let (acc, k1) := accessFrom env c acc
    let (acc, k2) := accessList env cs acc
    (acc, k1 ++ k2)
end

/-- The tree as assistive technology sees it: a window, id 0, over the widgets that describe
themselves. -/
def accessTree (env : Env) (n : Node Msg) : List AccessNode :=
  let (nodes, top) := accessFrom env n #[]
  { id := 0, access := { role := .window }, bounds := n.viewport, focusable := false,
    disabled := false, children := top } :: nodes.toList

end Node

end Paw
