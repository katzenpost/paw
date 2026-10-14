// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! The window: winit pumped from Lean's loop, so no Lean code runs inside a winit callback, and
//! softbuffer to show what `render` draws. Input is turned into events in units of 1/64 logical
//! pixel; a paste is read from the clipboard only when the user presses Ctrl-V. AccessKit serves the
//! accessibility tree Lean sends to screen readers, and its action requests come back as events.

use crate::events::{Button, Input, InputKind, Key, Mods, Request, WindowEvent};
use crate::render::{render, UNITS};
use crate::scene::Scene;
use crate::text::with_text;
use std::cell::RefCell;
use std::num::NonZeroU32;
use std::rc::Rc;
use std::time::{Duration, Instant};
use winit::application::ApplicationHandler;
use winit::dpi::LogicalSize;
use winit::event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent as WE};
use winit::event_loop::{ActiveEventLoop, EventLoop, EventLoopProxy};
use winit::keyboard::{Key as WKey, NamedKey};
use winit::platform::pump_events::{EventLoopExtPumpEvents, PumpStatus};
use winit::window::{Window, WindowId};

/// Milliseconds since the platform layer started.
pub fn now() -> u64 {
    thread_local!(static START: Instant = Instant::now());
    START.with(|s| s.elapsed().as_millis() as u64)
}

struct App {
    title: String,
    size: (u32, u32),
    window: Option<Rc<Window>>,
    surface: Option<softbuffer::Surface<Rc<Window>, Rc<Window>>>,
    events: Vec<WindowEvent>,
    mods: Mods,
    cursor: (i64, i64),
    scene: Scene,
    clipboard: Option<arboard::Clipboard>,
    proxy: EventLoopProxy<accesskit_winit::Event>,
    adapter: Option<accesskit_winit::Adapter>,
    /// The last accessibility tree from Lean, for a screen reader that asks for it.
    access: Option<accesskit::TreeUpdate>,
}

