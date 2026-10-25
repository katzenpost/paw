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
use crate::touch::{Phase, Touch};
use std::cell::RefCell;
use std::num::NonZeroU32;
use std::rc::Rc;
use std::sync::{Mutex, OnceLock};
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

/// What other threads send the loop: AccessKit's requests, and a nudge to stop waiting.
pub enum UserEvent {
    Access(accesskit_winit::Event),
    Wake,
}

impl From<accesskit_winit::Event> for UserEvent {
    fn from(e: accesskit_winit::Event) -> Self {
        UserEvent::Access(e)
    }
}

/// The loop's proxy, for `wake` from any thread.
static WAKER: OnceLock<Mutex<EventLoopProxy<UserEvent>>> = OnceLock::new();

/// Makes a poll waiting on the loop return, from any thread; nothing before the window opens.
pub fn wake() {
    if let Some(p) = WAKER.get() {
        if let Ok(p) = p.lock() {
            let _ = p.send_event(UserEvent::Wake);
        }
    }
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
    clipboard: Clipboard,
    touch: Touch,
    /// What the soft keyboard has typed, on Android, where it edits a buffer of its own.
    #[cfg(target_os = "android")]
    typed: crate::textinput::TextInput,
    ime: bool,
    proxy: EventLoopProxy<UserEvent>,
    adapter: Option<accesskit_winit::Adapter>,
    /// The last accessibility tree from Lean, for a screen reader that asks for it.
    access: Option<accesskit::TreeUpdate>,
}

