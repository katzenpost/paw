// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Touch as a pointer: the first finger down is the primary button, and other fingers are ignored
//! until it lifts. A lifted finger leaves the window, so nothing stays hovered.

use crate::events::{Button, InputKind};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Started,
    Moved,
    Ended,
    Cancelled,
}

#[derive(Default)]
pub struct Touch {
    finger: Option<u64>,
}

impl Touch {
    /// The inputs a finger's move makes, at `(x, y)` in units.
    pub fn event(&mut self, finger: u64, phase: Phase, x: i64, y: i64) -> Vec<InputKind> {
        match phase {
            Phase::Started if self.finger.is_none() => {
                self.finger = Some(finger);
                vec![
                    InputKind::Move(x, y),
                    InputKind::Press(x, y, Button::Primary),
                ]
            }
            _ if self.finger != Some(finger) => vec![],
            Phase::Started | Phase::Moved => vec![InputKind::Move(x, y)],
            Phase::Ended => {
                self.finger = None;
                vec![
                    InputKind::Release(x, y, Button::Primary),
                    InputKind::LeaveWindow,
                ]
            }
            // Released outside the window, so the press activates nothing.
            Phase::Cancelled => {
                self.finger = None;
                vec![
                    InputKind::Release(-1, -1, Button::Primary),
                    InputKind::LeaveWindow,
                ]
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use InputKind::*;

    #[test]
    fn tap() {
        let mut t = Touch::default();
        assert_eq!(
            t.event(7, Phase::Started, 10, 20),
            vec![Move(10, 20), Press(10, 20, Button::Primary)]
        );
        assert_eq!(t.event(7, Phase::Moved, 11, 21), vec![Move(11, 21)]);
        assert_eq!(
            t.event(7, Phase::Ended, 11, 21),
            vec![Release(11, 21, Button::Primary), LeaveWindow]
        );
    }

    #[test]
    fn second_finger_ignored() {
        let mut t = Touch::default();
        t.event(1, Phase::Started, 0, 0);
        assert_eq!(t.event(2, Phase::Started, 5, 5), vec![]);
        assert_eq!(t.event(2, Phase::Moved, 6, 6), vec![]);
        assert_eq!(t.event(2, Phase::Ended, 6, 6), vec![]);
        assert_eq!(
            t.event(1, Phase::Ended, 1, 1),
            vec![Release(1, 1, Button::Primary), LeaveWindow]
        );
        assert_eq!(
            t.event(2, Phase::Started, 3, 3),
            vec![Move(3, 3), Press(3, 3, Button::Primary)]
        );
    }

    #[test]
    fn cancel_releases_outside() {
        let mut t = Touch::default();
        t.event(1, Phase::Started, 4, 4);
        assert_eq!(
            t.event(1, Phase::Cancelled, 4, 4),
            vec![Release(-1, -1, Button::Primary), LeaveWindow]
        );
        assert_eq!(t.event(1, Phase::Moved, 4, 4), vec![]);
    }
}
