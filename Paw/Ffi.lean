/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # The platform layer

Functions implemented in `rust/src/lib.rs`. Data crosses as byte arrays that Lean encodes and
decodes. -/

namespace Paw.Ffi

/-- The version of the byte formats this library speaks. -/
def abiVersion : UInt32 := 1

@[extern "paw_abi_version"] opaque rustAbiVersion : Unit → UInt32

/-- Whether the linked Rust layer speaks the same byte formats. -/
def abiMatches : Bool := rustAbiVersion () == abiVersion

/-- The Rust layer decodes a scene and encodes it again; empty if it does not decode. -/
@[extern "paw_scene_echo"] opaque sceneEcho : @& ByteArray → ByteArray

/-- The Rust layer decodes a request and encodes it again; empty if it does not decode. -/
@[extern "paw_request_echo"] opaque requestEcho : @& ByteArray → ByteArray

/-- One of each kind of window event, as the Rust layer encodes them. -/
@[extern "paw_sample_events"] opaque sampleEvents : Unit → ByteArray

/-- The width and height of a line of text, in units, from its size, boldness and text, encoded. -/
@[extern "paw_measure"] opaque measureRaw : @& ByteArray → ByteArray

/-- A scene drawn offscreen at `scaleMilli`/1000 pixels per logical pixel, as PNG. -/
@[extern "paw_render_png"] opaque renderPng : @& ByteArray → UInt32 → UInt32 → UInt32 → ByteArray

@[extern "paw_window_open"] opaque windowOpen : @& String → UInt32 → UInt32 → IO Unit
@[extern "paw_window_poll"] opaque windowPoll : UInt32 → IO ByteArray
@[extern "paw_window_present"] opaque windowPresent : @& ByteArray → IO Unit
@[extern "paw_window_request"] opaque windowRequest : @& ByteArray → IO Unit
@[extern "paw_window_size"] opaque windowSize : IO ByteArray
/-- The last frame shown, as PNG. -/
@[extern "paw_window_screenshot"] opaque windowScreenshot : IO ByteArray
/-- Milliseconds since the platform layer started. -/
@[extern "paw_now"] opaque now : IO Nat

end Paw.Ffi

