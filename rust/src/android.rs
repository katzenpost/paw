// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

//! Android: the entry point, which runs the Lean program in the app's files directory with its
//! output in logcat, and the clipboard, links and notifications through Java.
//!
//! The test hooks of `Paw/Linux.lean` are read from system properties, which `adb shell setprop`
//! sets: `debug.paw.test_log` and `debug.paw.test_layout` name files in the app's files directory,
//! and `debug.paw.theme` and `debug.paw.reduce_motion` stand for `PAW_THEME` and
//! `PAW_REDUCE_MOTION`.

use jni::objects::{JObject, JString, JValue};
use jni::{JNIEnv, JavaVM};
use std::ffi::{c_char, c_int, CString};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::OnceLock;
use winit::platform::android::activity::AndroidApp;

static APP: OnceLock<AndroidApp> = OnceLock::new();

/// The app `android_main` was started with.
pub fn app() -> Option<AndroidApp> {
    APP.get().cloned()
}

#[link(name = "log")]
extern "C" {
    fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
}

extern "C" {
    /// The Lean program's `main`, which Lean emits in C.
    #[link_name = "main"]
    fn lean_main(argc: c_int, argv: *mut *mut c_char) -> c_int;
    fn __system_property_get(name: *const c_char, value: *mut c_char) -> c_int;
}

fn log(s: &str) {
    let text = CString::new(s.replace('\0', "")).unwrap_or_default();
    unsafe { __android_log_write(4, c"paw".as_ptr(), text.as_ptr()) };
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
            log(&line);
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

/// Runs the Lean program, once per process: its runtime cannot be started twice.
#[no_mangle]
fn android_main(app: AndroidApp) {
    if APP.set(app.clone()).is_err() {
        return;
    }
    log_stdio();
    let files = app.internal_data_path();
    if let Some(dir) = &files {
        let _ = std::env::set_current_dir(dir);
        std::env::set_var("HOME", dir);
    }
    test_hooks(files.as_deref());
    let name = c"paw".as_ptr() as *mut c_char;
    let mut argv = [name, std::ptr::null_mut()];
    let code = unsafe { lean_main(1, argv.as_mut_ptr()) };
    std::process::exit(code);
}

/// Runs `f` with the JVM attached to this thread and the activity; `None` if Java threw.
fn with_activity<R>(f: impl FnOnce(&mut JNIEnv, &JObject) -> jni::errors::Result<R>) -> Option<R> {
    let app = APP.get()?;
    let vm = unsafe { JavaVM::from_raw(app.vm_as_ptr() as *mut _) }.ok()?;
    let mut env = vm.attach_current_thread().ok()?;
    let activity = unsafe { JObject::from_raw(app.activity_as_ptr() as jni::sys::jobject) };
    let r = f(&mut env, &activity);
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_describe();
        let _ = env.exception_clear();
    }
    r.ok()
}

fn service<'a>(
    env: &mut JNIEnv<'a>,
    activity: &JObject,
    name: &str,
) -> jni::errors::Result<JObject<'a>> {
    let name = env.new_string(name)?;
    env.call_method(
        activity,
        "getSystemService",
        "(Ljava/lang/String;)Ljava/lang/Object;",
        &[JValue::Object(&name)],
    )?
    .l()
}

pub fn set_clipboard(text: &str) {
    with_activity(|env, activity| {
        let cm = service(env, activity, "clipboard")?;
        let label = env.new_string("")?;
        let text = env.new_string(text)?;
        let clip = env
            .call_static_method(
                "android/content/ClipData",
                "newPlainText",
                "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;",
                &[JValue::Object(&label), JValue::Object(&text)],
            )?
            .l()?;
        env.call_method(
            &cm,
            "setPrimaryClip",
            "(Landroid/content/ClipData;)V",
            &[JValue::Object(&clip)],
        )?;
        Ok(())
    });
}

pub fn clipboard() -> Option<String> {
    with_activity(|env, activity| {
        let cm = service(env, activity, "clipboard")?;
        let clip = env
            .call_method(&cm, "getPrimaryClip", "()Landroid/content/ClipData;", &[])?
            .l()?;
        if clip.is_null() {
            return Ok(None);
        }
        let item = env
            .call_method(
                &clip,
                "getItemAt",
                "(I)Landroid/content/ClipData$Item;",
                &[JValue::Int(0)],
            )?
            .l()?;
        let text = env
            .call_method(
                &item,
                "coerceToText",
                "(Landroid/content/Context;)Ljava/lang/CharSequence;",
                &[JValue::Object(activity)],
            )?
            .l()?;
        let s = env
            .call_method(&text, "toString", "()Ljava/lang/String;", &[])?
            .l()?;
        Ok(Some(env.get_string(&JString::from(s))?.into()))
    })
    .flatten()
}

/// Opens a link Lean checked, in the app the system picks for it.
pub fn open_uri(uri: &str) {
    with_activity(|env, activity| {
        let s = env.new_string(uri)?;
        let uri = env
            .call_static_method(
                "android/net/Uri",
                "parse",
                "(Ljava/lang/String;)Landroid/net/Uri;",
                &[JValue::Object(&s)],
            )?
            .l()?;
        let action = env.new_string("android.intent.action.VIEW")?;
        let intent = env.new_object(
            "android/content/Intent",
            "(Ljava/lang/String;Landroid/net/Uri;)V",
            &[JValue::Object(&action), JValue::Object(&uri)],
        )?;
        env.call_method(
            activity,
            "startActivity",
            "(Landroid/content/Intent;)V",
            &[JValue::Object(&intent)],
        )?;
        Ok(())
    });
}

const CHANNEL: &str = "paw";
const NOTIFY_PERMISSION: &str = "android.permission.POST_NOTIFICATIONS";

/// Shows a notification. Without permission to, asks for it, and this one is not shown.
pub fn notify(title: &str, body: &str) {
    static NEXT: AtomicI32 = AtomicI32::new(1);
    with_activity(|env, activity| {
        let perm = env.new_string(NOTIFY_PERMISSION)?;
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
        let nm = service(env, activity, "notification")?;
        let id = env.new_string(CHANNEL)?;
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
        env.call_method(
            &builder,
            "setSmallIcon",
            "(I)Landroid/app/Notification$Builder;",
            &[JValue::Int(icon)],
        )?;
        env.call_method(
            &builder,
            "setContentTitle",
            "(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;",
            &[JValue::Object(&title)],
        )?;
        env.call_method(
            &builder,
            "setContentText",
            "(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;",
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
