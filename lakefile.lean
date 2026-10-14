import Lake
open Lake DSL System

package paw where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩,
    ⟨`warningAsError, true⟩]

require LeanBench from git
  "https://github.com/alok/LeanBench" @ "250d2a892bf8c91ec3ae5de8517793e18379f97b"

@[default_target]
lean_lib Paw

lean_lib Gallery where
  srcDir := "examples"

lean_exe «paw-gallery» where
  root := `GalleryMain
  srcDir := "examples"

lean_exe «paw-test» where
  root := `Paw.Tests.Main

/-- Draws scenes offscreen and compares them with the approved images. -/
lean_exe «paw-goldens» where
  root := `Paw.Tests.Goldens

/-- Benchmarks of each layer, with LeanBench. -/
lean_exe «paw-bench» where
  root := `Paw.Bench.Main

/-- Lists public definitions that no test reaches. -/
lean_exe «paw-coverage» where
  root := `Paw.Tests.Coverage
  supportInterpreter := true

/-- The Rust crate in `rust/`, built by cargo. -/
extern_lib paw_ffi pkg := Job.async do
  proc { cmd := "cargo", args := #["build", "--release", "--quiet"], cwd := pkg.dir / "rust" }
  let lib := pkg.dir / "rust" / "target" / "release" / nameToStaticLib "paw_ffi"
  setTrace (← computeTrace lib)
  return lib
