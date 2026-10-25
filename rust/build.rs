// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

use std::process::Command;

/// `cargo test` links Lean's shared runtime; find it at run time too. An Android build links its
/// own runtime into the app's library instead.
fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        return;
    }
    let out = Command::new("lean")
        .arg("--print-prefix")
        .output()
        .expect("lean on PATH");
    let prefix = String::from_utf8(out.stdout).expect("UTF-8 path");
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}/lib/lean", prefix.trim());
}
