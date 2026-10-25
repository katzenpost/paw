// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The platform layer of Paw: windows, input, text and drawing, as functions with Lean's calling
//! convention. `Paw/Ffi.lean` declares them. Data crosses as byte arrays that Lean encodes and
//! decodes.

#![allow(clippy::missing_safety_doc)]

pub mod access;
#[cfg(target_os = "android")]
pub mod android;
pub mod codec;
pub mod events;
pub mod image;
pub mod render;
pub mod scene;
pub mod text;
pub mod textinput;
pub mod touch;
pub mod window;

use codec::{Reader, Writer};
use lean_sys::*;

/// The version of the byte formats shared with Lean, which `Paw.Ffi.abiVersion` must match.
pub const ABI_VERSION: u32 = 2;

#[no_mangle]
pub extern "C" fn paw_abi_version(_unit: *mut lean_object) -> u32 {
    ABI_VERSION
}

/// Whether this is Android.
#[no_mangle]
pub extern "C" fn paw_is_android(_unit: *mut lean_object) -> u8 {
    cfg!(target_os = "android") as u8
}

/// Whether the app holds an Android permission, asking the user for it when it does not; off
/// Android, always.
#[no_mangle]
pub unsafe extern "C" fn paw_permission(
    name: b_lean_obj_arg,
    _world: lean_obj_arg,
) -> lean_obj_res {
    #[cfg(target_os = "android")]
    let held = android::permission(&string_of(name));
    #[cfg(not(target_os = "android"))]
    let held = {
        let _ = name;
        true
    };
    io_ok(lean_box(held as usize))
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
    lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string_from_bytes(
        msg.as_ptr(),
        msg.len(),
    )))
}

/// Decodes a scene and encodes it again; empty if it does not decode. For tests that Lean and
/// Rust agree on the format.
#[no_mangle]
pub unsafe extern "C" fn paw_scene_echo(a: b_lean_obj_arg) -> lean_obj_res {
    let out = scene::Scene::decode(bytes_of(a))
        .map(|s| s.encode())
        .unwrap_or_default();
    byte_array(&out)
}

/// Decodes a request and encodes it again; empty if it does not decode.
#[no_mangle]
pub unsafe extern "C" fn paw_request_echo(a: b_lean_obj_arg) -> lean_obj_res {
    let out = events::Request::decode(bytes_of(a))
        .map(|r| r.encode())
        .unwrap_or_default();
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
pub unsafe extern "C" fn paw_render_png(
    a: b_lean_obj_arg,
    w: u32,
    h: u32,
    scale_milli: u32,
) -> lean_obj_res {
    let Some(s) = scene::Scene::decode(bytes_of(a)) else {
        return byte_array(&[]);
    };
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
    io_ok(byte_array(&events::encode_events(&window::poll(
        timeout_ms,
    ))))
}

#[no_mangle]
pub unsafe extern "C" fn paw_wake() -> lean_obj_res {
    window::wake();
    io_ok(lean_box(0))
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

/// The class of Lean's handles on images: finalizing one stops keeping its pixels.
fn image_class() -> *mut lean_external_class {
    static CLASS: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    unsafe extern "C" fn finalize(p: *mut std::ffi::c_void) {
        image::release(*Box::from_raw(p as *mut u64));
    }
    unsafe extern "C" fn foreach(_: *mut std::ffi::c_void, _: b_lean_obj_arg) {}
    *CLASS.get_or_init(|| unsafe {
        lean_register_external_class(Some(finalize), Some(foreach)) as usize
    }) as *mut lean_external_class
}

/// The outcome of making an image, as Lean reads it: a header, either the error's tag or 0 and
/// the width, height and id; and a handle that keeps the pixels while Lean holds it.
unsafe fn image_result(r: Result<(u32, u32, u64), image::ImageError>) -> lean_obj_res {
    let mut w = Writer::default();
    let id = match r {
        Ok((width, height, id)) => {
            w.nat(0);
            w.nat(width as u64);
            w.nat(height as u64);
            w.nat(id);
            id
        }
        Err(e) => {
            w.nat(e as u64);
            0
        }
    };
    let handle = lean_alloc_external(image_class(), Box::into_raw(Box::new(id)) as *mut _);
    let pair = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(pair, 0, byte_array(&w.bytes));
    lean_ctor_set(pair, 1, handle);
    io_ok(pair)
}

/// Decodes a PNG or JPEG and keeps its pixels for drawing.
#[no_mangle]
pub unsafe extern "C" fn paw_image_decode(a: b_lean_obj_arg, _world: lean_obj_arg) -> lean_obj_res {
    image_result(
        image::decode(bytes_of(a))
            .and_then(|(w, h, px)| image::register(w, h, &px).map(|id| (w, h, id))),
    )
}

/// Keeps straight RGBA pixels of a `w` × `h` image for drawing.
#[no_mangle]
pub unsafe extern "C" fn paw_image_of_rgba(
    w: u32,
    h: u32,
    a: b_lean_obj_arg,
    _world: lean_obj_arg,
) -> lean_obj_res {
    image_result(image::register(w, h, bytes_of(a)).map(|id| (w, h, id)))
}

/// How many images are kept.
#[no_mangle]
pub unsafe extern "C" fn paw_image_count(_world: lean_obj_arg) -> lean_obj_res {
    io_ok(lean_usize_to_nat(image::count()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version() {
        assert_eq!(paw_abi_version(std::ptr::null_mut()), ABI_VERSION);
    }

    #[test]
    fn wake_before_open() {
        window::wake();
    }
}
