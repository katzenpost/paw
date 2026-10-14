# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only

# Rust comes from rustup and Lean from elan.
export PATH := $(HOME)/.cargo/bin:$(HOME)/.elan/bin:$(PATH)

.PHONY: all build test test-lean test-rust coverage check goldens goldens-update

all: test coverage goldens

build:
	lake build

test: test-rust test-lean

test-lean:
	lake build paw-test
	.lake/build/bin/paw-test

test-rust:
	cd rust && cargo test --quiet

coverage:
	lake build Paw paw-test paw-coverage
	lake exe paw-coverage

check:
	cd rust && cargo clippy --quiet -- -D warnings

goldens:
	lake build paw-goldens
	.lake/build/bin/paw-goldens

# Look at every image this writes before committing it.
goldens-update:
	lake build paw-goldens
	.lake/build/bin/paw-goldens --update
