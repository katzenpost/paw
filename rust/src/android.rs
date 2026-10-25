// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Android: the entry point, which runs the Lean program in the app's files directory with its
//! output in logcat, and what no crate offers: notifications and the window's insets, through Java.
//!
//! The test hooks of `Paw/Linux.lean` are read from system properties, which `adb shell setprop`
//! sets: `debug.paw.test_log` and `debug.paw.test_layout` name files in the app's files directory,
//! and `debug.paw.theme` and `debug.paw.reduce_motion` stand for `PAW_THEME` and
//! `PAW_REDUCE_MOTION`. `debug.paw.args`, words split at spaces, are the program's arguments.

use jni::objects::{JObject, JValue};
use jni::{JNIEnv, JavaVM};
use std::ffi::{c_char, c_int, CString};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{mpsc, Mutex, OnceLock};
use std::time::Duration;
use winit::platform::android::activity::AndroidApp;

static APP: OnceLock<AndroidApp> = OnceLock::new();

/// The app `android_main` was started with.
pub fn app() -> Option<AndroidApp> {
    APP.get().cloned()
}

extern "C" {
    /// The Lean program's `main`, which Lean emits in C.
    #[link_name = "main"]
    fn lean_main(argc: c_int, argv: *mut *mut c_char) -> c_int;
    fn __system_property_get(name: *const c_char, value: *mut c_char) -> c_int;
}

/// Sends what the program writes to stdout and stderr to logcat, a line at a time.
fn log_stdio() {
    use std::io::BufRead;
    use std::os::fd::FromRawFd;
    let mut fds = [0; 2];
    unsafe {
        if libc::pipe(fds.as_mut_ptr()) != 0 {
            return;
        }
        libc::dup2(fds[1], 1);
        libc::dup2(fds[1], 2);
        libc::close(fds[1]);
    }
    let read = unsafe { std::fs::File::from_raw_fd(fds[0]) };
    std::thread::spawn(move || {
        for line in std::io::BufReader::new(read).lines().map_while(Result::ok) {
            log::info!("{line}");
        }
    });
}

fn property(name: &str) -> Option<String> {
    let name = CString::new(name).ok()?;
    let mut value = [0 as c_char; 92];
    let n = unsafe { __system_property_get(name.as_ptr(), value.as_mut_ptr()) };
    (n > 0).then(|| {
        let bytes: Vec<u8> = value[..n as usize].iter().map(|&c| c as u8).collect();
        String::from_utf8_lossy(&bytes).into_owned()
    })
}

/// A file name that stays in the directory it is joined to.
fn plain_name(s: &str) -> bool {
    !s.is_empty() && s != "." && s != ".." && !s.contains('/')
}

fn test_hooks(files: Option<&std::path::Path>) {
    for (prop, var) in [
        ("debug.paw.test_log", "PAW_TEST_LOG"),
        ("debug.paw.test_layout", "PAW_TEST_LAYOUT"),
    ] {
        if let (Some(dir), Some(v)) = (files, property(prop)) {
            if plain_name(&v) {
                std::env::set_var(var, dir.join(v));
            }
        }
    }
    for (prop, var) in [
        ("debug.paw.theme", "PAW_THEME"),
        ("debug.paw.reduce_motion", "PAW_REDUCE_MOTION"),
    ] {
        if let Some(v) = property(prop) {
            std::env::set_var(var, v);
        }
    }
}

type Job = Box<dyn FnOnce() + Send>;

static JOBS: OnceLock<Mutex<mpsc::Sender<Job>>> = OnceLock::new();

/// Runs `f` on `android_main`'s thread, which owns the window, and returns what it returns.
pub fn on_main<R: Send + 'static>(f: impl FnOnce() -> R + Send + 'static) -> R {
    let (tx, rx) = mpsc::sync_channel(1);
    let job: Job = Box::new(move || {
        let _ = tx.send(f());
    });
    let sent = JOBS
        .get()
        .and_then(|j| j.lock().ok())
        .is_some_and(|j| j.send(job).is_ok());
    assert!(sent, "paw: no android_main to run on");
    rx.recv().expect("android_main ran the job")
}

/// Runs the Lean program, once per process, as its runtime cannot be started twice. Lean runs on a
/// thread of its own, with the stack it asks for; this thread runs what Lean asks of the window and
/// otherwise keeps taking in the system's events.
#[no_mangle]
fn android_main(app: AndroidApp) {
    if APP.set(app.clone()).is_err() {
        return;
    }
    android_logger::init_once(
        android_logger::Config::default()
            .with_tag("paw")
            .with_max_level(log::LevelFilter::Info),
    );
    log_stdio();
    let files = app.internal_data_path();
    if let Some(dir) = &files {
        let _ = std::env::set_current_dir(dir);
        std::env::set_var("HOME", dir);
    }
    test_hooks(files.as_deref());
    keys_to_native();
    let (tx, rx) = mpsc::channel::<Job>();
    let _ = JOBS.set(Mutex::new(tx));
    let args: Vec<CString> = std::iter::once("paw".to_string())
        .chain(property("debug.paw.args").into_iter().flat_map(|a| {
            a.split(' ')
                .filter(|w| !w.is_empty())
                .map(String::from)
                .collect::<Vec<_>>()
        }))
        .filter_map(|a| CString::new(a).ok())
        .collect();
    std::thread::spawn(move || {
        let mut argv: Vec<*mut c_char> = args.iter().map(|a| a.as_ptr() as *mut c_char).collect();
        argv.push(std::ptr::null_mut());
        let code = unsafe { lean_main(args.len() as c_int, argv.as_mut_ptr()) };
        std::process::exit(code);
    });
    loop {
        match rx.recv_timeout(Duration::from_millis(20)) {
            Ok(job) => job(),
            Err(mpsc::RecvTimeoutError::Timeout) => crate::window::idle(),
            Err(mpsc::RecvTimeoutError::Disconnected) => return,
        }
    }
}

