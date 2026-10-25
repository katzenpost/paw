// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! An input method that edits a buffer of its own, as Android's does, turned into Paw's inputs.
//! Between two states of the buffer, characters removed from the text outside the composing region
//! become Backspace, characters added become text, a newline becomes Enter, and the composing
//! region becomes the preedit. The cursor is taken to be at the end of what was typed.

use crate::events::{InputKind, Key, Mods};

#[derive(Default)]
pub struct TextInput {
    committed: Vec<char>,
    preedit: String,
}

fn key(k: Key) -> [InputKind; 2] {
    [
        InputKind::Key(k.clone(), Mods::default(), true),
        InputKind::Key(k, Mods::default(), false),
    ]
}

/// A byte offset into `s` from an offset in UTF-16 code units, as Java counts, clamped to `s`.
fn byte_of_utf16(s: &str, u: usize) -> usize {
    let mut n = 0;
    for (i, c) in s.char_indices() {
        if n >= u {
            return i;
        }
        n += c.len_utf16();
    }
    s.len()
}

impl TextInput {
    /// Forgets the buffer, as when the input method starts on a new field.
    pub fn reset(&mut self) {
        *self = TextInput::default();
    }

    /// The inputs that take the buffer from its last state to `text`, whose composing region is
    /// `compose` in UTF-16 code units.
    pub fn update(&mut self, text: &str, compose: Option<(usize, usize)>) -> Vec<InputKind> {
        let (committed, preedit) = match compose {
            Some((a, b)) if a < b => {
                let (a, b) = (byte_of_utf16(text, a), byte_of_utf16(text, b));
                let (a, b) = (a.min(b), a.max(b));
                (
                    format!("{}{}", &text[..a], &text[b..]),
                    text[a..b].to_string(),
                )
            }
            _ => (text.to_string(), String::new()),
        };
        let committed: Vec<char> = committed.chars().collect();
        let mut out = Vec::new();
        let same = self
            .committed
            .iter()
            .zip(&committed)
            .take_while(|(a, b)| a == b)
            .count();
        let edits = same < self.committed.len() || same < committed.len();
        // The old preedit goes before an edit, so the edit lands where it was.
        if !self.preedit.is_empty() && (preedit.is_empty() || (edits && preedit != self.preedit)) {
            out.push(InputKind::Preedit(String::new(), 0));
            self.preedit.clear();
        }
        for _ in same..self.committed.len() {
            out.extend(key(Key::Backspace));
        }
        let mut run = String::new();
        for &c in &committed[same..] {
            if c == '\n' {
                if !run.is_empty() {
                    out.push(InputKind::Text(std::mem::take(&mut run)));
                }
                out.extend(key(Key::Enter));
            } else if !c.is_control() {
                run.push(c);
            }
        }
        if !run.is_empty() {
            out.push(InputKind::Text(run));
        }
        if preedit != self.preedit && !preedit.is_empty() {
            out.push(InputKind::Preedit(
                preedit.clone(),
                preedit.chars().count() as u64,
            ));
        }
        self.committed = committed;
        self.preedit = preedit;
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use InputKind::{Preedit, Text};

    fn text(s: &str) -> Vec<InputKind> {
        vec![Text(s.to_string())]
    }

    fn keys(k: Key, n: usize) -> Vec<InputKind> {
        (0..n).flat_map(|_| key(k.clone())).collect()
    }

    #[test]
    fn typing_commits() {
        let mut t = TextInput::default();
        assert_eq!(t.update("h", None), text("h"));
        assert_eq!(t.update("hé", None), text("é"));
        assert_eq!(t.update("hé", None), vec![]);
    }

    #[test]
    fn composing_then_commit() {
        let mut t = TextInput::default();
        assert_eq!(t.update("he", Some((0, 2))), vec![Preedit("he".into(), 2)]);
        assert_eq!(
            t.update("hel", Some((0, 3))),
            vec![Preedit("hel".into(), 3)]
        );
        assert_eq!(
            t.update("hello ", None),
            [vec![Preedit(String::new(), 0)], text("hello ")].concat()
        );
        assert_eq!(
            t.update("hello wo", Some((6, 8))),
            vec![Preedit("wo".into(), 2)]
        );
    }

    #[test]
    fn deleting_is_backspace() {
        let mut t = TextInput::default();
        t.update("abc", None);
        assert_eq!(t.update("ab", None), keys(Key::Backspace, 1));
        assert_eq!(t.update("", None), keys(Key::Backspace, 2));
    }

    #[test]
    fn autocorrect_replaces_a_word() {
        let mut t = TextInput::default();
        t.update("teh ", None);
        assert_eq!(
            t.update("the ", None),
            [keys(Key::Backspace, 3), text("he ")].concat()
        );
    }

    #[test]
    fn newline_is_enter() {
        let mut t = TextInput::default();
        assert_eq!(
            t.update("a\nb", None),
            [text("a"), keys(Key::Enter, 1), text("b")].concat()
        );
    }

    #[test]
    fn compose_region_in_utf16() {
        let mut t = TextInput::default();
        // "😀" is two UTF-16 code units.
        assert_eq!(
            t.update("😀ab", Some((2, 4))),
            [text("😀"), vec![Preedit("ab".into(), 2)]].concat()
        );
    }

    #[test]
    fn reset_forgets() {
        let mut t = TextInput::default();
        t.update("abc", None);
        t.reset();
        assert_eq!(t.update("x", None), text("x"));
    }
}
