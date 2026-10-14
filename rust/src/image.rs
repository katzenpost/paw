// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Images: decoded from PNG or JPEG under limits, and kept for drawing by id.
//!
//! An image's pixels stay here, in a registry keyed by an id from a counter, so that no content
//! can choose another image's id. Lean holds each image as an external object whose finalizer
//! takes it out of the registry, so an image is kept exactly as long as Lean refers to it.

use std::collections::HashMap;
use std::io::Cursor;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use tiny_skia::Pixmap;

/// The widest and tallest image decoded.
pub const MAX_SIDE: u32 = 8192;
/// The most bytes of RGBA an image may take.
pub const MAX_BYTES: u64 = 64 << 20;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageError {
    /// Not a PNG or a JPEG.
    Format = 1,
    /// Larger than the limits, whatever the file's size.
    TooLarge = 2,
    /// A PNG or JPEG that does not decode.
    Corrupt = 3,
}

fn registry() -> &'static Mutex<HashMap<u64, Arc<Pixmap>>> {
    static R: OnceLock<Mutex<HashMap<u64, Arc<Pixmap>>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

static NEXT: AtomicU64 = AtomicU64::new(1);

/// Whether a `w` × `h` image is within the limits.
pub fn within_limits(w: u32, h: u32) -> bool {
    w > 0 && h > 0 && w <= MAX_SIDE && h <= MAX_SIDE && (w as u64) * (h as u64) * 4 <= MAX_BYTES
}

/// The width, height and straight RGBA pixels of a PNG or JPEG. Its size is read from the header
/// and checked against the limits before anything is allocated for its pixels.
pub fn decode(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), ImageError> {
    let reader = || image::ImageReader::new(Cursor::new(bytes)).with_guessed_format().map_err(|_| ImageError::Format);
    let r = reader()?;
    if !matches!(r.format(), Some(image::ImageFormat::Png | image::ImageFormat::Jpeg)) {
        return Err(ImageError::Format);
    }
    let (w, h) = r.into_dimensions().map_err(|_| ImageError::Corrupt)?;
    if !within_limits(w, h) {
        return Err(ImageError::TooLarge);
    }
    let mut r = reader()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(MAX_SIDE);
    limits.max_image_height = Some(MAX_SIDE);
    limits.max_alloc = Some(MAX_BYTES);
    r.limits(limits);
    let img = r.decode().map_err(|e| match e {
        image::ImageError::Limits(_) => ImageError::TooLarge,
        image::ImageError::Unsupported(_) => ImageError::Format,
        _ => ImageError::Corrupt,
    })?;
    let rgba = img.into_rgba8();
    Ok((w, h, rgba.into_raw()))
}

/// Keeps straight RGBA pixels for drawing, under a new id.
pub fn register(w: u32, h: u32, rgba: &[u8]) -> Result<u64, ImageError> {
    if !within_limits(w, h) {
        return Err(ImageError::TooLarge);
    }
    if rgba.len() as u64 != w as u64 * h as u64 * 4 {
        return Err(ImageError::Corrupt);
    }
    let mut pm = Pixmap::new(w, h).ok_or(ImageError::TooLarge)?;
    for (dst, [r, g, b, a]) in pm.pixels_mut().iter_mut().zip(rgba.as_chunks::<4>().0) {
        *dst = tiny_skia::ColorU8::from_rgba(*r, *g, *b, *a).premultiply();
    }
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    registry().lock().unwrap().insert(id, Arc::new(pm));
    Ok(id)
}

/// The pixels with `id`, if they are still kept.
pub fn get(id: u64) -> Option<Arc<Pixmap>> {
    registry().lock().unwrap().get(&id).cloned()
}

/// Stops keeping the image with `id`.
pub fn release(id: u64) {
    registry().lock().unwrap().remove(&id);
}

/// How many images are kept.
pub fn count() -> usize {
    registry().lock().unwrap().len()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(w: u32, h: u32) -> Vec<u8> {
        let mut out = Vec::new();
        let img = image::RgbaImage::from_pixel(w, h, image::Rgba([10, 20, 30, 255]));
        img.write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png).unwrap();
        out
    }

    #[test]
    fn decodes_and_refuses() {
        let (w, h, px) = decode(&png(3, 2)).unwrap();
        assert_eq!((w, h, px.len()), (3, 2, 24));
        assert_eq!(&px[..4], &[10, 20, 30, 255]);
        assert_eq!(decode(b"not an image"), Err(ImageError::Format));
        let p = png(3, 2);
        assert_eq!(decode(&p[..p.len() - 20]), Err(ImageError::Corrupt));
        assert!(!within_limits(8193, 1));
        assert!(!within_limits(5000, 5000), "100 MB of RGBA");
        assert!(within_limits(4096, 4096));
    }

    #[test]
    fn registers_and_releases() {
        let a = register(1, 1, &[1, 2, 3, 4]).unwrap();
        let b = register(1, 1, &[1, 2, 3, 4]).unwrap();
        assert_ne!(a, b, "the same pixels twice are two images");
        assert!(get(a).is_some());
        release(a);
        assert!(get(a).is_none());
        assert!(get(b).is_some());
        assert_eq!(register(2, 2, &[0; 3]), Err(ImageError::Corrupt));
        release(b);
    }
}