thread_local! {
    static LOOP: RefCell<Option<EventLoop<accesskit_winit::Event>>> = const { RefCell::new(None) };
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

fn units(v: f64, scale: f64) -> i64 {
    (v / scale * UNITS as f64).round() as i64
}

fn key_of(k: &WKey) -> Option<Key> {
    Some(match k {
        WKey::Named(n) => match n {
            NamedKey::Enter => Key::Enter,
            NamedKey::Escape => Key::Escape,
            NamedKey::Backspace => Key::Backspace,
            NamedKey::Tab => Key::Tab,
            NamedKey::Delete => Key::Delete,
            NamedKey::ArrowLeft => Key::Left,
            NamedKey::ArrowRight => Key::Right,
            NamedKey::ArrowUp => Key::Up,
            NamedKey::ArrowDown => Key::Down,
            NamedKey::Home => Key::Home,
            NamedKey::End => Key::End,
            NamedKey::PageUp => Key::PageUp,
            NamedKey::PageDown => Key::PageDown,
            NamedKey::Space => Key::Char(' '),
            NamedKey::F1 => Key::F(1),
            NamedKey::F2 => Key::F(2),
            NamedKey::F3 => Key::F(3),
            NamedKey::F4 => Key::F(4),
            NamedKey::F5 => Key::F(5),
            NamedKey::F6 => Key::F(6),
            NamedKey::F7 => Key::F(7),
            NamedKey::F8 => Key::F(8),
            NamedKey::F9 => Key::F(9),
            NamedKey::F10 => Key::F(10),
            NamedKey::F11 => Key::F(11),
            NamedKey::F12 => Key::F(12),
            _ => return None,
        },
        WKey::Character(s) => Key::Char(s.chars().next()?.to_lowercase().next()?),
        _ => return None,
    })
}

impl App {
    fn scale(&self) -> f64 {
        self.window.as_ref().map(|w| w.scale_factor()).unwrap_or(1.0)
    }

    fn input(&mut self, kind: InputKind) {
        self.events.push(WindowEvent::Input(Input { kind, time: now(), synthetic: false, obscured: false }));
    }

    fn present(&mut self) {
        let (Some(window), Some(surface)) = (self.window.as_ref(), self.surface.as_mut()) else { return };
        let size = window.inner_size();
        let (Some(w), Some(h)) = (NonZeroU32::new(size.width), NonZeroU32::new(size.height)) else { return };
        let scale = window.scale_factor() as f32;
        let pm = with_text(|t| render(&self.scene, w.get(), h.get(), scale, t));
        if surface.resize(w, h).is_err() {
            return;
        }
        let Ok(mut buf) = surface.buffer_mut() else { return };
        for (dst, p) in buf.iter_mut().zip(pm.pixels()) {
            *dst = ((p.red() as u32) << 16) | ((p.green() as u32) << 8) | p.blue() as u32;
        }
        let _ = buf.present();
    }
}

impl ApplicationHandler<accesskit_winit::Event> for App {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        // AccessKit must be attached before the window is first shown.
        let attrs = Window::default_attributes()
            .with_title(self.title.clone())
            .with_inner_size(LogicalSize::new(self.size.0, self.size.1))
            .with_visible(false);
        let Ok(window) = el.create_window(attrs) else { return };
        self.adapter = Some(accesskit_winit::Adapter::with_event_loop_proxy(el, &window, self.proxy.clone()));
        window.set_visible(true);
        let window = Rc::new(window);
        if let Ok(ctx) = softbuffer::Context::new(window.clone()) {
            self.surface = softbuffer::Surface::new(&ctx, window.clone()).ok();
        }
        let s = window.inner_size();
        let scale = window.scale_factor();
        self.events.push(WindowEvent::Resize(units(s.width as f64, scale), units(s.height as f64, scale)));
        self.window = Some(window);
    }

    fn user_event(&mut self, _el: &ActiveEventLoop, event: accesskit_winit::Event) {
        use accesskit_winit::WindowEvent as Ak;
        match event.window_event {
            Ak::InitialTreeRequested => {
                let tree = self.access.clone().unwrap_or_else(|| crate::access::empty(&self.title));
                if let Some(a) = self.adapter.as_mut() {
                    a.update_if_active(|| tree);
                }
            }
            Ak::ActionRequested(req) => {
                let action = match req.action {
                    accesskit::Action::Click => 0,
                    accesskit::Action::Focus => 1,
                    _ => return,
                };
                self.events.push(WindowEvent::Access(req.target.0, action));
            }
            Ak::AccessibilityDeactivated => {}
        }
    }

    fn window_event(&mut self, _el: &ActiveEventLoop, _id: WindowId, event: WE) {
        if let (Some(a), Some(w)) = (self.adapter.as_mut(), self.window.as_ref()) {
            a.process_event(w, &event);
        }
        let scale = self.scale();
        match event {
            WE::CloseRequested => self.events.push(WindowEvent::Close),
            WE::Resized(s) => {
                self.events.push(WindowEvent::Resize(units(s.width as f64, scale), units(s.height as f64, scale)))
            }
            WE::RedrawRequested => self.present(),
            WE::Focused(f) => self.events.push(WindowEvent::Focus(f)),
            WE::Occluded(o) => self.events.push(WindowEvent::Visible(!o)),
            WE::ModifiersChanged(m) => {
                let s = m.state();
                self.mods = Mods { shift: s.shift_key(), ctrl: s.control_key(), alt: s.alt_key(), sup: s.super_key() };
            }
            WE::CursorMoved { position, .. } => {
                self.cursor = (units(position.x, scale), units(position.y, scale));
                self.input(InputKind::Move(self.cursor.0, self.cursor.1));
            }
            WE::CursorLeft { .. } => self.input(InputKind::LeaveWindow),
            WE::MouseInput { state, button, .. } => {
                let b = match button {
                    MouseButton::Left => Button::Primary,
                    MouseButton::Right => Button::Secondary,
                    MouseButton::Middle => Button::Middle,
                    _ => return,
                };
                let (x, y) = self.cursor;
                self.input(match state {
                    ElementState::Pressed => InputKind::Press(x, y, b),
                    ElementState::Released => InputKind::Release(x, y, b),
                });
            }
            WE::MouseWheel { delta, .. } => {
                let (dx, dy) = match delta {
                    MouseScrollDelta::LineDelta(x, y) => (-x.round() as i64, -y.round() as i64),
                    MouseScrollDelta::PixelDelta(p) => (-(p.x / 40.0).round() as i64, -(p.y / 40.0).round() as i64),
                };
                if dx != 0 || dy != 0 {
                    let (x, y) = self.cursor;
                    self.input(InputKind::Wheel(x, y, dx, dy));
                }
            }
            WE::KeyboardInput { event, is_synthetic, .. } => {
                // Keys winit reports as held when focus arrives were not pressed in this window.
                if is_synthetic {
                    return;
                }
                let pressed = event.state == ElementState::Pressed;
                let m = self.mods;
                let Some(k) = key_of(&event.logical_key) else { return };
                if pressed && m.ctrl && !m.alt && k == Key::Char('v') {
                    let text = self.clipboard.as_mut().and_then(|c| c.get_text().ok()).unwrap_or_default();
                    self.input(InputKind::Paste(text));
                    return;
                }
                self.input(InputKind::Key(k, m, pressed));
                if pressed && !m.ctrl && !m.alt && !m.sup {
                    if let Some(t) = event.text {
                        let t: String = t.chars().filter(|c| !c.is_control()).collect();
                        if !t.is_empty() {
                            self.input(InputKind::Text(t));
                        }
                    }
                }
            }
            _ => {}
        }
    }
}

