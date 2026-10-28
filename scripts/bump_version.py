#!/usr/bin/env python3
"""Synchronize project version across pubspec, Dart, C++, RC, Inno Setup, and docs.

Usage:
  python scripts/bump_version.py 1.1.3       # bumps to 1.1.3 and auto-increments +build
  python scripts/bump_version.py 1.1.3+7     # sets exact version 1.1.3 and build 7
  python scripts/bump_version.py             # syncs all files to current pubspec.yaml version
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / "pubspec.yaml"

SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")
PUBSPEC_VER_RE = re.compile(r"(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$")


def read_pubspec_version() -> tuple[str, int]:
    text = PUBSPEC.read_text(encoding="utf-8")
    m = PUBSPEC_VER_RE.search(text)
    if not m:
        raise RuntimeError(f"Cannot find 'version: X.Y.Z+B' in {PUBSPEC}")
    ver = f"{m.group(1)}.{m.group(2)}.{m.group(3)}"
    build = int(m.group(4)) if m.group(4) is not None else 1
    return ver, build


def resolve_target_version(arg: str | None) -> tuple[str, str, int]:
    cur_ver, cur_build = read_pubspec_version()
    if not arg:
        parts = cur_ver.split(".")
        return cur_ver, f"{parts[0]},{parts[1]},{parts[2]},0", cur_build

    m = SEMVER_RE.match(arg.strip())
    if not m:
        raise ValueError(
            f"Invalid version '{arg}'. Expected format: X.Y.Z or X.Y.Z+B (e.g. 1.1.3 or 1.1.3+7)"
        )
    major, minor, patch, build_str = m.groups()
    new_ver = f"{major}.{minor}.{patch}"
    if build_str is not None:
        new_build = int(build_str)
    else:
        new_build = cur_build + 1 if new_ver != cur_ver else cur_build

    csv_ver = f"{major},{minor},{patch},0"
    return new_ver, csv_ver, new_build


def replace_in_file(
    rel_path: str,
    replacements: list[tuple[str, str]],
) -> bool:
    path = ROOT / rel_path
    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig" if has_bom else "utf-8")
    use_crlf = "\r\n" in text
    norm = text.replace("\r\n", "\n")
    orig_norm = norm

    for pattern, repl in replacements:
        new_norm, count = re.subn(pattern, repl, norm, flags=re.MULTILINE)
        if count == 0:
            raise RuntimeError(f"Pattern not matched in {rel_path}: {pattern}")
        norm = new_norm

    if norm == orig_norm:
        return False

    out_text = norm.replace("\n", "\r\n") if use_crlf else norm
    out_bytes = out_text.encode("utf-8-sig" if has_bom else "utf-8")
    path.write_bytes(out_bytes)
    return True


def main() -> int:
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    if arg in ("-h", "--help"):
        print(__doc__.strip())
        return 0

    cur_ver, cur_build = read_pubspec_version()
    ver, csv_ver, build = resolve_target_version(arg)
    full_ver = f"{ver}+{build}"

    targets: list[tuple[str, list[tuple[str, str]]]] = [
        (
            "pubspec.yaml",
            [(r"^version:\s*\d+\.\d+\.\d+(?:\+\d+)?", f"version: {full_ver}")],
        ),
        (
            "lib/app/diag_export.dart",
            [
                (r"^const kAppVersion = '[^']+';", f"const kAppVersion = '{ver}';"),
                (r"^const kHelperVersion = '[^']+';", f"const kHelperVersion = '{ver}';"),
            ],
        ),
        (
            "cpp_core/app/helper_main.cpp",
            [
                (
                    r'^static constexpr char kHelperVersion\[\] = "[^"]+";',
                    f'static constexpr char kHelperVersion[] = "{ver}";',
                ),
            ],
        ),
        (
            "cpp_core/shell/helper.rc",
            [
                (r"^\s*FILEVERSION\s+\d+,\d+,\d+,\d+", f" FILEVERSION {csv_ver}"),
                (r"^\s*PRODUCTVERSION\s+\d+,\d+,\d+,\d+", f" PRODUCTVERSION {csv_ver}"),
                (
                    r'^(\s*VALUE "FileVersion", )"[^"]+"( "\\0")',
                    rf'\g<1>"{ver}"\g<2>',
                ),
                (
                    r'^(\s*VALUE "ProductVersion", )"[^"]+"( "\\0")',
                    rf'\g<1>"{ver}"\g<2>',
                ),
            ],
        ),
        (
            "windows/runner/Runner.rc",
            [
                (
                    r"^#define VERSION_AS_NUMBER \d+,\d+,\d+,\d+",
                    f"#define VERSION_AS_NUMBER {csv_ver}",
                ),
                (
                    r'^#define VERSION_AS_STRING "[^"]+"',
                    f'#define VERSION_AS_STRING "{ver}"',
                ),
            ],
        ),
        (
            "packaging/pack.ps1",
            [(r'^(\s*\$Version = )"[^"]+"', rf'\g<1>"{ver}"')],
        ),
        (
            "packaging/screen_strip_sync.iss",
            [(r'^#define MyAppVersion "[^"]+"', f'#define MyAppVersion "{ver}"')],
        ),
        (
            "dist_installer/README-GitHub.txt",
            [
                (
                    r"ScreenStripSync-\d+\.\d+\.\d+-windows-x64-Setup\.exe",
                    f"ScreenStripSync-{ver}-windows-x64-Setup.exe",
                ),
                (
                    r"ScreenStripSync-\d+\.\d+\.\d+-windows-x64\.zip",
                    f"ScreenStripSync-{ver}-windows-x64.zip",
                ),
            ],
        ),
        (
            ".github/ISSUE_TEMPLATE/bug_report.yml",
            [
                (
                    r'^(\s*placeholder:\s*)"\d+\.\d+\.\d+\+\d+ / helper \d+\.\d+\.\d+"',
                    rf'\g<1>"{full_ver} / helper {ver}"',
                ),
            ],
        ),
    ]

    changed_files: list[str] = []
    for rel_path, rules in targets:
        if replace_in_file(rel_path, rules):
            changed_files.append(rel_path)

    print(f"Version: {cur_ver}+{cur_build} -> {full_ver} (RC: {csv_ver})")
    if changed_files:
        print(f"Updated {len(changed_files)} file(s):")
        for f in changed_files:
            print(f"  - {f}")
    else:
        print(f"All {len(targets)} files are already in sync at {full_ver}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