thread_local! {
    static LOOP: RefCell<Option<EventLoop<UserEvent>>> = const { RefCell::new(None) };
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

/// The system clipboard, read only when the user pastes.
#[cfg(not(target_os = "android"))]
struct Clipboard(Option<arboard::Clipboard>);

#[cfg(not(target_os = "android"))]
impl Clipboard {
    fn new() -> Clipboard {
        Clipboard(arboard::Clipboard::new().ok())
    }
    fn get(&mut self) -> Option<String> {
        self.0.as_mut().and_then(|c| c.get_text().ok())
    }
    fn set(&mut self, t: String) {
        if let Some(c) = self.0.as_mut() {
            let _ = c.set_text(t);
        }
    }
}

#[cfg(target_os = "android")]
struct Clipboard;

#[cfg(target_os = "android")]
impl Clipboard {
    fn new() -> Clipboard {
        Clipboard
    }
    fn get(&mut self) -> Option<String> {
        crate::android::clipboard()
    }
    fn set(&mut self, t: String) {
        crate::android::set_clipboard(&t)
    }
}

fn units(v: f64, scale: f64) -> i64 {
    (v / scale * UNITS as f64).round() as i64
}

fn key_of(k: &WKey) -> Option<Key> {
    Some(match k {
        WKey::Named(n) => match n {
            NamedKey::Enter => Key::Enter,
            NamedKey::Escape | NamedKey::GoBack | NamedKey::BrowserBack => Key::Escape,
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
        self.window
            .as_ref()
            .map(|w| w.scale_factor())
            .unwrap_or(1.0)
    }

    fn input(&mut self, kind: InputKind) {
        self.events.push(WindowEvent::Input(Input {
            kind,
            time: now(),
            synthetic: false,
            obscured: false,
        }));
    }

    fn present(&mut self) {
        let (Some(window), Some(surface)) = (self.window.as_ref(), self.surface.as_mut()) else {
            return;
        };
        let size = window.inner_size();
        let (Some(w), Some(h)) = (NonZeroU32::new(size.width), NonZeroU32::new(size.height)) else {
            return;
        };
        let scale = window.scale_factor() as f32;
        let pm = with_text(|t| render(&self.scene, w.get(), h.get(), scale, t));
        if surface.resize(w, h).is_err() {
            return;
        }
        let Ok(mut buf) = surface.buffer_mut() else {
            return;
        };
        for (dst, p) in buf.iter_mut().zip(pm.pixels()) {
            *dst = ((p.red() as u32) << 16) | ((p.green() as u32) << 8) | p.blue() as u32;
        }
        let _ = buf.present();
    }
}

impl ApplicationHandler<UserEvent> for App {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        // Android takes the surface away while the app is in the background.
        if let Some(window) = self.window.clone() {
            if self.surface.is_none() {
                self.surface = surface(&window);
                let s = window.inner_size();
                let scale = window.scale_factor();
                self.events.push(WindowEvent::Resize(
                    units(s.width as f64, scale),
                    units(s.height as f64, scale),
                ));
                window.request_redraw();
            }
            return;
        }
        // AccessKit must be attached before the window is first shown.
        let attrs = Window::default_attributes()
            .with_title(self.title.clone())
            .with_inner_size(LogicalSize::new(self.size.0, self.size.1))
            .with_visible(false);
        let Ok(window) = el.create_window(attrs) else {
            return;
        };
        self.adapter = Some(accesskit_winit::Adapter::with_event_loop_proxy(
            el,
            &window,
            self.proxy.clone(),
        ));
        window.set_visible(true);
        let window = Rc::new(window);
        self.surface = surface(&window);
        let s = window.inner_size();
        let scale = window.scale_factor();
        self.events.push(WindowEvent::Resize(
            units(s.width as f64, scale),
            units(s.height as f64, scale),
        ));
        self.window = Some(window);
    }

    fn suspended(&mut self, _el: &ActiveEventLoop) {
        self.surface = None;
    }

    fn user_event(&mut self, _el: &ActiveEventLoop, event: UserEvent) {
        use accesskit_winit::WindowEvent as Ak;
        // A wake has done its work by ending the wait.
        let UserEvent::Access(event) = event else {
            return;
        };
        match event.window_event {
            Ak::InitialTreeRequested => {
                let tree = self
                    .access
                    .clone()
                    .unwrap_or_else(|| crate::access::empty(&self.title));
                if let Some(a) = self.adapter.as_mut() {
                    a.update_if_active(|| tree);
                }
            }
            Ak::ActionRequested(req) => {
                let action = match req.action {
                    accesskit::Action::Click => 0,
                    accesskit::Action::Focus => 1,
                    accesskit::Action::Increment => 2,
                    accesskit::Action::Decrement => 3,
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
            WE::Resized(s) => self.events.push(WindowEvent::Resize(
                units(s.width as f64, scale),
                units(s.height as f64, scale),
            )),
            WE::RedrawRequested => self.present(),
            WE::Focused(f) => self.events.push(WindowEvent::Focus(f)),
            WE::Ime(ime) => match ime {
                winit::event::Ime::Preedit(s, cursor) => {
                    let c = cursor
                        .map(|(a, _)| s[..a.min(s.len())].chars().count())
                        .unwrap_or(s.chars().count());
                    self.input(InputKind::Preedit(s, c as u64));
                }
                winit::event::Ime::Commit(s) => self.input(InputKind::Text(s)),
                winit::event::Ime::Disabled => self.input(InputKind::Preedit(String::new(), 0)),
                winit::event::Ime::Enabled => {}
            },
            WE::Occluded(o) => self.events.push(WindowEvent::Visible(!o)),
            WE::ModifiersChanged(m) => {
                let s = m.state();
                self.mods = Mods {
                    shift: s.shift_key(),
                    ctrl: s.control_key(),
                    alt: s.alt_key(),
                    sup: s.super_key(),
                };
            }
            WE::CursorMoved { position, .. } => {
                self.cursor = (units(position.x, scale), units(position.y, scale));
                self.input(InputKind::Move(self.cursor.0, self.cursor.1));
            }
            WE::CursorLeft { .. } => self.input(InputKind::LeaveWindow),
            WE::Touch(t) => {
                let phase = match t.phase {
                    winit::event::TouchPhase::Started => Phase::Started,
                    winit::event::TouchPhase::Moved => Phase::Moved,
                    winit::event::TouchPhase::Ended => Phase::Ended,
                    winit::event::TouchPhase::Cancelled => Phase::Cancelled,
                };
                let (x, y) = (units(t.location.x, scale), units(t.location.y, scale));
                for kind in self.touch.event(t.id, phase, x, y) {
                    if let InputKind::Move(x, y) = kind {
                        self.cursor = (x, y);
                    }
                    self.input(kind);
                }
            }
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
                    MouseScrollDelta::PixelDelta(p) => {
                        (-(p.x / 40.0).round() as i64, -(p.y / 40.0).round() as i64)
                    }
                };
                if dx != 0 || dy != 0 {
                    let (x, y) = self.cursor;
                    self.input(InputKind::Wheel(x, y, dx, dy));
                }
            }
            WE::KeyboardInput {
                event,
                is_synthetic,
                ..
            } => {
                // Keys winit reports as held when focus arrives were not pressed in this window.
                if is_synthetic {
                    return;
                }
                let pressed = event.state == ElementState::Pressed;
                let m = self.mods;
                let Some(k) = key_of(&event.logical_key) else {
                    return;
                };
                if pressed && m.ctrl && !m.alt && k == Key::Char('v') {
                    let text = self.clipboard.get().unwrap_or_default();
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
    let mut builder = EventLoop::<UserEvent>::with_user_event();
    #[cfg(not(target_os = "android"))]
    {
        winit::platform::x11::EventLoopBuilderExtX11::with_any_thread(&mut builder, true);
        winit::platform::wayland::EventLoopBuilderExtWayland::with_any_thread(&mut builder, true);
    }
    #[cfg(target_os = "android")]
    {
        use winit::platform::android::EventLoopBuilderExtAndroid;
        let app = crate::android::app().ok_or("paw: not started by android_main")?;
        builder.with_android_app(app);
    }
    let el = builder.build().map_err(|e| e.to_string())?;
    let proxy = el.create_proxy();
    match WAKER.get() {
        Some(w) => {
            if let Ok(mut w) = w.lock() {
                *w = proxy.clone();
            }
        }
        None => {
            let _ = WAKER.set(Mutex::new(proxy.clone()));
        }
    }
    with_text(|t| t.load_system_fonts());
    let clipboard = Clipboard::new();
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
            touch: Touch::default(),
            #[cfg(target_os = "android")]
            typed: Default::default(),
            ime: false,
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
            let (Some(el), Some(app)) = (l.as_mut(), a.as_mut()) else {
                return vec![WindowEvent::Close];
            };
            let timeout =
                (timeout_ms != u32::MAX).then(|| Duration::from_millis(timeout_ms as u64));
            let status = el.pump_app_events(timeout, app);
            // The loop exits when the display connection is lost; the window is gone with it.
            if let PumpStatus::Exit(_) = status {
                app.events.push(WindowEvent::Close);
            }
            #[cfg(target_os = "android")]
            app.read_typed();
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
            Request::SetClipboard(t) => app.clipboard.set(t),
            Request::OpenUri(u) => open_uri(&u),
            Request::Notify(title, body) => notify(&title, &body),
            Request::Quit => {
                app.adapter = None;
                app.window = None;
                app.surface = None;
            }
            Request::Ime(area) => {
                if area.is_some() != app.ime {
                    app.ime = area.is_some();
                    #[cfg(target_os = "android")]
                    app.start_typing();
                }
                if let Some(w) = &app.window {
                    w.set_ime_allowed(area.is_some());
                    if let Some(r) = area {
                        let s = app.scale();
                        let p = |u: i64| u as f64 / crate::render::UNITS as f64 * s;
                        w.set_ime_cursor_area(
                            winit::dpi::PhysicalPosition::new(p(r.x0), p(r.y0)),
                            winit::dpi::PhysicalSize::new(
                                p(r.x1 - r.x0).max(1.0),
                                p(r.y1 - r.y0).max(1.0),
                            ),
                        );
                    }
                }
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
            None => (
                (app.size.0 as i64) * UNITS as i64,
                (app.size.1 as i64) * UNITS as i64,
            ),
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

fn surface(window: &Rc<Window>) -> Option<softbuffer::Surface<Rc<Window>, Rc<Window>>> {
    let ctx = softbuffer::Context::new(window.clone()).ok()?;
    softbuffer::Surface::new(&ctx, window.clone()).ok()
}

// Lean checked the link; it is passed as one argument, with no shell.
#[cfg(not(target_os = "android"))]
fn open_uri(u: &str) {
    let _ = std::process::Command::new("xdg-open").arg(u).spawn();
}

#[cfg(not(target_os = "android"))]
fn notify(title: &str, body: &str) {
    let _ = std::process::Command::new("notify-send")
        .arg("--")
        .arg(title)
        .arg(body)
        .spawn();
}

#[cfg(target_os = "android")]
use crate::android::{notify, open_uri};

#[cfg(target_os = "android")]
impl App {
    /// Empties the soft keyboard's buffer for a field that starts taking text, and asks for a
    /// keyboard whose Enter types a newline, which is passed on as the Enter key.
    fn start_typing(&mut self) {
        use winit::platform::android::activity::input::{
            ImeOptions, InputType, TextInputAction, TextInputState, TextSpan,
        };
        let Some(a) = crate::android::app() else {
            return;
        };
        self.typed.reset();
        a.set_text_input_state(TextInputState {
            text: String::new(),
            selection: TextSpan { start: 0, end: 0 },
            compose_region: None,
        });
        if self.ime {
            a.set_ime_editor_info(
                InputType::TYPE_CLASS_TEXT | InputType::TYPE_TEXT_FLAG_MULTI_LINE,
                TextInputAction::None,
                ImeOptions::IME_FLAG_NO_FULLSCREEN,
            );
        }
    }

    /// What the soft keyboard typed since the last poll.
    fn read_typed(&mut self) {
        if !self.ime {
            return;
        }
        let Some(a) = crate::android::app() else {
            return;
        };
        let state = a.text_input_state();
        let compose = state.compose_region.map(|r| (r.start, r.end));
        for kind in self.typed.update(&state.text, compose) {
            self.input(kind);
        }
    }
}
