// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Window events for Lean and requests from it, in the formats `Paw/Linux.lean` defines.

use crate::codec::{Reader, Writer};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Enter,
    Escape,
    Backspace,
    Tab,
    Delete,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
    F(u32),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Mods {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub sup: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Button {
    Primary,
    Secondary,
    Middle,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputKind {
    Press(i64, i64, Button),
    Release(i64, i64, Button),
    Move(i64, i64),
    Wheel(i64, i64, i64, i64),
    Key(Key, Mods, bool),
    Text(String),
    Paste(String),
    LeaveWindow,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Input {
    pub kind: InputKind,
    pub time: u64,
    pub synthetic: bool,
    pub obscured: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WindowEvent {
    Input(Input),
    Resize(i64, i64),
    Close,
}

fn put_key(w: &mut Writer, k: &Key) {
    match k {
        Key::Char(c) => {
            w.nat(0);
            w.nat(*c as u64);
        }
        Key::F(n) => {
            w.nat(14);
            w.nat(*n as u64);
        }
        other => w.nat(match other {
            Key::Enter => 1,
            Key::Escape => 2,
            Key::Backspace => 3,
            Key::Tab => 4,
            Key::Delete => 5,
            Key::Left => 6,
            Key::Right => 7,
            Key::Up => 8,
            Key::Down => 9,
            Key::Home => 10,
            Key::End => 11,
            Key::PageUp => 12,
            _ => 13,
        }),
    }
}

fn put_button(w: &mut Writer, b: Button) {
    w.nat(match b {
        Button::Primary => 0,
        Button::Secondary => 1,
        Button::Middle => 2,
    });
}

fn put_input(w: &mut Writer, i: &Input) {
    match &i.kind {
        InputKind::Press(x, y, b) => {
            w.nat(0);
            w.int(*x);
            w.int(*y);
            put_button(w, *b);
        }
        InputKind::Release(x, y, b) => {
            w.nat(1);
            w.int(*x);
            w.int(*y);
            put_button(w, *b);
        }
        InputKind::Move(x, y) => {
            w.nat(2);
            w.int(*x);
            w.int(*y);
        }
        InputKind::Wheel(x, y, dx, dy) => {
            w.nat(3);
            w.int(*x);
            w.int(*y);
            w.int(*dx);
            w.int(*dy);
        }
        InputKind::Key(k, m, pressed) => {
            w.nat(4);
            put_key(w, k);
            w.bool(m.shift);
            w.bool(m.ctrl);
            w.bool(m.alt);
            w.bool(m.sup);
            w.bool(*pressed);
        }
        InputKind::Text(s) => {
            w.nat(5);
            w.string(s);
        }
        InputKind::Paste(s) => {
            w.nat(6);
            w.string(s);
        }
        InputKind::LeaveWindow => w.nat(7),
    }
    w.nat(i.time);
    w.bool(i.synthetic);
    w.bool(i.obscured);
}

pub fn encode_events(evs: &[WindowEvent]) -> Vec<u8> {
    let mut w = Writer::default();
    w.nat(evs.len() as u64);
    for e in evs {
        match e {
            WindowEvent::Input(i) => {
                w.nat(0);
                put_input(&mut w, i);
            }
            WindowEvent::Resize(x, y) => {
                w.nat(1);
                w.int(*x);
                w.int(*y);
            }
            WindowEvent::Close => w.nat(2),
        }
    }
    w.bytes
}

/// What Lean asks of the window, besides drawing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    SetTitle(String),
    SetClipboard(String),
    OpenUri(String),
    Notify(String, String),
    Quit,
}

impl Request {
    pub fn decode(bytes: &[u8]) -> Option<Request> {
        let mut r = Reader::new(bytes);
        let req = match r.nat()? {
            0 => Request::SetTitle(r.string()?),
            1 => Request::SetClipboard(r.string()?),
            2 => Request::OpenUri(r.string()?),
            3 => Request::Notify(r.string()?, r.string()?),
            4 => Request::Quit,
            _ => return None,
        };
        r.is_empty().then_some(req)
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut w = Writer::default();
        match self {
            Request::SetTitle(s) => {
                w.nat(0);
                w.string(s);
            }
            Request::SetClipboard(s) => {
                w.nat(1);
                w.string(s);
            }
            Request::OpenUri(s) => {
                w.nat(2);
                w.string(s);
            }
            Request::Notify(t, b) => {
                w.nat(3);
                w.string(t);
                w.string(b);
            }
            Request::Quit => w.nat(4),
        }
        w.bytes
    }
}

/// A fixed set of events, one of each kind, for testing that Lean decodes what Rust encodes.
pub fn sample() -> Vec<WindowEvent> {
    let input = |kind, time| WindowEvent::Input(Input { kind, time, synthetic: false, obscured: false });
    vec![
        input(InputKind::Press(640, -64, Button::Primary), 1),
        input(InputKind::Release(640, 64, Button::Secondary), 2),
        input(InputKind::Move(1, 2), 3),
        input(InputKind::Wheel(0, 0, -1, 2), 4),
        input(InputKind::Key(Key::Char('é'), Mods { ctrl: true, ..Mods::default() }, true), 5),
        input(InputKind::Key(Key::F(12), Mods::default(), false), 6),
        input(InputKind::Key(Key::PageDown, Mods { shift: true, alt: true, sup: true, ctrl: false }, true), 7),
        input(InputKind::Text("hé 🚀".into()), 8),
        input(InputKind::Paste("a\nb".into()), 9),
        WindowEvent::Input(Input { kind: InputKind::LeaveWindow, time: 10, synthetic: true, obscured: true }),
        WindowEvent::Resize(64000, 48000),
        WindowEvent::Close,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_round_trip() {
        for r in [
            Request::SetTitle("t".into()),
            Request::SetClipboard("c".into()),
            Request::OpenUri("https://example.org".into()),
            Request::Notify("a".into(), "b".into()),
            Request::Quit,
        ] {
            assert_eq!(Request::decode(&r.encode()), Some(r));
        }
        assert_eq!(Request::decode(&[9]), None);
        assert_eq!(Request::decode(&[4, 0]), None);
    }

    #[test]
    fn events_encode() {
        let bytes = encode_events(&sample());
        assert_eq!(bytes[0], 12);
        assert_eq!(encode_events(&[WindowEvent::Close]), [1, 2]);
        assert_eq!(encode_events(&[WindowEvent::Resize(1, -1)]), [1, 1, 2, 1]);
    }
}
