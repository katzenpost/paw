#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only

# Builds a Paw app as an Android APK: Lean's runtime, the C Lean emits for the app and every module
# it imports, and the Rust and C code of its packages, linked into one libmain.so that GameActivity
# loads.
#
#   APP   the app's Lake package (default: this repository)
#   EXE   its executable target (default: paw-gallery)
#   ROOT  the executable's root module (default: GalleryMain)
#   NAME  the app's Android package name (default: org.katzenpost.paw.gallery)
#   LABEL the app's name on the launcher (default: Paw gallery)
#   PERMISSIONS    Android permissions the app asks for besides the network and notifications,
#                  such as RECORD_AUDIO, separated by spaces (default: none)
#   VERSION_NAME   the version shown to users (default: 0.1.0)
#   VERSION_CODE   the version Android compares, which an update must not lower (default: 1)
#   ANDROID_ABI    x86_64 or arm64-v8a (default: x86_64)
#   ANDROID_HOME   the Android SDK (default: ~/Android/Sdk), with its newest NDK and build-tools
#   ANDROID_NDK_HOME, BUILD_TOOLS, ANDROID_JAR   the NDK, the build-tools' directory and the
#                  platform's android.jar, in place of the newest
#   KEYSTORE, KEYSTORE_PASS, KEY_ALIAS   the key to sign with (default: the debug key, made when
#                  there is none); with KEYSTORE=none the APK is left unsigned
#   SOURCE_DATE_EPOCH   when set, the time of every file the APK holds, so that a build can be
#                  repeated to the same bytes
#
# Needs cargo-ndk (`cargo install cargo-ndk`) and the Rust targets of the ABI
# (`rustup target add x86_64-linux-android aarch64-linux-android`).
#
# A package's native code is found by convention: a Rust crate in rust/, C files in c/.

set -eu

PAW=$(cd "$(dirname "$0")/.." && pwd)
APP=$(cd "${APP:-$PAW}" && pwd)
EXE=${EXE:-paw-gallery}
ROOT=${ROOT:-GalleryMain}
NAME=${NAME:-org.katzenpost.paw.gallery}
LABEL=${LABEL:-Paw gallery}
PERMISSIONS=${PERMISSIONS:-}
VERSION_NAME=${VERSION_NAME:-0.1.0}
VERSION_CODE=${VERSION_CODE:-1}
ABI=${ANDROID_ABI:-x86_64}
API=28
JOBS=${JOBS:-$(nproc)}

case $ABI in
  x86_64) TRIPLE=x86_64-linux-android ;;
  arm64-v8a) TRIPLE=aarch64-linux-android ;;
  *) echo "unknown ABI $ABI" >&2; exit 1 ;;
esac

SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
NDK=${ANDROID_NDK_HOME:-$(ls -d "$SDK"/ndk/* | sort -V | tail -1)}
LLVM=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
CC="$LLVM/clang --target=$TRIPLE$API"
CXX="$LLVM/clang++ --target=$TRIPLE$API"

LEAN_PREFIX=$(cd "$APP" && lean --print-prefix)
LEAN_VERSION=$(cd "$APP" && lean --version | sed 's/.*version \([^,]*\),.*/\1/')
LEAN_INCLUDE=$LEAN_PREFIX/include

WORK=$APP/.lake/android
SRC=$WORK/src
# By Lean version, so that a runtime built for another is never reused.
OUT=$WORK/$ABI/lean-$LEAN_VERSION
mkdir -p "$SRC" "$OUT"

say() { echo "== $*"; }

command -v cargo-ndk >/dev/null || { echo "cargo-ndk is needed: cargo install cargo-ndk" >&2; exit 1; }

# Downloads and unpacks a pinned source from deps.lock, checking its SHA-256.
fetch() {
  line=$(grep "^$1 " "$PAW/android/deps.lock") || { echo "$1 is not in deps.lock" >&2; exit 1; }
  url=$(echo "$line" | cut -d' ' -f2)
  sum=$(echo "$line" | cut -d' ' -f3)
  file=$SRC/$1.${url##*.}
  [ "${url%.tar.gz}" != "$url" ] && file=$SRC/$1.tar.gz
  if [ ! -f "$file" ]; then
    curl -fsSL -o "$file.part" "$url"
    echo "$sum  $file.part" | sha256sum -c --quiet - || { rm -f "$file.part"; exit 1; }
    mv "$file.part" "$file"
  fi
  case $file in
    *.tar.gz)
      if [ ! -d "$SRC/$1" ]; then
        mkdir -p "$SRC/$1.tmp"
        tar -xzf "$file" -C "$SRC/$1.tmp" --strip-components=1
        mv "$SRC/$1.tmp" "$SRC/$1"
      fi
      echo "$SRC/$1" ;;
    *) echo "$file" ;;
  esac
}

# Lean's sources, and the flags of its src/CMakeLists.txt for a release build of its C++, without
# GMP or OpenSSL.
lean_sources() {
  lean=$(fetch "lean-$LEAN_VERSION")
  mimalloc=$(fetch mimalloc-3.4.5)
  uv=$(fetch libuv-1.48.0)
  mkdir -p "$OUT/rt"
  printf '#define LEAN_GITHASH "%s"\n' "$(cd "$APP" && lean --githash)" > "$OUT/rt/githash.h"
  CXX_FLAGS="-std=c++20 -O3 -DNDEBUG -fPIC -DLEAN_EXPORTING -DLEAN_BUILD_TYPE=\"Release\" -D__CLANG__"
  CXX_FLAGS="$CXX_FLAGS -DLEAN_MULTI_THREAD -DLEAN_MMAP -pthread -ffp-contract=off"
  CXX_FLAGS="$CXX_FLAGS -I$lean/src -I$OUT/rt -I$LEAN_INCLUDE -I$uv/include -w"
  # Lean defines free_sized itself, which Android's headers declare only from API 37.
  CXX_FLAGS="$CXX_FLAGS -D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__"
  export CXX CXX_FLAGS
}

# Compiles C++ files, one a line on stdin, into objects in directory $1.
compile_cpp() {
  mkdir -p "$1"
  O=$1 xargs -P"$JOBS" -n1 sh -c 'o=$O/$(echo "$0" | md5sum | cut -c1-12).o; $CXX $CXX_FLAGS -c "$0" -o "$o"'
}

lean_runtime() {
  [ -f "$OUT/libleanrt.a" ] && [ -f "$OUT/libuv.a" ] && return
  say "Lean $LEAN_VERSION runtime for $ABI"
  lean_sources
  cmake -S "$uv" -B "$OUT/uv" -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" -DCMAKE_BUILD_TYPE=Release \
    -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_SHARED=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -Wno-dev >/dev/null
  make -s -C "$OUT/uv" -j"$JOBS" uv_a >/dev/null
  cp "$OUT/uv/libuv.a" "$OUT/libuv.a"
  for f in "$lean"/src/runtime/*.cpp "$lean"/src/runtime/uv/*.cpp "$PAW/android/openssl_stub.cpp"; do
    case $f in */runtime/openssl.cpp | */runtime/mimalloc.cpp) continue ;; esac
    echo "$f"
  done | compile_cpp "$OUT/rt"
  # All of mimalloc with the runtime's small-object allocator, which inlines its fast path, with
  # the flags of Lean's src/runtime/CMakeLists.txt. Not its local-exec TLS: libmain.so is a shared
  # library.
  $CXX $CXX_FLAGS -DMI_SHARED_LIB -DMI_SHARED_LIB_EXPORT -DMI_WIN_NOREDIRECT -DMI_MAX_ALIGN_SIZE=8 \
    -DMI_SECURE=0 -Wno-unused-function -I"$mimalloc/include" -I"$mimalloc/src" \
    -c "$lean/src/runtime/mimalloc.cpp" -o "$OUT/rt/mimalloc.o"
  rm -f "$OUT/libleanrt.a"
  "$LLVM/llvm-ar" rcs "$OUT/libleanrt.a" "$OUT"/rt/*.o
}

# The C file Lake wrote for module $1, from the app or one of its packages.
lake_c() {
  rel=$(echo "$1" | tr . /).c
  for d in "$APP" "$APP"/.lake/packages/*; do
    [ -f "$d/.lake/build/ir/$rel" ] && { echo "$d/.lake/build/ir/$rel"; return; }
  done
  return 1
}

# Every module the executable's root imports, with the C file of each: Lake's for the app and its
# packages, and C from `lean -c` for the toolchain's own modules, which ship only compiled.
# Adds the modules $todo names, and all they import, to $OUT/modules.
add_modules() {
  while [ -n "$todo" ]; do
    next=""
    for m in $todo; do
      case $seen in *" $m "*) continue ;; esac
      seen="$seen$m "
      if c=$(lake_c "$m"); then
        :
      else
        # The toolchain's own modules; Lake's, which Mathlib's import graph tools import, sit in
        # their own source root.
        case $m in
          Init|Init.*|Std|Std.*|Lean|Lean.*) root=$LEAN_PREFIX/src/lean ;;
          Lake|Lake.*) root=$LEAN_PREFIX/src/lean/lake ;;
          *) echo "no C for module $m" >&2; exit 1 ;;
        esac
        c=$stdc/$m.c
        if [ ! -f "$c" ]; then
          (cd "$root" && lean --root=. -c "$c.tmp" "$(echo "$m" | tr . /).lean" >/dev/null)
          mv "$c.tmp" "$c"
        fi
      fi
      echo "$m $c" >> "$OUT/modules"
      imports=$(sed -n '3s|^// Imports:||p' "$c" | tr ' ' '\n' | grep -v -x -e '' -e public -e meta -e import -e all -e private || true)
      next="$next $imports"
    done
    todo=$next
  done
}

lean_c() {
  say "Lean C of $ROOT and its imports"
  (cd "$APP" && lake build "$EXE" >/dev/null)
  stdc=$WORK/lean-$LEAN_VERSION/c
  mkdir -p "$stdc"
  : > "$OUT/modules"
  seen=" "
  todo=$ROOT
  add_modules
  # Lean's C++ calls into the whole of the Lean and Std libraries, as they are built into Lean.
  if grep -q '^Lean[ .]' "$OUT/modules"; then
    todo="Lean Std"
    add_modules
  fi
  echo "$(wc -l < "$OUT/modules") modules"
}

# Lean's kernel and the rest of its C++, which the `Lean` package calls, for apps that import it:
# the sources of Lean's src/CMakeLists.txt's leancpp.
lean_cpp() {
  grep -q '^Lean[ .]' "$OUT/modules" || return 0
  [ -f "$OUT/libleancpp.a" ] && return
  say "Lean's C++ for $ABI"
  lean_sources
  mkdir -p "$OUT/cpp"
  # Its flags for compiling C, which mean nothing on Android.
  sed 's/@[A-Z_]*@//g' "$lean/src/util/ffi.cpp" > "$OUT/cpp/ffi.cpp"
  for d in util kernel library library/constructions initialize; do
    sed -n '/add_library/,/)/p' "$lean/src/$d/CMakeLists.txt" | grep -o '[A-Za-z_]*\.cpp' |
      while read -r f; do
        if [ "$d/$f" = util/ffi.cpp ]; then echo "$OUT/cpp/ffi.cpp"; else echo "$lean/src/$d/$f"; fi
      done
  done | compile_cpp "$OUT/cpp"
  rm -f "$OUT/libleancpp.a"
  "$LLVM/llvm-ar" rcs "$OUT/libleancpp.a" "$OUT"/cpp/*.o
}

compile_lean_c() {
  say "compiling Lean C for $ABI"
  mkdir -p "$OUT/lean"
  C_FLAGS="-O3 -fPIC -ffp-contract=off -fdata-sections -ffunction-sections -w -I$LEAN_INCLUDE"
  export CC C_FLAGS OUT
  xargs -P"$JOBS" -L1 sh -c 'o=$OUT/lean/$0.o; [ "$o" -nt "$1" ] || $CC $C_FLAGS -c "$1" -o "$o"' < "$OUT/modules"
}

# The packages' Rust crates and C files, for Android.
native_code() {
  say "Rust and C of the packages for $ABI"
  mkdir -p "$OUT/c"
  : > "$OUT/libs"
  # Each crate's static library carries Rust's std, so all are built by the rustc Paw's crate
  # pins, or the link finds std twice.
  RUSTUP_TOOLCHAIN=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$PAW/rust/rust-toolchain.toml")
  export RUSTUP_TOOLCHAIN
  for d in "$APP" "$APP"/.lake/packages/*; do
    if [ -f "$d/rust/Cargo.toml" ]; then
      (cd "$d/rust" && ANDROID_NDK_HOME=$NDK cargo ndk -t "$ABI" --platform $API build --release --quiet)
      for a in "$d/rust/target/$TRIPLE/release/"*.a; do
        [ -f "$a" ] && echo "$(basename "$d") $a" >> "$OUT/libs"
      done
    fi
    for f in "$d"/c/*.c; do
      [ -f "$f" ] || continue
      o=$OUT/c/$(basename "$d")-$(basename "$f" .c).o
      $CC -O2 -fPIC -I"$LEAN_INCLUDE" -c "$f" -o "$o"
    done
  done
}

link() {
  say "linking libmain.so for $ABI"
  paw_lib=$(grep '/libpaw_ffi\.a$' "$OUT/libs" | head -1 | cut -d' ' -f2)
  other_libs=$(grep -v '/libpaw_ffi\.a$' "$OUT/libs" | cut -d' ' -f2 | tr '\n' ' ')
  mkdir -p "$OUT/apk/lib/$ABI"
  # GameActivity's entry points, which Java looks up by name; they reach android_main.
  entry=$("$LLVM/llvm-nm" -g --defined-only "$paw_lib" 2>/dev/null |
    awk '$2 == "T" && ($3 ~ /^Java_/ || $3 ~ /^GameActivity_onCreate/) { printf "-Wl,-u,%s ", $3 }')
  # Android's system libraries; AAudio for crates that play or record sound, needed only by them.
  # Only the entry points are exported, so unused code can be dropped.
  { echo "{ global: android_main; GameActivity_onCreate*; Java_*; local: *; };"; } > "$OUT/exports.map"
  # shellcheck disable=SC2086
  $CXX -shared -o "$OUT/libmain.so" -Wl,-soname,libmain.so $entry -Wl,--version-script,"$OUT/exports.map" \
    "$OUT"/lean/*.o $(ls "$OUT"/c/*.o 2>/dev/null) \
    -Wl,--start-group "$paw_lib" $other_libs $(ls "$OUT/libleancpp.a" 2>/dev/null) "$OUT/libleanrt.a" \
    "$OUT/libuv.a" -Wl,--end-group \
    -static-libstdc++ -llog -landroid -lm -ldl -Wl,--as-needed -laaudio -Wl,--no-as-needed \
    -Wl,--gc-sections -Wl,--no-undefined -Wl,-z,max-page-size=16384
  "$LLVM/llvm-strip" --strip-debug -o "$OUT/apk/lib/$ABI/libmain.so" "$OUT/libmain.so"
  ls -la "$OUT/apk/lib/$ABI/libmain.so"
}

# The Java libraries of deps.lock, each checked against its SHA-256.
java_libs() {
  mkdir -p "$SRC/java"
  sed -n '/^# Java libraries/,$p' "$PAW/android/deps.lock" | grep -v '^#' | while read -r name url sum; do
    file=$SRC/java/$name
    if [ ! -f "$file" ]; then
      curl -fsSL -o "$file.part" "$url"
      echo "$sum  $file.part" | sha256sum -c --quiet - || { rm -f "$file.part"; exit 1; }
      mv "$file.part" "$file"
    fi
    echo "$file"
  done
}

apk() {
  say "packaging $NAME for $ABI"
  BT=${BUILD_TOOLS:-$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)}
  JAR=${ANDROID_JAR:-$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)/android.jar}
  A=$OUT/apk
  rm -rf "$A/res" "$A/gen" "$A/classes" "$A/dex" "$A/jars"
  mkdir -p "$A/res" "$A/gen" "$A/classes" "$A/dex" "$A/jars"
  packages=""
  for f in $(java_libs); do
    base=$(basename "$f")
    case $f in
      *.aar)
        d=$SRC/aar/${base%.aar}
        if [ ! -d "$d" ]; then
          mkdir -p "$d.tmp" && unzip -q -o "$f" -d "$d.tmp" && mv "$d.tmp" "$d"
        fi
        [ -f "$d/classes.jar" ] && cp "$d/classes.jar" "$A/jars/$base.jar"
        for j in "$d"/libs/*.jar; do [ -f "$j" ] && cp "$j" "$A/jars/$base-$(basename "$j")"; done
        if [ -d "$d/res" ] && [ -n "$(ls -A "$d/res")" ]; then
          "$BT/aapt2" compile --dir "$d/res" -o "$A/res/$base.zip"
        fi
        pkg=$(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$d/AndroidManifest.xml" | head -1)
        packages="$packages${packages:+:}$pkg" ;;
      *.jar) cp "$f" "$A/jars/$base" ;;
    esac
  done
  uses=$(for p in $PERMISSIONS; do printf '<uses-permission android:name="android.permission.%s" />' "$p"; done)
  sed -e "s|@NAME@|$NAME|" -e "s|@LABEL@|$LABEL|" -e "s|@PERMISSIONS@|$uses|" \
    "$PAW/android/AndroidManifest.xml" > "$A/AndroidManifest.xml"
  # shellcheck disable=SC2046
  "$BT/aapt2" link -I "$JAR" --manifest "$A/AndroidManifest.xml" -o "$A/base.apk" \
    --min-sdk-version $API --target-sdk-version 34 --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
    --auto-add-overlay --extra-packages "$packages" --java "$A/gen" $(for r in "$A"/res/*.zip; do echo -R "$r"; done)
  javac -nowarn --release 11 -cp "$JAR" -d "$A/classes" $(find "$A/gen" -name '*.java')
  # shellcheck disable=SC2046
  "$BT/d8" --release --min-api $API --lib "$JAR" --output "$A/dex" \
    $(find "$A/classes" -name '*.class') "$A"/jars/*.jar
  cp "$A/base.apk" "$A/unsigned.apk"
  if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    find "$A/dex" "$A/lib" -type f -exec touch -d "@$SOURCE_DATE_EPOCH" {} +
  fi
  (cd "$A/dex" && zip -q -X "$A/unsigned.apk" classes*.dex)
  # Stored, so the library is loaded straight from the APK.
  (cd "$A" && zip -q -X -0 "$A/unsigned.apk" "lib/$ABI/libmain.so")
  "$BT/zipalign" -f -P 16 4 "$A/unsigned.apk" "$A/aligned.apk"
  if [ "${KEYSTORE:-}" = none ]; then
    cp "$A/aligned.apk" "$WORK/$EXE-$ABI-unsigned.apk"
    ls -la "$WORK/$EXE-$ABI-unsigned.apk"
    return
  fi
  # Without a key given, the debug key, which Android's tools make when a machine first needs one.
  if [ -z "${KEYSTORE:-}" ]; then
    KEYSTORE=$HOME/.android/debug.keystore KEYSTORE_PASS=android KEY_ALIAS=androiddebugkey
    if [ ! -f "$KEYSTORE" ]; then
      mkdir -p "$HOME/.android"
      keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android \
        -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
    fi
  fi
  export KEYSTORE_PASS
  "$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass env:KEYSTORE_PASS \
    --ks-key-alias "$KEY_ALIAS" --out "$WORK/$EXE-$ABI.apk" "$A/aligned.apk"
  ls -la "$WORK/$EXE-$ABI.apk"
}

lean_runtime
lean_c
lean_cpp
compile_lean_c
native_code
link
apk
