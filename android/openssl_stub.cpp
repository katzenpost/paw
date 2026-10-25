// SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
// SPDX-License-Identifier: AGPL-3.0-only

// Lean's runtime without OpenSSL, which it uses only to report OpenSSL's version.

#include <lean/lean.h>

namespace lean {
void initialize_openssl() {}
void finalize_openssl() {}
}

extern "C" LEAN_EXPORT lean_obj_res lean_openssl_version(lean_obj_arg) { return lean_box(0); }
