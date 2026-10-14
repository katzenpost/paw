// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Text shaping, measuring and drawing with cosmic-text. Measuring and drawing use one font
//! system, so a line is drawn as wide as it was measured. Only the bundled DejaVu fonts are
//! loaded until a window opens, so offscreen renders are the same on every machine.

use cosmic_text::{Attrs, Buffer, Family, FontSystem, Metrics, Shaping, SwashCache, Weight};
use std::sync::{Arc, Mutex};

const REGULAR: &[u8] = include_bytes!("../fonts/DejaVuSans.ttf");
const BOLD: &[u8] = include_bytes!("../fonts/DejaVuSans-Bold.ttf");

/// Line height as a multiple of the font size.
pub const LINE_HEIGHT: f32 = 1.25;

pub struct Text {
    fs: FontSystem,
    cache: SwashCache,
}

impl Text {
    /// Only the bundled fonts, with a fixed locale, so that what is drawn is the same on every
    /// machine. (`FontSystem::new_with_fonts` would also load the system's fonts.)
    pub fn bundled() -> Text {
        let mut db = cosmic_text::fontdb::Database::new();
        for b in [REGULAR, BOLD] {
            db.load_font_source(cosmic_text::fontdb::Source::Binary(Arc::new(b.to_vec())));
        }
        db.set_sans_serif_family("DejaVu Sans");
        let fs = FontSystem::new_with_locale_and_db("en-US".to_string(), db);
        Text { fs, cache: SwashCache::new() }
    }

    /// Adds the system's fonts, for characters the bundled fonts lack.
    pub fn load_system_fonts(&mut self) {
        self.fs.db_mut().load_system_fonts();
    }

    fn buffer(&mut self, s: &str, size: f32, bold: bool) -> Buffer {
        let size = size.max(1.0);
        let mut b = Buffer::new(&mut self.fs, Metrics::new(size, size * LINE_HEIGHT));
        b.set_size(&mut self.fs, None, None);
        let weight = if bold { Weight::BOLD } else { Weight::NORMAL };
        let attrs = Attrs::new().family(Family::SansSerif).weight(weight);
        b.set_text(&mut self.fs, s, &attrs, Shaping::Advanced);
        b.shape_until_scroll(&mut self.fs, false);
        b
    }

    /// The width and height of one line, in pixels.
    pub fn measure(&mut self, s: &str, size: f32, bold: bool) -> (f32, f32) {
        let b = self.buffer(s, size, bold);
        let w = b.layout_runs().fold(0.0f32, |w, run| w.max(run.line_w));
        (w, size.max(1.0) * LINE_HEIGHT)
    }

    /// Calls `f(x, y, alpha)` for each pixel of the line drawn with its top left at `(x, y)`.
    pub fn draw<F: FnMut(i32, i32, u8)>(&mut self, s: &str, size: f32, bold: bool, x: f32, y: f32, mut f: F) {
        let b = self.buffer(s, size, bold);
        let (ox, oy) = (x.round() as i32, y.round() as i32);
        b.draw(&mut self.fs, &mut self.cache, cosmic_text::Color::rgba(0, 0, 0, 255), |px, py, w, h, c| {
            for dy in 0..h as i32 {
                for dx in 0..w as i32 {
                    f(ox + px + dx, oy + py + dy, c.a());
                }
            }
        });
    }
}

/// The text system every measurement and drawing uses.
pub static TEXT: Mutex<Option<Text>> = Mutex::new(None);

pub fn with_text<R>(f: impl FnOnce(&mut Text) -> R) -> R {
    let mut t = TEXT.lock().unwrap_or_else(|e| e.into_inner());
    f(t.get_or_insert_with(Text::bundled))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn measures() {
        let mut t = Text::bundled();
        let (w0, h) = t.measure("", 14.0, false);
        assert_eq!(w0, 0.0);
        assert!((h - 17.5).abs() < 0.01);
        let (w1, _) = t.measure("a", 14.0, false);
        let (w2, _) = t.measure("aa", 14.0, false);
        assert!(w1 > 0.0 && w2 > w1);
        let (wb, _) = t.measure("aa", 14.0, true);
        assert!(wb >= w2);
        let (w28, h28) = t.measure("aa", 28.0, false);
        assert!(w28 > w2 && h28 > h);
    }

    #[test]
    fn only_the_bundled_fonts() {
        let t = Text::bundled();
        assert_eq!(t.fs.db().len(), 2, "the system's fonts must not be loaded");
    }

    #[test]
    fn draws_within_its_line() {
        let mut t = Text::bundled();
        let (w, h) = t.measure("Hello", 20.0, false);
        let mut n = 0;
        t.draw("Hello", 20.0, false, 10.0, 5.0, |x, y, a| {
            if a > 0 {
                n += 1;
                assert!(x >= 9 && (x as f32) <= 10.0 + w + 1.0, "x {x}");
                assert!(y >= 4 && (y as f32) <= 5.0 + h + 1.0, "y {y}");
            }
        });
        assert!(n > 50);
    }
}
