#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only

"""Writes the Java libraries of deps.lock: GameActivity, AppCompat and everything they need, from
their Maven POMs. Where two libraries ask for different versions of a third, the highest is taken,
as Gradle does. Run it after changing ROOTS, then look at what changed in deps.lock."""

import hashlib
import os
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

ROOTS = [
    ("androidx.games", "games-activity", "4.4.0"),
    ("androidx.appcompat", "appcompat", "1.7.1"),
]
REPOS = ["https://dl.google.com/android/maven2", "https://repo1.maven.org/maven2"]
LOCK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "deps.lock")
MARK = "# Java libraries, written by lock.py:"


def get(url):
    try:
        with urllib.request.urlopen(url) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def path(g, a, v, ext):
    return f"{g.replace('.', '/')}/{a}/{v}/{a}-{v}.{ext}"


def find(g, a, v, ext):
    for repo in REPOS:
        url = f"{repo}/{path(g, a, v, ext)}"
        data = get(url)
        if data is not None:
            return url, data
    return None, None


def key(v):
    return [int(p) if p.isdigit() else -1 for p in re.split(r"[.-]", v)]


def pom(g, a, v):
    _, data = find(g, a, v, "pom")
    if data is None:
        sys.exit(f"no POM for {g}:{a}:{v}")
    root = ET.fromstring(data)
    ns = {"m": root.tag[1:].split("}")[0]} if root.tag.startswith("{") else {"m": ""}
    q = (lambda t: f"m:{t}") if ns["m"] else (lambda t: t)
    packaging = root.findtext(q("packaging"), "jar", ns)
    deps = []
    for d in root.findall(f"{q('dependencies')}/{q('dependency')}", ns):
        scope = d.findtext(q("scope"), "compile", ns)
        if scope not in ("compile", "runtime") or d.findtext(q("optional"), "false", ns) == "true":
            continue
        dv = d.findtext(q("version"), "", ns).strip("[]()").split(",")[0]
        deps.append((d.findtext(q("groupId"), "", ns), d.findtext(q("artifactId"), "", ns), dv))
    return packaging, deps


def main():
    chosen = {(g, a): v for g, a, v in ROOTS}
    seen = {}
    while True:
        changed = False
        for (g, a), v in list(chosen.items()):
            if seen.get((g, a)) == v:
                continue
            seen[(g, a)] = v
            _, deps = pom(g, a, v)
            for dg, da, dv in deps:
                old = chosen.get((dg, da))
                if old is None or key(dv) > key(old):
                    chosen[(dg, da)] = dv
                    changed = True
        # Kotlin's jdk7 and jdk8 parts moved into its stdlib; they follow its version, as Gradle's
        # module metadata asks, so no class is in two jars.
        stdlib = chosen.get(("org.jetbrains.kotlin", "kotlin-stdlib"))
        for part in ("kotlin-stdlib-jdk7", "kotlin-stdlib-jdk8"):
            if stdlib and ("org.jetbrains.kotlin", part) in chosen and chosen[("org.jetbrains.kotlin", part)] != stdlib:
                chosen[("org.jetbrains.kotlin", part)] = stdlib
                changed = True
        if not changed and all(seen.get(k) == v for k, v in chosen.items()):
            break
    lines = []
    for (g, a), v in sorted(chosen.items()):
        packaging, _ = pom(g, a, v)
        ext = "aar" if packaging == "aar" else "jar"
        url, data = find(g, a, v, ext)
        if data is None:
            # A multiplatform library's root has no artifact of its own; its JVM part is a dependency.
            continue
        lines.append(f"{g}:{a}:{v}.{ext} {url} {hashlib.sha256(data).hexdigest()}")
    text = open(LOCK).read()
    text = text.split(MARK)[0].rstrip("\n") + f"\n\n{MARK}\n" + "\n".join(lines) + "\n"
    open(LOCK, "w").write(text)
    print(f"{len(lines)} libraries")


if __name__ == "__main__":
    main()
