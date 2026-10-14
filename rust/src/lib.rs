// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The platform layer of Paw: windows, input, text and drawing, as functions with Lean's calling
//! convention. `Paw/Ffi.lean` declares them. Data crosses as byte arrays that Lean encodes and
//! decodes.

#![allow(clippy::missing_safety_doc)]

/// The version of the byte formats shared with Lean, which `Paw.Ffi.abiVersion` must match.
pub const ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn paw_abi_version(_unit: *mut lean_sys::lean_object) -> u32 {
    ABI_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version() {
        assert_eq!(paw_abi_version(std::ptr::null_mut()), ABI_VERSION);
    }
}