/// Runs `f` with the JVM attached to this thread and the activity; `None` if Java threw.
fn with_activity<R>(f: impl FnOnce(&mut JNIEnv, &JObject) -> jni::errors::Result<R>) -> Option<R> {
    let app = APP.get()?;
    let vm = unsafe { JavaVM::from_raw(app.vm_as_ptr().cast()) }.ok()?;
    let mut env = vm.attach_current_thread().ok()?;
    let activity = unsafe { JObject::from_raw(app.activity_as_ptr().cast()) };
    let r = f(&mut env, &activity);
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_describe();
        let _ = env.exception_clear();
    }
    r.ok()
}

/// Sends the keys of a hardware keyboard to native code, where winit reads them with their text.
/// GameTextInput otherwise takes them to edit its buffer itself, and drops and repeats characters
/// that come quickly; it is left the soft keyboard's text, which comes as edits.
fn keys_to_native() {
    with_activity(|env, activity| {
        let view = env
            .get_field(
                activity,
                "mSurfaceView",
                "Lcom/google/androidgamesdk/GameActivity$InputEnabledSurfaceView;",
            )?
            .l()?;
        env.call_method(
            &view,
            "setOnKeyListener",
            "(Landroid/view/View$OnKeyListener;)V",
            &[JValue::Object(&JObject::null())],
        )?;
        Ok(())
    });
}

/// The edges of the window that the system's bars, the display's cutout and the soft keyboard
/// cover, in physical pixels: left, top, right and bottom. GameActivity draws edge to edge.
pub fn insets() -> Option<(u32, u32, u32, u32)> {
    // androidx's WindowInsetsCompat.Type: system bars, the soft keyboard and display cutouts.
    const TYPES: i32 = 0x7 | 0x8 | 0x80;
    with_activity(|env, activity| {
        let insets = env
            .call_method(
                activity,
                "getWindowInsets",
                "(I)Landroidx/core/graphics/Insets;",
                &[JValue::Int(TYPES)],
            )?
            .l()?;
        if insets.is_null() {
            return Ok(None);
        }
        let mut side = |name| -> jni::errors::Result<u32> {
            Ok(env.get_field(&insets, name, "I")?.i()?.max(0) as u32)
        };
        Ok(Some((
            side("left")?,
            side("top")?,
            side("right")?,
            side("bottom")?,
        )))
    })
    .flatten()
}

/// Shows a notification. Without permission to, asks for it, and this one is not shown.
pub fn notify(title: &str, body: &str) {
    static NEXT: AtomicI32 = AtomicI32::new(1);
    with_activity(|env, activity| {
        let perm = env.new_string("android.permission.POST_NOTIFICATIONS")?;
        let granted = env
            .call_method(
                activity,
                "checkSelfPermission",
                "(Ljava/lang/String;)I",
                &[JValue::Object(&perm)],
            )?
            .i()?
            == 0;
        if !granted {
            let perms = env.new_object_array(1, "java/lang/String", &perm)?;
            env.call_method(
                activity,
                "requestPermissions",
                "([Ljava/lang/String;I)V",
                &[JValue::Object(&perms), JValue::Int(1)],
            )?;
            return Ok(());
        }
        let service = env.new_string("notification")?;
        let nm = env
            .call_method(
                activity,
                "getSystemService",
                "(Ljava/lang/String;)Ljava/lang/Object;",
                &[JValue::Object(&service)],
            )?
            .l()?;
        let id = env.new_string("paw")?;
        let name = env.new_string("Notifications")?;
        let channel = env.new_object(
            "android/app/NotificationChannel",
            "(Ljava/lang/String;Ljava/lang/CharSequence;I)V",
            &[JValue::Object(&id), JValue::Object(&name), JValue::Int(3)],
        )?;
        env.call_method(
            &nm,
            "createNotificationChannel",
            "(Landroid/app/NotificationChannel;)V",
            &[JValue::Object(&channel)],
        )?;
        let builder = env.new_object(
            "android/app/Notification$Builder",
            "(Landroid/content/Context;Ljava/lang/String;)V",
            &[JValue::Object(activity), JValue::Object(&id)],
        )?;
        let icon = env
            .get_static_field("android/R$drawable", "ic_dialog_info", "I")?
            .i()?;
        let title = env.new_string(title)?;
        let body = env.new_string(body)?;
        let set = "Landroid/app/Notification$Builder;";
        env.call_method(
            &builder,
            "setSmallIcon",
            format!("(I){set}"),
            &[JValue::Int(icon)],
        )?;
        env.call_method(
            &builder,
            "setContentTitle",
            format!("(Ljava/lang/CharSequence;){set}"),
            &[JValue::Object(&title)],
        )?;
        env.call_method(
            &builder,
            "setContentText",
            format!("(Ljava/lang/CharSequence;){set}"),
            &[JValue::Object(&body)],
        )?;
        let n = env
            .call_method(&builder, "build", "()Landroid/app/Notification;", &[])?
            .l()?;
        let tag = NEXT.fetch_add(1, Ordering::Relaxed);
        env.call_method(
            &nm,
            "notify",
            "(ILandroid/app/Notification;)V",
            &[JValue::Int(tag), JValue::Object(&n)],
        )?;
        Ok(())
    });
}
