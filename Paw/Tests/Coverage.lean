/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Lean

/-! # Declaration coverage and axioms

Lists the definitions in `Paw` that no test reaches: a definition is covered when a declaration in
`Paw.Tests` uses it, directly or through other definitions. Names in `tests/coverage-allow.txt`
are not listed. It also lists any declaration in `Paw` that depends on an axiom beyond the three
standard ones, such as `sorryAx`. -/

open Lean

namespace Paw.Tests.Coverage

def inTests (m : Name) : Bool := (`Paw.Tests).isPrefixOf m

def inLibrary (m : Name) : Bool := (`Paw).isPrefixOf m && !inTests m

def moduleOf (env : Environment) (n : Name) : Option Name :=
  env.getModuleIdxFor? n |>.bind fun i => env.header.moduleNames[i.toNat]?

/-- Classes whose instances are usually derived. -/
def derivedClasses : List Name := [``Repr, ``Inhabited, ``DecidableEq, ``Nonempty, ``Hashable]

/-- An instance of a class in `derivedClasses`, or a definition made for one. -/
def routineInstance (env : Environment) (n : Name) : Bool :=
  let isRoutine (m : Name) := match env.find? m with
    | some ci => ci.type.getForallBody.getAppFn.constName?.any derivedClasses.contains
    | none => false
  isRoutine n || isRoutine n.getPrefix

/-- Written by hand, not generated for a structure, an inductive, a match, a proof or a derived
instance. -/
def handWritten (env : Environment) (n : Name) : Bool :=
  let user := (privateToUserName? n).getD n
  let generated := user.components.any fun c =>
    let c := c.toString
    c.startsWith "match_" || c.startsWith "proof_" || c == "splitter"
  !generated && !user.isInternalDetail && !user.hasMacroScopes && !isAuxRecursor env n && !isNoConfusion env n
    && !(env.isProjectionFn n) && !routineInstance env n
    && !["ctorIdx", "noConfusionType", "ctorElimType", "toCtorIdx", "ofNat"].contains n.getString!
    && !(Meta.Match.Extension.getMatcherInfo? env n).isSome

def candidates (env : Environment) : Array Name :=
  env.constants.fold (init := #[]) fun acc n ci =>
    match ci with
    | .defnInfo _ | .opaqueInfo _ =>
      if (moduleOf env n).any inLibrary && handWritten env n then acc.push n else acc
    | _ => acc

/-- Every constant used by a test declaration, transitively. -/
def reached (env : Environment) : NameSet := Id.run do
  let mut todo : Array Name := env.constants.fold (init := #[]) fun acc n _ =>
    if (moduleOf env n).any inTests then acc.push n else acc
  let mut seen : NameSet := {}
  while h : todo.size > 0 do
    let n := todo[todo.size - 1]
    todo := todo.pop
    if seen.contains n then continue
    seen := seen.insert n
    if let some ci := env.find? n then
      for m in ci.getUsedConstantsAsSet do
        if !seen.contains m then todo := todo.push m
  return seen

def allowed : IO (List Name) := do
  let path : System.FilePath := "tests/coverage-allow.txt"
  if !(← path.pathExists) then return []
  let lines := (← IO.FS.readFile path).splitOn "\n" |>.map (·.trimAscii.toString)
  return lines.filter (fun l => !l.isEmpty && !l.startsWith "#") |>.map String.toName

/-- The axioms a proof in `Paw` may use. -/
def standardAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

/-- Declarations in `Paw` whose proofs use any other axiom, such as `sorryAx`, with it. -/
def offAxioms (env : Environment) : IO (Array (Name × Name)) := do
  let names := env.constants.fold (init := #[]) fun acc n _ =>
    if (moduleOf env n).any inLibrary then acc.push n else acc
  let ctx : Core.Context := { fileName := "<coverage>", fileMap := default }
  let (bad, _) ← (names.foldlM (init := #[]) fun acc n => do
      let axs ← collectAxioms n
      return acc ++ (axs.filter (!standardAxioms.contains ·)).map (n, ·)
    : CoreM _).toIO ctx { env }
  return bad

end Paw.Tests.Coverage

open Paw.Tests.Coverage in
def main : IO UInt32 := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Paw }, { module := `Paw.Tests.Main }] {}
  let seen := reached env
  let allow ← allowed
  let missed := (candidates env).filter (fun n => !seen.contains n && !allow.contains n)
    |>.qsort (·.toString < ·.toString)
  let total := (candidates env).size
  IO.println s!"coverage: {total - missed.size} of {total} definitions reached by tests"
  for n in missed do IO.println s!"  not reached: {n}"
  let bad ← offAxioms env
  IO.println s!"axioms: {bad.size} declarations use an axiom beyond {standardAxioms}"
  for (n, a) in bad do IO.println s!"  {n} uses {a}"
  return if missed.isEmpty && bad.isEmpty then 0 else 1
