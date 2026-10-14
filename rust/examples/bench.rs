// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Benchmarks of the platform layer: decoding and drawing scenes, and measuring text. Run with
//! `cargo run --release --example bench`; each line gives the median and fastest time.

use benchmark::benchmark_block;
use paw_ffi::events::{encode_events, sample};
use paw_ffi::render::render;
use paw_ffi::scene::{Color, Draw, Point, Rect, Scene, TextStyle};
use paw_ffi::text::Text;
use std::hint::black_box;

fn scene(rows: i64) -> Scene {
    let black = Color { r: 0x20, g: 0x20, b: 0x20, a: 255 };
    let white = Color { r: 255, g: 255, b: 255, a: 255 };
    let mut items = Vec::new();
    for i in 0..rows {
        let r = Rect { x0: 0, y0: i * 28 * 64, x1: 800 * 64, y1: (i + 1) * 28 * 64 };
        let b = Rect { x0: 700 * 64, y0: r.y0 + 2 * 64, x1: 790 * 64, y1: r.y1 - 2 * 64 };
        items.push((r, Draw::Fill { rect: r, color: white, radius: 0 }));
        items.push((r, Draw::Text { at: Point { x: 8 * 64, y: r.y0 }, text: format!("message number {i}, which says something"),
            style: TextStyle { size: 14 * 64, color: black, bold: false } }));
        items.push((r, Draw::Fill { rect: b, color: white, radius: 4 * 64 }));
        items.push((r, Draw::Stroke { rect: b, color: black, width: 64, radius: 4 * 64 }));
        items.push((r, Draw::Text { at: Point { x: 708 * 64, y: b.y0 }, text: "Remove".into(),
            style: TextStyle { size: 14 * 64, color: black, bold: false } }));
    }
    Scene { items }
}

fn report(name: &str, samples: Vec<benchmark::Duration>) {
    let mut ns: Vec<u128> = samples.iter().map(|d| d.as_nanos()).collect();
    ns.sort_unstable();
    let fmt = |n: u128| if n >= 1_000_000 { format!("{:.2} ms", n as f64 / 1e6) } else { format!("{:.1} µs", n as f64 / 1e3) };
    println!("{name:<44} median {:>10}   min {:>10}   ({} samples)", fmt(ns[ns.len() / 2]), fmt(ns[0]), ns.len());
}

fn main() {
    let mut t = Text::bundled();
    let big = scene(400);
    let bytes = big.encode();
    let screen = scene(22);
    report("scene encode 2000 items", benchmark_block!(200, { black_box(big.encode()); }));
    report("scene decode 2000 items", benchmark_block!(200, { black_box(Scene::decode(black_box(&bytes))); }));
    report("events encode 12", benchmark_block!(10_000, { black_box(encode_events(black_box(&sample()))); }));
    report("measure a word", benchmark_block!(2_000, { black_box(t.measure(black_box("Remove"), 14.0, false)); }));
    report("measure 540 characters", benchmark_block!(500, {
        black_box(t.measure(black_box(&"a fairly long line of text ".repeat(20)), 14.0, false)); }));
    report("render a screen of 22 rows, 800x600", benchmark_block!(100, { black_box(render(&screen, 800, 600, 1.0, &mut t)); }));
    report("render a screen of 22 rows, 1600x1200 (2x)", benchmark_block!(50, { black_box(render(&screen, 1600, 1200, 2.0, &mut t)); }));
    report("render 400 rows clipped to 800x600", benchmark_block!(50, { black_box(render(&big, 800, 600, 1.0, &mut t)); }));
    // Images: a 1024 × 1024 photo-like PNG, and 100 thumbnails of a 64 × 64 image on one screen.
    let photo = image::RgbaImage::from_fn(1024, 1024, |x, y| image::Rgba([(x % 256) as u8, (y % 256) as u8, ((x ^ y) % 256) as u8, 255]));
    let mut png = Vec::new();
    photo.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png).unwrap();
    report("decode a 1024x1024 PNG", benchmark_block!(10, { black_box(paw_ffi::image::decode(black_box(&png)).unwrap()); }));
    let thumb = paw_ffi::image::register(64, 64, &[128; 64 * 64 * 4]).unwrap();
    let thumbs = Scene {
        items: (0..100)
            .map(|i| {
                let r = Rect { x0: (i % 10) * 80 * 64, y0: (i / 10) * 60 * 64, x1: ((i % 10) * 80 + 72) * 64, y1: ((i / 10) * 60 + 54) * 64 };
                (r, Draw::Image { rect: r, id: thumb, alpha: 255 })
            })
            .collect(),
    };
    report("render 100 images, 800x600", benchmark_block!(50, { black_box(render(&thumbs, 800, 600, 1.0, &mut t)); }));
}
