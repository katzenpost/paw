/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Gallery
import Paw.Linux

/-! The gallery in a window. With `PAW_TEST_LOG` set, each step's model is logged for the
end-to-end tests. -/

def describe (m : Gallery.Model) : String :=
  s!"count={m.count} name={m.name} agree={m.agree} items={m.items.map (·.2)} opened={m.opened} \
    dialog={m.clearing.isSome} picture={m.picture.isSome} \
    notes={m.notes.replace "\n" "|"}"

def main : IO Unit := Paw.Linux.run Gallery.app "Paw gallery" 640 560 describe
