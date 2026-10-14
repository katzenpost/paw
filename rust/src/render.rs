// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Draws a scene into a pixmap with tiny-skia. Every item is drawn clipped to its rectangle,
//! which is what Lean's laws about scenes rely on.

use crate::scene::{Color, Draw, Rect, Scene};
use crate::text::Text;
use tiny_skia::{
    FillRule, FilterQuality, IntRect, LineCap, LineJoin, Mask, Paint, Path, PathBuilder, Pattern,
    Pixmap, PremultipliedColorU8, SpreadMode, Stroke, Transform,
};

/// Units per logical pixel, as in `Paw.unitsPerPx`.
pub const UNITS: f32 = 64.0;

fn px(u: i64, scale: f32) -> f32 {
    u as f32 / UNITS * scale
}

/// The pixels a clip covers, if any.
fn clip_pixels(c: &Rect, scale: f32, w: u32, h: u32) -> Option<IntRect> {
    let x0 = px(c.x0, scale).round().max(0.0) as i32;
    let y0 = px(c.y0, scale).round().max(0.0) as i32;
    let x1 = (px(c.x1, scale).round() as i32).min(w as i32);
    let y1 = (px(c.y1, scale).round() as i32).min(h as i32);
    if x1 <= x0 || y1 <= y0 {
        return None;
    }
    IntRect::from_ltrb(x0, y0, x1, y1)
}

fn paint(c: &Color) -> Paint<'static> {
    let mut p = Paint::default();
    p.set_color_rgba8(c.r, c.g, c.b, c.a);
    p.anti_alias = true;
    p
}

fn rounded(l: f32, t: f32, r: f32, b: f32, radius: f32) -> Option<Path> {
    let rad = radius.min((r - l) / 2.0).min((b - t) / 2.0).max(0.0);
    let mut pb = PathBuilder::new();
    pb.move_to(l + rad, t);
    pb.line_to(r - rad, t);
    pb.quad_to(r, t, r, t + rad);
    pb.line_to(r, b - rad);
    pb.quad_to(r, b, r - rad, b);
    pb.line_to(l + rad, b);
    pb.quad_to(l, b, l, b - rad);
    pb.line_to(l, t + rad);
    pb.quad_to(l, t, l + rad, t);
    pb.close();
    pb.finish()
}

fn mask(clip: IntRect, w: u32, h: u32) -> Option<Mask> {
    let mut m = Mask::new(w, h)?;
    let path = PathBuilder::from_rect(clip.to_rect());
    m.fill_path(&path, FillRule::Winding, false, Transform::identity());
    Some(m)
}

/// Blends `c` at coverage `alpha` into the pixel at `(x, y)`.
fn blend(pm: &mut Pixmap, x: i32, y: i32, c: &Color, alpha: u8) {
    let (w, h) = (pm.width() as i32, pm.height() as i32);
    if x < 0 || y < 0 || x >= w || y >= h {
        return;
    }
    let a = (alpha as u32 * c.a as u32 + 127) / 255;
    if a == 0 {
        return;
    }
    let i = (y * w + x) as usize;
    let d = pm.pixels()[i];
    let mix = |s: u8, d: u8| ((s as u32 * a + d as u32 * (255 - a) + 127) / 255) as u8;
    let out = PremultipliedColorU8::from_rgba(
        mix(c.r, d.red()),
        mix(c.g, d.green()),
        mix(c.b, d.blue()),
        ((a * 255 + d.alpha() as u32 * (255 - a) + 127) / 255) as u8,
    );
    if let Some(out) = out {
        pm.pixels_mut()[i] = out;
    }
}

