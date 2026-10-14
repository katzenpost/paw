// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! A virtual pointer for the end-to-end tests under a headless sway, which has no pointer of its
//! own. It stays connected so that windows have a pointer to bind before a click arrives, and
//! reads commands from standard input, one per line:
//!
//!     move X Y     put the pointer at (X, Y) on the output, in pixels
//!     click        press and release the left button
//!
//! Run as `vpointer WIDTH HEIGHT`, the output's size.

use std::io::BufRead;
use wayland_client::protocol::{wl_pointer, wl_registry, wl_seat};
use wayland_client::{delegate_noop, Connection, Dispatch, QueueHandle};
use wayland_protocols_wlr::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};

const BTN_LEFT: u32 = 0x110;

#[derive(Default)]
struct State {
    seat: Option<wl_seat::WlSeat>,
    manager: Option<ZwlrVirtualPointerManagerV1>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for State {
    fn event(s: &mut Self, r: &wl_registry::WlRegistry, e: wl_registry::Event, _: &(), _: &Connection, qh: &QueueHandle<Self>) {
        if let wl_registry::Event::Global { name, interface, .. } = e {
            match interface.as_str() {
                "wl_seat" => s.seat = Some(r.bind(name, 1, qh, ())),
                "zwlr_virtual_pointer_manager_v1" => s.manager = Some(r.bind(name, 1, qh, ())),
                _ => {}
            }
        }
    }
}

delegate_noop!(State: ignore wl_seat::WlSeat);
delegate_noop!(State: ZwlrVirtualPointerManagerV1);
delegate_noop!(State: ZwlrVirtualPointerV1);

fn main() {
    let args: Vec<u32> = std::env::args().skip(1).filter_map(|a| a.parse().ok()).collect();
    let (w, h) = (args.first().copied().unwrap_or(1024), args.get(1).copied().unwrap_or(768));
    let conn = Connection::connect_to_env().expect("a Wayland display");
    let mut queue = conn.new_event_queue();
    let qh = queue.handle();
    conn.display().get_registry(&qh, ());
    let mut state = State::default();
    queue.roundtrip(&mut state).expect("roundtrip");
    let manager = state.manager.as_ref().expect("the compositor offers zwlr_virtual_pointer_manager_v1");
    let pointer = manager.create_virtual_pointer(state.seat.as_ref(), &qh, ());
    queue.roundtrip(&mut state).expect("roundtrip");
    println!("ready");
    let mut t = 0u32;
    for line in std::io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        let words: Vec<&str> = line.split_whitespace().collect();
        t += 10;
        match words.as_slice() {
            ["move", x, y] => {
                let (x, y) = (x.parse().unwrap_or(0), y.parse().unwrap_or(0));
                pointer.motion_absolute(t, x, y, w, h);
                pointer.frame();
            }
            ["click"] => {
                pointer.button(t, BTN_LEFT, wl_pointer::ButtonState::Pressed);
                pointer.frame();
                pointer.button(t + 5, BTN_LEFT, wl_pointer::ButtonState::Released);
                pointer.frame();
            }
            _ => continue,
        }
        let _ = queue.roundtrip(&mut state);
        println!("done");
    }
}