/// Opens the window. The first poll reports its size.
pub fn open(title: &str, width: u32, height: u32) -> Result<(), String> {
    // Lean runs `main` on a thread of its own; every use of the loop stays on that thread.
    let mut builder = EventLoop::<accesskit_winit::Event>::with_user_event();
    winit::platform::x11::EventLoopBuilderExtX11::with_any_thread(&mut builder, true);
    winit::platform::wayland::EventLoopBuilderExtWayland::with_any_thread(&mut builder, true);
    let el = builder.build().map_err(|e| e.to_string())?;
    let proxy = el.create_proxy();
    with_text(|t| t.load_system_fonts());
    let clipboard = arboard::Clipboard::new().ok();
    LOOP.with(|l| *l.borrow_mut() = Some(el));
    APP.with(|a| {
        *a.borrow_mut() = Some(App {
            title: title.to_string(),
            size: (width, height),
            window: None,
            surface: None,
            events: Vec::new(),
            mods: Mods::default(),
            cursor: (0, 0),
            scene: Scene::default(),
            clipboard,
            proxy,
            adapter: None,
            access: None,
        })
    });
    Ok(())
}

/// Events since the last poll, waiting up to `timeout_ms` for the first, or with `u32::MAX`, until
/// there is one.
pub fn poll(timeout_ms: u32) -> Vec<WindowEvent> {
    LOOP.with(|l| {
        APP.with(|a| {
            let (mut l, mut a) = (l.borrow_mut(), a.borrow_mut());
            let (Some(el), Some(app)) = (l.as_mut(), a.as_mut()) else { return vec![WindowEvent::Close] };
            let timeout = (timeout_ms != u32::MAX).then(|| Duration::from_millis(timeout_ms as u64));
            let status = el.pump_app_events(timeout, app);
            // The loop exits when the display connection is lost; the window is gone with it.
            if let PumpStatus::Exit(_) = status {
                app.events.push(WindowEvent::Close);
            }
            std::mem::take(&mut app.events)
        })
    })
}

/// Shows `scene` from now on.
pub fn present(scene: Scene) {
    APP.with(|a| {
        if let Some(app) = a.borrow_mut().as_mut() {
            app.scene = scene;
            app.present();
        }
    })
}

pub fn request(r: Request) {
    APP.with(|a| {
        let mut a = a.borrow_mut();
        let Some(app) = a.as_mut() else { return };
        match r {
            Request::SetTitle(t) => {
                if let Some(w) = &app.window {
                    w.set_title(&t)
                }
            }
            Request::SetClipboard(t) => {
                if let Some(c) = app.clipboard.as_mut() {
                    let _ = c.set_text(t);
                }
            }
            // Lean checked the link; it is passed as one argument, with no shell.
            Request::OpenUri(u) => {
                let _ = std::process::Command::new("xdg-open").arg(u).spawn();
            }
            Request::Notify(title, body) => {
                let _ = std::process::Command::new("notify-send").arg("--").arg(title).arg(body).spawn();
            }
            Request::Quit => {
                app.adapter = None;
                app.window = None;
                app.surface = None;
            }
            Request::Cursor(c) => {
                use winit::window::CursorIcon;
                let icon = match c {
                    1 => CursorIcon::Pointer,
                    2 => CursorIcon::Text,
                    3 => CursorIcon::EwResize,
                    4 => CursorIcon::NsResize,
                    _ => CursorIcon::Default,
                };
                if let Some(w) = &app.window {
                    w.set_cursor(icon);
                }
            }
            Request::Access(focus, nodes) => {
                let tree = crate::access::update(focus, &nodes, app.scale(), &app.title);
                app.access = Some(tree.clone());
                if let Some(a) = app.adapter.as_mut() {
                    a.update_if_active(|| tree);
                }
            }
        }
    })
}

/// The window's size in units, once it is open.
pub fn size() -> (i64, i64) {
    APP.with(|a| {
        let a = a.borrow();
        let Some(app) = a.as_ref() else { return (0, 0) };
        match &app.window {
            Some(w) => {
                let s = w.inner_size();
                let scale = w.scale_factor();
                (units(s.width as f64, scale), units(s.height as f64, scale))
            }
            None => ((app.size.0 as i64) * UNITS as i64, (app.size.1 as i64) * UNITS as i64),
        }
    })
}

/// The last frame shown, as PNG.
pub fn screenshot() -> Vec<u8> {
    APP.with(|a| {
        let a = a.borrow();
        let Some(app) = a.as_ref() else { return vec![] };
        let Some(w) = &app.window else { return vec![] };
        let s = w.inner_size();
        let pm = with_text(|t| render(&app.scene, s.width, s.height, w.scale_factor() as f32, t));
        pm.encode_png().unwrap_or_default()
    })
}