fn draw_item(pm: &mut Pixmap, clip: &Rect, d: &Draw, scale: f32, text: &mut Text) {
    let (w, h) = (pm.width(), pm.height());
    let Some(clip) = clip_pixels(clip, scale, w, h) else { return };
    match d {
        Draw::Fill { rect, color, radius } => {
            let (l, t, r, b) = (px(rect.x0, scale), px(rect.y0, scale), px(rect.x1, scale), px(rect.y1, scale));
            if *radius == 0 {
                let cl = clip.to_rect();
                let (l, t, r, b) = (l.max(cl.left()), t.max(cl.top()), r.min(cl.right()), b.min(cl.bottom()));
                if let Some(rr) = tiny_skia::Rect::from_ltrb(l, t, r, b) {
                    pm.fill_rect(rr, &paint(color), Transform::identity(), None);
                }
            } else if let (Some(path), Some(m)) = (rounded(l, t, r, b, px(*radius, scale)), mask(clip, w, h)) {
                pm.fill_path(&path, &paint(color), FillRule::Winding, Transform::identity(), Some(&m));
            }
        }
        Draw::Stroke { rect, color, width, radius } => {
            let sw = px(*width, scale).max(0.5);
            let half = sw / 2.0;
            let (l, t, r, b) = (
                px(rect.x0, scale) + half,
                px(rect.y0, scale) + half,
                px(rect.x1, scale) - half,
                px(rect.y1, scale) - half,
            );
            if let (Some(path), Some(m)) = (rounded(l, t, r, b, px(*radius, scale)), mask(clip, w, h)) {
                let stroke = Stroke { width: sw, ..Stroke::default() };
                pm.stroke_path(&path, &paint(color), &stroke, Transform::identity(), Some(&m));
            }
        }
        Draw::Image { rect, id, alpha } => {
            let Some(src) = crate::image::get(*id) else { return };
            let (l, t, r, b) = (px(rect.x0, scale), px(rect.y0, scale), px(rect.x1, scale), px(rect.y1, scale));
            if r <= l || b <= t {
                return;
            }
            // The image fills its rectangle cut to the clip, as a pattern: no mask is needed.
            let cl = clip.to_rect();
            let Some(area) = tiny_skia::Rect::from_ltrb(l.max(cl.left()), t.max(cl.top()), r.min(cl.right()), b.min(cl.bottom()))
            else {
                return;
            };
            let tf = Transform::from_row((r - l) / src.width() as f32, 0.0, 0.0, (b - t) / src.height() as f32, l, t);
            let shader = Pattern::new(src.as_ref().as_ref(), SpreadMode::Pad, FilterQuality::Bilinear, *alpha as f32 / 255.0, tf);
            let paint = Paint { shader, anti_alias: false, ..Paint::default() };
            pm.fill_rect(area, &paint, Transform::identity(), None);
        }
        Draw::Path { points, closed, fill, stroke } => {
            let mut pb = PathBuilder::new();
            for (i, p) in points.iter().enumerate() {
                let (x, y) = (px(p.x, scale), px(p.y, scale));
                if i == 0 {
                    pb.move_to(x, y);
                } else {
                    pb.line_to(x, y);
                }
            }
            if *closed {
                pb.close();
            }
            let (Some(path), Some(m)) = (pb.finish(), mask(clip, w, h)) else { return };
            if let Some(c) = fill {
                pm.fill_path(&path, &paint(c), FillRule::Winding, Transform::identity(), Some(&m));
            }
            if let Some((c, width)) = stroke {
                let stroke = Stroke {
                    width: px(*width, scale).max(0.5),
                    line_cap: LineCap::Round,
                    line_join: LineJoin::Round,
                    ..Stroke::default()
                };
                pm.stroke_path(&path, &paint(c), &stroke, Transform::identity(), Some(&m));
            }
        }
        Draw::Text { at, text: s, style } => {
            let size = px(style.size, scale);
            text.draw(s, size, style.bold, px(at.x, scale), px(at.y, scale), |x, y, a| {
                if x >= clip.left() && x < clip.right() && y >= clip.top() && y < clip.bottom() {
                    blend(pm, x, y, &style.color, a);
                }
            });
        }
    }
}

/// The scene drawn at `scale` physical pixels per logical pixel, on white.
pub fn render(scene: &Scene, width: u32, height: u32, scale: f32, text: &mut Text) -> Pixmap {
    let mut pm = Pixmap::new(width.max(1), height.max(1)).expect("non-zero size");
    pm.fill(tiny_skia::Color::WHITE);
    for (clip, d) in &scene.items {
        draw_item(&mut pm, clip, d, scale, text);
    }
    pm
}

