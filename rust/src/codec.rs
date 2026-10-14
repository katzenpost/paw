// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The byte formats shared with Lean, as `Paw/Codec.lean` and `Paw/Scene.lean` define them:
//! natural numbers are LEB128 varints, integers zigzag varints, lists a count then their
//! elements, and sums a tag then their fields.

/// Reads values from bytes, refusing anything not well formed.
pub struct Reader<'a> {
    bytes: &'a [u8],
}

impl<'a> Reader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        Reader { bytes }
    }

    pub fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }

    pub fn u8(&mut self) -> Option<u8> {
        let (&b, rest) = self.bytes.split_first()?;
        self.bytes = rest;
        Some(b)
    }

    /// A varint that fits in 64 bits.
    pub fn nat(&mut self) -> Option<u64> {
        let mut n: u64 = 0;
        let mut shift = 0u32;
        loop {
            let b = self.u8()?;
            let low = (b & 0x7F) as u64;
            if shift >= 64 || (shift > 0 && low >> (64 - shift) != 0) {
                return None;
            }
            n |= low << shift;
            if b < 0x80 {
                return Some(n);
            }
            shift += 7;
        }
    }

    pub fn int(&mut self) -> Option<i64> {
        let z = self.nat()?;
        Some(if z % 2 == 0 { (z / 2) as i64 } else { -(z.div_ceil(2) as i64) })
    }

    pub fn bool(&mut self) -> Option<bool> {
        match self.nat()? {
            0 => Some(false),
            1 => Some(true),
            _ => None,
        }
    }

    pub fn string(&mut self) -> Option<String> {
        let n = self.nat()?;
        let mut s = String::new();
        for _ in 0..n {
            s.push(char::from_u32(u32::try_from(self.nat()?).ok()?)?);
        }
        Some(s)
    }

    /// A count, no larger than the bytes left could hold.
    pub fn count(&mut self) -> Option<usize> {
        let n = usize::try_from(self.nat()?).ok()?;
        (n <= self.bytes.len()).then_some(n)
    }
}

#[derive(Default)]
pub struct Writer {
    pub bytes: Vec<u8>,
}

impl Writer {
    pub fn u8(&mut self, b: u8) {
        self.bytes.push(b);
    }

    pub fn nat(&mut self, mut n: u64) {
        while n >= 0x80 {
            self.bytes.push((n & 0x7F) as u8 | 0x80);
            n >>= 7;
        }
        self.bytes.push(n as u8);
    }

    pub fn int(&mut self, i: i64) {
        self.nat(if i >= 0 { 2 * i as u64 } else { 2 * i.unsigned_abs() - 1 });
    }

    pub fn bool(&mut self, b: bool) {
        self.nat(b as u64);
    }

    pub fn string(&mut self, s: &str) {
        self.nat(s.chars().count() as u64);
        for c in s.chars() {
            self.nat(c as u64);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nat(n: u64) -> Vec<u8> {
        let mut w = Writer::default();
        w.nat(n);
        w.bytes
    }

    fn int(i: i64) -> Vec<u8> {
        let mut w = Writer::default();
        w.int(i);
        w.bytes
    }

    #[test]
    fn layouts_match_lean() {
        assert_eq!(nat(0), [0]);
        assert_eq!(nat(127), [127]);
        assert_eq!(nat(128), [0x80, 1]);
        assert_eq!(nat(300), [0xAC, 2]);
        assert_eq!(int(0), [0]);
        assert_eq!(int(-1), [1]);
        assert_eq!(int(1), [2]);
        assert_eq!(int(-64), [127]);
        assert_eq!(int(64), [0x80, 1]);
        let mut w = Writer::default();
        w.string("hi");
        assert_eq!(w.bytes, [2, 104, 105]);
    }

    #[test]
    fn round_trips() {
        for i in [0, 1, -1, 63, -64, 64, i64::MAX, i64::MIN + 1, 123456789, -987654321] {
            assert_eq!(Reader::new(&int(i)).int(), Some(i));
        }
        for n in [0, 1, 127, 128, u64::MAX] {
            assert_eq!(Reader::new(&nat(n)).nat(), Some(n));
        }
        let mut w = Writer::default();
        w.string("héllo 🚀");
        assert_eq!(Reader::new(&w.bytes).string().as_deref(), Some("héllo 🚀"));
    }

    #[test]
    fn refuses_malformed() {
        assert_eq!(Reader::new(&[]).nat(), None);
        assert_eq!(Reader::new(&[0x80]).nat(), None);
        assert_eq!(Reader::new(&[0xFF; 11]).nat(), None);
        assert_eq!(Reader::new(&[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x02]).nat(), None);
        assert_eq!(Reader::new(&[2]).bool(), None);
        assert_eq!(Reader::new(&[1, 0x80, 0xB0, 0x03]).string(), None); // a surrogate
        assert_eq!(Reader::new(&[5, 1]).count(), None);
    }
}
