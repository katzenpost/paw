# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only

# Rust comes from rustup and Lean from elan.
export PATH := $(HOME)/.cargo/bin:$(HOME)/.elan/bin:$(PATH)

.PHONY: demo all ci build test test-lean test-rust coverage check goldens goldens-update e2e e2e-x11 e2e-wayland e2e-atspi bench bench-lean bench-rust

all: test coverage goldens

# Everything CI runs.
ci: all check e2e

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

e2e: e2e-x11 e2e-wayland e2e-atspi

e2e-x11:
	lake build paw-gallery
	sh tests/e2e/x11.sh

e2e-wayland:
	lake build paw-gallery
	cd rust && cargo build --quiet --release --example vpointer
	sh tests/e2e/wayland.sh

# Benchmarks take a while; run one suite with e.g. `make bench-lean BENCH_ARGS="--where 'suite(tree)'"`.
BENCH_ARGS ?=

bench: bench-lean bench-rust

bench-lean:
	lake build paw-bench
	.lake/build/bin/paw-bench $(BENCH_ARGS)

bench-rust:
	cd rust && cargo run --quiet --release --example bench

e2e-atspi:
	lake build paw-gallery
	sh tests/e2e/atspi.sh

# The gallery example in a window.
demo:
	lake build paw-gallery
	.lake/build/bin/paw-gallery
