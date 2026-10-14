// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The platform layer of Paw: windows, input, text and drawing, as functions with Lean's calling
//! convention. `Paw/Ffi.lean` declares them. Data crosses as byte arrays that Lean encodes and
//! decodes.

#![allow(clippy::missing_safety_doc)]

pub mod codec;
pub mod scene;

use lean_sys::*;

/// The version of the byte formats shared with Lean, which `Paw.Ffi.abiVersion` must match.
pub const ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn paw_abi_version(_unit: *mut lean_object) -> u32 {
    ABI_VERSION
}

/// The bytes of a borrowed Lean `ByteArray`.
pub unsafe fn bytes_of<'a>(a: b_lean_obj_arg) -> &'a [u8] {
    std::slice::from_raw_parts(lean_sarray_cptr(a as *mut _), lean_sarray_size(a))
}

/// A new Lean `ByteArray` holding `bytes`.
pub unsafe fn byte_array(bytes: &[u8]) -> lean_obj_res {
    let a = lean_alloc_sarray(1, bytes.len(), bytes.len());
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), lean_sarray_cptr(a), bytes.len());
    a
}

/// Decodes a scene and encodes it again; empty if it does not decode. For tests that Lean and
/// Rust agree on the format.
#[no_mangle]
pub unsafe extern "C" fn paw_scene_echo(a: b_lean_obj_arg) -> lean_obj_res {
    let out = scene::Scene::decode(bytes_of(a)).map(|s| s.encode()).unwrap_or_default();
    byte_array(&out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version() {
        assert_eq!(paw_abi_version(std::ptr::null_mut()), ABI_VERSION);
    }
}
