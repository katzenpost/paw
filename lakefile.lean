import Lake
open Lake DSL System

package paw where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

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
