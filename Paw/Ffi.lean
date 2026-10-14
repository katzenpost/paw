/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # The platform layer

Functions implemented in `rust/src/lib.rs`. Data crosses as byte arrays that Lean encodes and
decodes. -/

namespace Paw.Ffi

/-- The version of the byte formats this library speaks. -/
def abiVersion : UInt32 := 1

@[extern "paw_abi_version"] opaque rustAbiVersion : Unit → UInt32

/-- Whether the linked Rust layer speaks the same byte formats. -/
def abiMatches : Bool := rustAbiVersion () == abiVersion

end Paw.Ffi

