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
    /// Text an input method is composing, with its cursor in characters.
    Preedit(String, u64),
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
    /// Assistive technology acts on a widget: 0 press, 1 focus.
    Access(u64, u64),
    /// The window gained or lost keyboard focus.
    Focus(bool),
    /// The window can or cannot be seen.
    Visible(bool),
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
        InputKind::Preedit(s, c) => {
            w.nat(8);
            w.string(s);
            w.nat(*c);
        }
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
            WindowEvent::Access(id, action) => {
                w.nat(3);
                w.nat(*id);
                w.nat(*action);
            }
            WindowEvent::Focus(b) => {
                w.nat(4);
                w.bool(*b);
            }
            WindowEvent::Visible(b) => {
                w.nat(5);
                w.bool(*b);
            }
        }
    }
    w.bytes
}

/// A node of the accessibility tree, as Lean sends it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccessNode {
    pub id: u64,
    /// 0 label, 1 button, 2 check box, 3 text input, 4 password input, 5 scroll view, 6 window.
    pub role: u64,
    pub name: String,
    pub value: Option<String>,
    /// 0 none, 1 unchecked, 2 checked.
    pub checked: u64,
    /// For a value in a range: its least, greatest, and itself.
    pub range: Option<(i64, i64, i64)>,
    pub focusable: bool,
    pub disabled: bool,
    pub bounds: crate::scene::Rect,
    pub children: Vec<u64>,
}

/// What Lean asks of the window, besides drawing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    SetTitle(String),
    SetClipboard(String),
    OpenUri(String),
    Notify(String, String),
    Quit,
    /// The accessibility tree and the focused node, 0 for none.
    Access(u64, Vec<AccessNode>),
    /// The pointer's shape: 0 default, 1 pointer, 2 text, 3 horizontal resize, 4 vertical resize.
    Cursor(u64),
    /// An input method allowed, with the caret's rectangle, or not.
    Ime(Option<crate::scene::Rect>),
}

fn access_node(r: &mut Reader) -> Option<AccessNode> {
    let id = r.nat()?;
    let role = r.nat()?;
    let name = r.string()?;
    let value = if r.bool()? { Some(r.string()?) } else { None };
    let checked = r.nat()?;
    let range = if r.bool()? { Some((r.int()?, r.int()?, r.int()?)) } else { None };
    let focusable = r.bool()?;
    let disabled = r.bool()?;
    let bounds = crate::scene::Rect { x0: r.int()?, y0: r.int()?, x1: r.int()?, y1: r.int()? };
    let n = r.count()?;
    let mut children = Vec::with_capacity(n);
    for _ in 0..n {
        children.push(r.nat()?);
    }
    Some(AccessNode { id, role, name, value, checked, range, focusable, disabled, bounds, children })
}

fn put_access_node(w: &mut Writer, n: &AccessNode) {
    w.nat(n.id);
    w.nat(n.role);
    w.string(&n.name);
    match &n.value {
        Some(v) => {
            w.bool(true);
            w.string(v);
        }
        None => w.bool(false),
    }
    w.nat(n.checked);
    w.bool(n.range.is_some());
    if let Some((lo, hi, v)) = n.range {
        w.int(lo);
        w.int(hi);
        w.int(v);
    }
    w.bool(n.focusable);
    w.bool(n.disabled);
    w.int(n.bounds.x0);
    w.int(n.bounds.y0);
    w.int(n.bounds.x1);
    w.int(n.bounds.y1);
    w.nat(n.children.len() as u64);
    for c in &n.children {
        w.nat(*c);
    }
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
            5 => {
                let focus = r.nat()?;
                let n = r.count()?;
                let mut nodes = Vec::with_capacity(n);
                for _ in 0..n {
                    nodes.push(access_node(&mut r)?);
                }
                Request::Access(focus, nodes)
            }
            6 => match r.nat()? {
                c @ 0..=4 => Request::Cursor(c),
                _ => return None,
            },
            7 => Request::Ime(if r.bool()? {
                Some(crate::scene::Rect { x0: r.int()?, y0: r.int()?, x1: r.int()?, y1: r.int()? })
            } else {
                None
            }),
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
            Request::Access(focus, nodes) => {
                w.nat(5);
                w.nat(*focus);
                w.nat(nodes.len() as u64);
                for n in nodes {
                    put_access_node(&mut w, n);
                }
            }
            Request::Cursor(c) => {
                w.nat(6);
                w.nat(*c);
            }
            Request::Ime(area) => {
                w.nat(7);
                w.bool(area.is_some());
                if let Some(r) = area {
                    w.int(r.x0);
                    w.int(r.y0);
                    w.int(r.x1);
                    w.int(r.y1);
                }
            }
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
        WindowEvent::Access(7, 1),
        WindowEvent::Focus(false),
        WindowEvent::Visible(true),
        input(InputKind::Preedit("日本".into(), 1), 11),
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
            Request::Cursor(2),
            Request::Ime(None),
            Request::Ime(Some(crate::scene::Rect { x0: 1, y0: -2, x1: 3, y1: 4 })),
            Request::Access(
                2,
                vec![AccessNode {
                    id: 2,
                    role: 1,
                    name: "Go".into(),
                    value: None,
                    checked: 0,
                    range: Some((0, 10, 3)),
                    focusable: true,
                    disabled: false,
                    bounds: crate::scene::Rect { x0: 0, y0: 0, x1: 640, y1: 640 },
                    children: vec![],
                }],
            ),
        ] {
            assert_eq!(Request::decode(&r.encode()), Some(r));
        }
        assert_eq!(Request::decode(&[9]), None);
        assert_eq!(Request::decode(&[4, 0]), None);
    }

    #[test]
    fn events_encode() {
        let bytes = encode_events(&sample());
        assert_eq!(bytes[0], 16);
        assert_eq!(encode_events(&[WindowEvent::Focus(false), WindowEvent::Visible(true)]), [2, 4, 0, 5, 1]);
        assert_eq!(encode_events(&[WindowEvent::Close]), [1, 2]);
        assert_eq!(encode_events(&[WindowEvent::Resize(1, -1)]), [1, 1, 2, 1]);
    }
}
