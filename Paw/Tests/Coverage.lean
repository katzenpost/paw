/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Lean

/-! # Declaration coverage

Lists the definitions in `Paw` that no test reaches: a definition is covered when a declaration in
`Paw.Tests` uses it, directly or through other definitions. Names in `tests/coverage-allow.txt`
are not listed. -/

open Lean

namespace Paw.Tests.Coverage

def inTests (m : Name) : Bool := (`Paw.Tests).isPrefixOf m

def inLibrary (m : Name) : Bool := (`Paw).isPrefixOf m && !inTests m

def moduleOf (env : Environment) (n : Name) : Option Name :=
  env.getModuleIdxFor? n |>.bind fun i => env.header.moduleNames[i.toNat]?

/-- Written by hand, not generated for a structure, an inductive, a match or a proof. -/
def handWritten (env : Environment) (n : Name) : Bool :=
  let user := (privateToUserName? n).getD n
  !user.isInternalDetail && !user.hasMacroScopes && !isAuxRecursor env n && !isNoConfusion env n
    && !(env.isProjectionFn n) && !Meta.isInstanceCore env n
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
  return if missed.isEmpty then 0 else 1
