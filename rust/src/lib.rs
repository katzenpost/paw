// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The platform layer of Paw: windows, input, text and drawing, as functions with Lean's calling
//! convention. `Paw/Ffi.lean` declares them. Data crosses as byte arrays that Lean encodes and
//! decodes.

#![allow(clippy::missing_safety_doc)]

pub mod codec;
pub mod access;
pub mod events;
pub mod render;
pub mod scene;
pub mod text;
pub mod window;

use codec::{Reader, Writer};
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

unsafe fn string_of(s: b_lean_obj_arg) -> String {
    let p = lean_string_cstr(s);
    let n = lean_string_size(s) - 1;
    String::from_utf8_lossy(std::slice::from_raw_parts(p, n)).into_owned()
}

unsafe fn io_ok(v: lean_obj_res) -> lean_obj_res {
    lean_io_result_mk_ok(v)
}

unsafe fn io_err(msg: &str) -> lean_obj_res {
    lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string_from_bytes(msg.as_ptr(), msg.len())))
}

/// Decodes a scene and encodes it again; empty if it does not decode. For tests that Lean and
/// Rust agree on the format.
#[no_mangle]
pub unsafe extern "C" fn paw_scene_echo(a: b_lean_obj_arg) -> lean_obj_res {
    let out = scene::Scene::decode(bytes_of(a)).map(|s| s.encode()).unwrap_or_default();
    byte_array(&out)
}

/// Decodes a request and encodes it again; empty if it does not decode.
#[no_mangle]
pub unsafe extern "C" fn paw_request_echo(a: b_lean_obj_arg) -> lean_obj_res {
    let out = events::Request::decode(bytes_of(a)).map(|r| r.encode()).unwrap_or_default();
    byte_array(&out)
}

/// One of each kind of window event, encoded.
#[no_mangle]
pub unsafe extern "C" fn paw_sample_events(_unit: *mut lean_object) -> lean_obj_res {
    byte_array(&events::encode_events(&events::sample()))
}

/// The width and height of a line of text, in units: given the size in units, whether bold, and
/// the text.
#[no_mangle]
pub unsafe extern "C" fn paw_measure(a: b_lean_obj_arg) -> lean_obj_res {
    let mut r = Reader::new(bytes_of(a));
    let (Some(size), Some(bold), Some(s)) = (r.int(), r.bool(), r.string()) else {
        return byte_array(&[]);
    };
    let (w, h) = text::with_text(|t| t.measure(&s, size as f32 / render::UNITS, bold));
    let mut out = Writer::default();
    out.int((w * render::UNITS).ceil() as i64);
    out.int((h * render::UNITS).ceil() as i64);
    byte_array(&out.bytes)
}

/// A scene drawn offscreen at `scale_milli`/1000 physical pixels per logical pixel, as PNG;
/// empty if it does not decode.
#[no_mangle]
pub unsafe extern "C" fn paw_render_png(a: b_lean_obj_arg, w: u32, h: u32, scale_milli: u32) -> lean_obj_res {
    let Some(s) = scene::Scene::decode(bytes_of(a)) else { return byte_array(&[]) };
    let png = text::with_text(|t| render::render(&s, w, h, scale_milli as f32 / 1000.0, t))
        .encode_png()
        .unwrap_or_default();
    byte_array(&png)
}

/// The pixels that differ between two PNGs, then an image of them; empty if they cannot be
/// compared.
#[no_mangle]
pub unsafe extern "C" fn paw_png_diff(a: b_lean_obj_arg, b: b_lean_obj_arg) -> lean_obj_res {
    match render::diff_png(bytes_of(a), bytes_of(b)) {
        Some((n, png)) => {
            let mut w = Writer::default();
            w.nat(n);
            w.bytes.extend_from_slice(&png);
            byte_array(&w.bytes)
        }
        None => byte_array(&[]),
    }
}

/// The pixels outside a rectangle that differ between two PNGs.
#[no_mangle]
pub unsafe extern "C" fn paw_png_diff_outside(
    a: b_lean_obj_arg,
    b: b_lean_obj_arg,
    x0: u32,
    y0: u32,
    x1: u32,
    y1: u32,
) -> u64 {
    render::diff_outside(bytes_of(a), bytes_of(b), x0, y0, x1, y1)
}

#[no_mangle]
pub unsafe extern "C" fn paw_window_open(title: b_lean_obj_arg, w: u32, h: u32) -> lean_obj_res {
    match window::open(&string_of(title), w, h) {
        Ok(()) => io_ok(lean_box(0)),
        Err(e) => io_err(&e),
    }
}

#[no_mangle]
pub unsafe extern "C" fn paw_window_poll(timeout_ms: u32) -> lean_obj_res {
    io_ok(byte_array(&events::encode_events(&window::poll(timeout_ms))))
}

#[no_mangle]
pub unsafe extern "C" fn paw_window_present(a: b_lean_obj_arg) -> lean_obj_res {
    match scene::Scene::decode(bytes_of(a)) {
        Some(s) => {
            window::present(s);
            io_ok(lean_box(0))
        }
        None => io_err("paw: a scene that does not decode"),
    }
}

#[no_mangle]
pub unsafe extern "C" fn paw_window_request(a: b_lean_obj_arg) -> lean_obj_res {
    match events::Request::decode(bytes_of(a)) {
        Some(r) => {
            window::request(r);
            io_ok(lean_box(0))
        }
        None => io_err("paw: a request that does not decode"),
    }
}

#[no_mangle]
pub unsafe extern "C" fn paw_window_size() -> lean_obj_res {
    let (w, h) = window::size();
    let mut out = Writer::default();
    out.int(w);
    out.int(h);
    io_ok(byte_array(&out.bytes))
}

#[no_mangle]
pub unsafe extern "C" fn paw_window_screenshot() -> lean_obj_res {
    io_ok(byte_array(&window::screenshot()))
}

#[no_mangle]
pub unsafe extern "C" fn paw_now() -> lean_obj_res {
    io_ok(lean_uint64_to_nat(window::now()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version() {
        assert_eq!(paw_abi_version(std::ptr::null_mut()), ABI_VERSION);
    }
}
