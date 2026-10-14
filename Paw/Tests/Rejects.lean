/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Style

/-! # Programs that must not compile

Each example breaks a law a type carries, and each fails to compile with the error shown. -/

namespace Paw.Tests.Rejects

open Paw

/-- The light theme with gray text, 2.4:1 on its background. -/
def unreadable : ThemeData := { Theme.lightData with text := Theme.gray 0xA0 }

/-- The light theme with a button that looks the same focused as not. -/
def noFocusRing : ThemeData := { Theme.lightData with button.focus := {} }

/-- The light theme with a chosen row too dark for its muted text. -/
def mutedOnSelection : ThemeData := { Theme.lightData with selection := Theme.gray 0xA0 }

/-- The light theme with a flat button whose caption cannot be read on a panel. -/
def faintFlat : ThemeData := { Theme.lightData with flatButton.basic.fg := Theme.gray 0xC0 }

/--
error: Tactic `decide` proved that the proposition
  mutedOnSelection.readable = true
is false
-/
#guard_msgs in
example : Theme := { mutedOnSelection with contrast_ok := by decide +kernel, focus_visible := by decide +kernel }

/--
error: Tactic `decide` proved that the proposition
  faintFlat.readable = true
is false
-/
#guard_msgs in
example : Theme := { faintFlat with contrast_ok := by decide +kernel, focus_visible := by decide +kernel }

/--
error: Tactic `decide` proved that the proposition
  unreadable.readable = true
is false
-/
#guard_msgs in
example : Theme := { unreadable with contrast_ok := by decide +kernel, focus_visible := by decide +kernel }

/--
error: Tactic `decide` proved that the proposition
  noFocusRing.focusVisible = true
is false
-/
#guard_msgs in
example : Theme := { noFocusRing with contrast_ok := by decide +kernel, focus_visible := by decide +kernel }

end Paw.Tests.Rejects
