// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Scenes as `Paw/Scene.lean` defines them: draw items, each with the clip it is drawn under.
//! Coordinates are in units of 1/64 of a logical pixel.

use crate::codec::{Reader, Writer};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x0: i64,
    pub y0: i64,
    pub x1: i64,
    pub y1: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Point {
    pub x: i64,
    pub y: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextStyle {
    pub size: i64,
    pub color: Color,
    pub bold: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Draw {
    Fill { rect: Rect, color: Color, radius: i64 },
    Stroke { rect: Rect, color: Color, width: i64, radius: i64 },
    Text { at: Point, text: String, style: TextStyle },
    /// The image with an id from `image::register`, scaled into `rect`, at opacity `alpha`.
    Image { rect: Rect, id: u64, alpha: u8 },
    /// A path through `points`, closed if `closed`, filled and stroked if given.
    Path { points: Vec<Point>, closed: bool, fill: Option<Color>, stroke: Option<(Color, i64)> },
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Scene {
    pub items: Vec<(Rect, Draw)>,
}

fn rect(r: &mut Reader) -> Option<Rect> {
    Some(Rect { x0: r.int()?, y0: r.int()?, x1: r.int()?, y1: r.int()? })
}

fn color(r: &mut Reader) -> Option<Color> {
    Some(Color { r: r.u8()?, g: r.u8()?, b: r.u8()?, a: r.u8()? })
}

fn draw(r: &mut Reader) -> Option<Draw> {
    Some(match r.nat()? {
        0 => Draw::Fill { rect: rect(r)?, color: color(r)?, radius: r.int()? },
        1 => Draw::Stroke { rect: rect(r)?, color: color(r)?, width: r.int()?, radius: r.int()? },
        2 => Draw::Text {
            at: Point { x: r.int()?, y: r.int()? },
            text: r.string()?,
            style: TextStyle { size: r.int()?, color: color(r)?, bold: r.bool()? },
        },
        3 => Draw::Image { rect: rect(r)?, id: r.nat()?, alpha: r.u8()? },
        4 => {
            let n = r.count()?;
            let mut points = Vec::with_capacity(n);
            for _ in 0..n {
                points.push(Point { x: r.int()?, y: r.int()? });
            }
            let closed = r.bool()?;
            let fill = if r.bool()? { Some(color(r)?) } else { None };
            let stroke = if r.bool()? { Some((color(r)?, r.int()?)) } else { None };
            Draw::Path { points, closed, fill, stroke }
        }
        _ => return None,
    })
}

impl Scene {
    /// Decodes exactly one scene, with nothing left over.
    pub fn decode(bytes: &[u8]) -> Option<Scene> {
        let mut r = Reader::new(bytes);
        let n = r.count()?;
        let mut items = Vec::with_capacity(n);
        for _ in 0..n {
            items.push((rect(&mut r)?, draw(&mut r)?));
        }
        r.is_empty().then_some(Scene { items })
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut w = Writer::default();
        w.nat(self.items.len() as u64);
        for (clip, d) in &self.items {
            put_rect(&mut w, clip);
            match d {
                Draw::Fill { rect, color, radius } => {
                    w.nat(0);
                    put_rect(&mut w, rect);
                    put_color(&mut w, color);
                    w.int(*radius);
                }
                Draw::Stroke { rect, color, width, radius } => {
                    w.nat(1);
                    put_rect(&mut w, rect);
                    put_color(&mut w, color);
                    w.int(*width);
                    w.int(*radius);
                }
                Draw::Text { at, text, style } => {
                    w.nat(2);
                    w.int(at.x);
                    w.int(at.y);
                    w.string(text);
                    w.int(style.size);
                    put_color(&mut w, &style.color);
                    w.bool(style.bold);
                }
                Draw::Image { rect, id, alpha } => {
                    w.nat(3);
                    put_rect(&mut w, rect);
                    w.nat(*id);
                    w.u8(*alpha);
                }
                Draw::Path { points, closed, fill, stroke } => {
                    w.nat(4);
                    w.nat(points.len() as u64);
                    for p in points {
                        w.int(p.x);
                        w.int(p.y);
                    }
                    w.bool(*closed);
                    w.bool(fill.is_some());
                    if let Some(c) = fill {
                        put_color(&mut w, c);
                    }
                    w.bool(stroke.is_some());
                    if let Some((c, width)) = stroke {
                        put_color(&mut w, c);
                        w.int(*width);
                    }
                }
            }
        }
        w.bytes
    }
}

fn put_rect(w: &mut Writer, r: &Rect) {
    w.int(r.x0);
    w.int(r.y0);
    w.int(r.x1);
    w.int(r.y1);
}

fn put_color(w: &mut Writer, c: &Color) {
    w.u8(c.r);
    w.u8(c.g);
    w.u8(c.b);
    w.u8(c.a);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Scene {
        let r = Rect { x0: 0, y0: 0, x1: 6400, y1: 1280 };
        let c = Color { r: 255, g: 0, b: 0, a: 255 };
        Scene {
            items: vec![
                (r, Draw::Fill { rect: r, color: c, radius: 0 }),
                (r, Draw::Stroke { rect: r, color: c, width: 64, radius: 256 }),
                (
                    r,
                    Draw::Text {
                        at: Point { x: -128, y: 128 },
                        text: "hi ␛ 🚀".into(),
                        style: TextStyle { size: 896, color: c, bold: true },
                    },
                ),
                (r, Draw::Image { rect: r, id: 7, alpha: 128 }),
                (
                    r,
                    Draw::Path {
                        points: vec![Point { x: 0, y: 0 }, Point { x: 640, y: -64 }],
                        closed: true,
                        fill: Some(c),
                        stroke: Some((c, 128)),
                    },
                ),
                (r, Draw::Path { points: vec![], closed: false, fill: None, stroke: None }),
            ],
        }
    }

    #[test]
    fn round_trip() {
        assert_eq!(Scene::decode(&sample().encode()), Some(sample()));
    }

    #[test]
    fn a_fill_matches_lean() {
        // Lean: Draw.codec.enc (.fill (r 0 0 1 1) red 0) after its clip, one item.
        let r = Rect { x0: 0, y0: 0, x1: 64, y1: 64 };
        let s = Scene { items: vec![(r, Draw::Fill { rect: r, color: Color { r: 255, g: 0, b: 0, a: 255 }, radius: 0 })] };
        assert_eq!(s.encode(), [1, 0, 0, 0x80, 1, 0x80, 1, 0, 0, 0, 0x80, 1, 0x80, 1, 255, 0, 0, 255, 0]);
    }

    #[test]
    fn refuses_malformed() {
        let bytes = sample().encode();
        for n in 0..bytes.len() {
            assert_eq!(Scene::decode(&bytes[..n]), None, "cut at {n}");
        }
        let mut extra = bytes.clone();
        extra.push(0);
        assert_eq!(Scene::decode(&extra), None);
        assert_eq!(Scene::decode(&[1, 0, 0, 0, 0, 9]), None);
    }
}