/// The pixels that differ between two PNGs, and an image of them: differing pixels red, the rest
/// faded. `None` if either does not decode or their sizes differ.
pub fn diff_png(a: &[u8], b: &[u8]) -> Option<(u64, Vec<u8>)> {
    let (pa, pb) = (Pixmap::decode_png(a).ok()?, Pixmap::decode_png(b).ok()?);
    if pa.width() != pb.width() || pa.height() != pb.height() {
        return None;
    }
    let mut out = pa.clone();
    let mut n = 0;
    for (o, (x, y)) in out.pixels_mut().iter_mut().zip(pa.pixels().iter().zip(pb.pixels())) {
        *o = if x != y {
            n += 1;
            PremultipliedColorU8::from_rgba(255, 0, 0, 255)?
        } else {
            let f = |c: u8| ((c as u32 + 3 * 255) / 4) as u8;
            PremultipliedColorU8::from_rgba(f(x.red()), f(x.green()), f(x.blue()), 255)?
        };
    }
    Some((n, out.encode_png().ok()?))
}

/// The pixels outside `(x0, y0)–(x1, y1)` that differ between two PNGs; `u64::MAX` if they do not
/// decode or their sizes differ.
pub fn diff_outside(a: &[u8], b: &[u8], x0: u32, y0: u32, x1: u32, y1: u32) -> u64 {
    let (Ok(pa), Ok(pb)) = (Pixmap::decode_png(a), Pixmap::decode_png(b)) else { return u64::MAX };
    if pa.width() != pb.width() || pa.height() != pb.height() {
        return u64::MAX;
    }
    let w = pa.width();
    pa.pixels()
        .iter()
        .zip(pb.pixels())
        .enumerate()
        .filter(|(i, (p, q))| {
            let (x, y) = (*i as u32 % w, *i as u32 / w);
            let inside = x >= x0 && x < x1 && y >= y0 && y < y1;
            !inside && p != q
        })
        .count() as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene::{Point, TextStyle};

    const RED: Color = Color { r: 255, g: 0, b: 0, a: 255 };
    const BLACK: Color = Color { r: 0, g: 0, b: 0, a: 255 };

    fn r(x: i64, y: i64, w: i64, h: i64) -> Rect {
        Rect { x0: x * 64, y0: y * 64, x1: (x + w) * 64, y1: (y + h) * 64 }
    }

    fn pixel(pm: &Pixmap, x: u32, y: u32) -> (u8, u8, u8) {
        let p = pm.pixel(x, y).unwrap();
        (p.red(), p.green(), p.blue())
    }

    #[test]
    fn images_and_paths_are_clipped() {
        let mut t = Text::bundled();
        let id = crate::image::register(2, 2, &[0, 0, 255, 255].repeat(4)).unwrap();
        let s = Scene { items: vec![(r(0, 0, 5, 5), Draw::Image { rect: r(0, 0, 10, 10), id, alpha: 255 })] };
        let pm = render(&s, 10, 10, 1.0, &mut t);
        assert_eq!(pixel(&pm, 2, 2), (0, 0, 255), "the image is drawn, scaled up");
        assert_eq!(pixel(&pm, 7, 7), (255, 255, 255), "but not past its clip");
        let gone = Scene { items: vec![(r(0, 0, 10, 10), Draw::Image { rect: r(0, 0, 10, 10), id: 0, alpha: 255 })] };
        assert_eq!(pixel(&render(&gone, 10, 10, 1.0, &mut t), 5, 5), (255, 255, 255), "an unknown image draws nothing");
        crate::image::release(id);
        let p = |x: i64, y: i64| Point { x: x * 64, y: y * 64 };
        let tri = Draw::Path { points: vec![p(0, 0), p(10, 0), p(10, 10), p(0, 10)], closed: true, fill: Some(RED), stroke: None };
        let pm = render(&Scene { items: vec![(r(0, 0, 5, 10), tri)] }, 10, 10, 1.0, &mut t);
        assert_eq!(pixel(&pm, 2, 5), (255, 0, 0));
        assert_eq!(pixel(&pm, 7, 5), (255, 255, 255));
    }

    #[test]
    fn a_fill_is_clipped() {
        let mut t = Text::bundled();
        let s = Scene { items: vec![(r(0, 0, 5, 5), Draw::Fill { rect: r(0, 0, 10, 10), color: RED, radius: 0 })] };
        let pm = render(&s, 10, 10, 1.0, &mut t);
        assert_eq!(pixel(&pm, 2, 2), (255, 0, 0));
        assert_eq!(pixel(&pm, 7, 7), (255, 255, 255));
        assert_eq!(pixel(&pm, 7, 2), (255, 255, 255));
    }

    #[test]
    fn scale_doubles_pixels() {
        let mut t = Text::bundled();
        let s = Scene { items: vec![(r(0, 0, 5, 5), Draw::Fill { rect: r(0, 0, 5, 5), color: RED, radius: 0 })] };
        let pm = render(&s, 20, 20, 2.0, &mut t);
        assert_eq!(pixel(&pm, 9, 9), (255, 0, 0));
        assert_eq!(pixel(&pm, 11, 11), (255, 255, 255));
    }

    #[test]
    fn rounded_shapes_and_strokes_stay_in_their_clip() {
        let mut t = Text::bundled();
        let s = Scene {
            items: vec![
                (r(0, 0, 6, 20), Draw::Fill { rect: r(0, 0, 20, 20), color: RED, radius: 4 * 64 }),
                (r(0, 0, 6, 20), Draw::Stroke { rect: r(0, 0, 20, 20), color: BLACK, width: 2 * 64, radius: 4 * 64 }),
            ],
        };
        let pm = render(&s, 20, 20, 1.0, &mut t);
        for y in 0..20 {
            for x in 6..20 {
                assert_eq!(pixel(&pm, x, y), (255, 255, 255), "({x}, {y})");
            }
        }
        assert_eq!(pixel(&pm, 4, 10), (255, 0, 0));
    }

    #[test]
    fn text_is_clipped() {
        let mut t = Text::bundled();
        let style = TextStyle { size: 20 * 64, color: BLACK, bold: false };
        let s = Scene {
            items: vec![(r(0, 0, 12, 30), Draw::Text { at: Point { x: 0, y: 0 }, text: "WWWWWW".into(), style })],
        };
        let pm = render(&s, 60, 30, 1.0, &mut t);
        let mut inside = 0;
        for y in 0..30 {
            for x in 0..60 {
                let p = pixel(&pm, x, y);
                if p != (255, 255, 255) {
                    assert!(x < 12, "ink at ({x}, {y})");
                    inside += 1;
                }
            }
        }
        assert!(inside > 10);
    }

    #[test]
    fn diffs() {
        let mut t = Text::bundled();
        let a = Scene { items: vec![(r(0, 0, 4, 4), Draw::Fill { rect: r(0, 0, 4, 4), color: RED, radius: 0 })] };
        let b = Scene { items: vec![(r(0, 0, 2, 2), Draw::Fill { rect: r(0, 0, 2, 2), color: RED, radius: 0 })] };
        let (pa, pb) = (render(&a, 8, 8, 1.0, &mut t).encode_png().unwrap(), render(&b, 8, 8, 1.0, &mut t).encode_png().unwrap());
        assert_eq!(diff_png(&pa, &pa).map(|d| d.0), Some(0));
        assert_eq!(diff_png(&pa, &pb).map(|d| d.0), Some(12));
        assert_eq!(diff_outside(&pa, &pb, 0, 0, 4, 4), 0);
        assert_eq!(diff_outside(&pa, &pb, 0, 0, 3, 3), 7);
        let small = render(&a, 4, 4, 1.0, &mut t).encode_png().unwrap();
        assert_eq!(diff_png(&pa, &small), None);
        assert_eq!(diff_outside(&pa, &small, 0, 0, 1, 1), u64::MAX);
        assert_eq!(diff_outside(&pa, b"junk", 0, 0, 1, 1), u64::MAX);
    }

    #[test]
    fn nothing_outside_the_pixmap() {
        let mut t = Text::bundled();
        let s = Scene { items: vec![(r(-50, -50, 500, 500), Draw::Fill { rect: r(-50, -50, 500, 500), color: RED, radius: 0 })] };
        let pm = render(&s, 10, 10, 1.0, &mut t);
        assert_eq!(pixel(&pm, 0, 0), (255, 0, 0));
        assert_eq!(pixel(&pm, 9, 9), (255, 0, 0));
    }
}
