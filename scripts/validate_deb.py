#!/usr/bin/env python3
"""Validate a RootHide WeidianGrab deb without extracting or executing it.

Usage:
  python3 scripts/validate_deb.py packages/com.koudai.weidian.grab_0.9.5_iphoneos-arm64e.deb --output manifest.json
  python3 scripts/validate_deb.py dist7/com.koudai.weidian.grab_0.4.2_iphoneos-arm64e.deb --version 0.4.2

Only the Python standard library is required. All archive contents stay in memory.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import posixpath
import plistlib
import re
import struct
import sys
import tarfile
from pathlib import Path
from typing import Any

PACKAGE = "com.koudai.weidian.grab"
NAME = "WeidianGrab"
ARCHITECTURE = "iphoneos-arm64e"
BUNDLE = "com.koudai.weidian.buyer"
LIBRARY = "Library/MobileSubstrate/DynamicLibraries/WeidianGrab.dylib"
FILTER = "Library/MobileSubstrate/DynamicLibraries/WeidianGrab.plist"
PATCH_TARGET = "/usr/lib/DynamicPatches/AutoPatches.dylib"
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
MAX_MEMBER_BYTES = 64 * 1024 * 1024
MAX_MEMBERS = 4096
CPU_TYPE_ARM64 = 0x0100000C
DYLIB_COMMANDS = {
    0x0C: "LC_LOAD_DYLIB",
    0x0D: "LC_ID_DYLIB",
    0x18: "LC_LOAD_WEAK_DYLIB",
    0x1F: "LC_REEXPORT_DYLIB",
    0x20: "LC_LAZY_LOAD_DYLIB",
    0x23: "LC_LOAD_UPWARD_DYLIB",
}


class ValidationError(ValueError):
    """The artifact does not meet the declared package contract."""


def require(condition: Any, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unpack(fmt: str, data: bytes, offset: int, end: int | None = None) -> tuple:
    size = struct.calcsize(fmt)
    limit = len(data) if end is None else min(len(data), end)
    require(0 <= offset <= limit - size, f"truncated structure at offset {offset}")
    return struct.unpack_from(fmt, data, offset)


def read_ar(data: bytes) -> dict[str, bytes]:
    require(len(data) <= MAX_ARCHIVE_BYTES, "deb exceeds the archive size limit")
    require(data.startswith(b"!<arch>\n"), "invalid ar signature")
    members: dict[str, bytes] = {}
    offset = 8
    while offset < len(data):
        require(offset + 60 <= len(data), "truncated ar header")
        header = data[offset:offset + 60]
        require(header[58:60] == b"`\n", "invalid ar member header")
        try:
            name = header[:16].decode("ascii").strip().removesuffix("/")
            size = int(header[48:58].decode("ascii").strip())
        except (UnicodeError, ValueError) as error:
            raise ValidationError("invalid ar member name or size") from error
        require(name and "/" not in name and "\\" not in name, "unsupported ar member name")
        require(name not in members, f"duplicate ar member: {name}")
        offset += 60
        require(0 <= size <= MAX_ARCHIVE_BYTES and offset + size <= len(data), f"truncated ar member: {name}")
        members[name] = data[offset:offset + size]
        offset += size
        if size & 1:
            require(offset < len(data) and data[offset:offset + 1] == b"\n", "invalid ar padding")
            offset += 1
    require(members.get("debian-binary") == b"2.0\n", "missing Debian archive version 2.0")
    require(len(members) == 3, "expected only debian-binary, control.tar.*, and data.tar.*")
    return members


def canonical_name(name: str) -> str:
    require("\\" not in name and "\0" not in name and not name.startswith("/"), f"unsafe archive path: {name!r}")
    require(".." not in name.split("/"), f"parent traversal in archive path: {name!r}")
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def read_tar(data: bytes, label: str) -> dict[str, tuple[tarfile.TarInfo, bytes]]:
    members: dict[str, tuple[tarfile.TarInfo, bytes]] = {}
    total = 0
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
            for index, member in enumerate(archive):
                require(index < MAX_MEMBERS, f"too many {label} members")
                require(0 <= member.size <= MAX_MEMBER_BYTES, f"oversized {label} member: {member.name}")
                total += member.size
                require(total <= MAX_ARCHIVE_BYTES, f"{label} exceeds the unpacked size limit")
                name = canonical_name(member.name)
                if name in ("", ".") and member.isdir():
                    continue
                require(name and name not in members, f"duplicate or empty {label} path: {name}")
                require(member.isfile() or member.isdir() or member.issym(), f"unsupported {label} entry: {name}")
                payload = b""
                if member.isfile():
                    stream = archive.extractfile(member)
                    require(stream is not None, f"missing payload: {name}")
                    payload = stream.read(MAX_MEMBER_BYTES + 1)
                    require(len(payload) == member.size, f"truncated payload: {name}")
                members[name] = (member, payload)
    except (tarfile.TarError, EOFError, OSError) as error:
        raise ValidationError(f"invalid or unsupported {label} archive: {error}") from error
    return members


def regular_file(members: dict, name: str) -> bytes:
    require(name in members and members[name][0].isfile(), f"missing regular file: {name}")
    return members[name][1]


def parse_control(data: bytes) -> dict[str, str]:
    require(b"\r" not in data, "control must use Unix LF line endings")
    text = data.decode("utf-8")
    fields: dict[str, str] = {}
    previous = None
    for line in text.splitlines():
        if not line:
            continue
        if line[0].isspace():
            require(previous is not None, "orphan control continuation")
            fields[previous] += "\n" + line.strip()
            continue
        require(":" in line, f"malformed control line: {line!r}")
        key, value = line.split(":", 1)
        require(key not in fields and re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", key), f"invalid or duplicate control field: {key}")
        fields[key] = value.strip()
        previous = key
    return fields


def parse_filter(data: bytes) -> dict:
    """Accept XML/binary plist or the small, strict OpenStep plist grammar."""
    try:
        result = plistlib.loads(data)
        require(isinstance(result, dict), "filter plist must be a dictionary")
        return result
    except plistlib.InvalidFileException:
        pass
    text = data.decode("utf-8-sig")
    tokens: list[str] = []
    token_pattern = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[A-Za-z0-9_./:+@-]+', re.S)
    position = 0
    while position < len(text):
        match = token_pattern.match(text, position)
        require(match is not None, f"invalid OpenStep token at offset {position}")
        token = match.group()
        position = match.end()
        if token.isspace() or token.startswith(("//", "/*")):
            continue
        tokens.append(token)
        require(len(tokens) <= 4096, "filter plist is too complex")
    cursor = 0

    def take(expected: str | None = None) -> str:
        nonlocal cursor
        require(cursor < len(tokens), "truncated OpenStep plist")
        token = tokens[cursor]
        cursor += 1
        require(expected is None or token == expected, f"expected {expected!r}, got {token!r}")
        return token

    def scalar() -> str:
        token = take()
        require(token not in "{}()=;,", "expected OpenStep string")
        return json.loads(token) if token.startswith('"') else token

    def value(depth: int = 0) -> Any:
        require(depth < 16 and cursor < len(tokens), "filter plist depth limit or truncation")
        if tokens[cursor] == "{":
            take("{")
            result: dict[str, Any] = {}
            while cursor < len(tokens) and tokens[cursor] != "}":
                key = scalar()
                require(key not in result, f"duplicate filter key: {key}")
                take("=")
                result[key] = value(depth + 1)
                take(";")
            take("}")
            return result
        if tokens[cursor] == "(":
            take("(")
            result_list = []
            while cursor < len(tokens) and tokens[cursor] != ")":
                result_list.append(value(depth + 1))
                if cursor < len(tokens) and tokens[cursor] == ",":
                    take(",")
                else:
                    break
            take(")")
            return result_list
        return scalar()

    result = value()
    require(cursor == len(tokens) and isinstance(result, dict), "trailing data or non-dictionary filter plist")
    return result


def version_string(packed: int) -> str:
    return f"{packed >> 16}.{(packed >> 8) & 255}.{packed & 255}"


def normalized_version(value: str) -> str:
    parts = value.split(".")
    require(1 <= len(parts) <= 3 and all(p.isdigit() for p in parts), f"invalid numeric version: {value}")
    return ".".join(str(int(p)) for p in parts + ["0"] * (3 - len(parts)))


def command_string(data: bytes, start: int, size: int) -> str:
    relative, = unpack("<I", data, start + 8, start + size)
    require(12 <= relative < size, "invalid load-command string offset")
    payload = data[start + relative:start + size]
    require(b"\0" in payload, "unterminated load-command string")
    return payload.split(b"\0", 1)[0].decode("utf-8")


def check_link_path(path: str, kind: str, warnings: list[str]) -> None:
    require(path and "\0" not in path and "\\" not in path, f"invalid {kind} path")
    require(not re.search(r"\.jbroot-[^/]+", path), f"hardcoded randomized jbroot in {kind}: {path}")
    require(not path.startswith(("/var/jb", "/private/var/jb")), f"rootless prefix in RootHide {kind}: {path}")
    require(".." not in path.split("/"), f"parent traversal in {kind}: {path}")
    roothide = "@loader_path/.jbroot/"
    if kind == "LC_ID_DYLIB":
        require(path == roothide + LIBRARY, f"unexpected RootHide dylib identity: {path}")
    elif kind == "LC_RPATH":
        require(path.startswith((roothide, "/System/Library/", "/usr/lib/")), f"unexpected RootHide rpath: {path}")
    elif path.startswith(roothide):
        logical = path[len(roothide):]
        require(logical.startswith(("usr/lib/", "Library/Frameworks/")), f"unexpected RootHide dependency: {path}")
        if "CydiaSubstrate.framework/" in logical:
            warnings.append(f"RootHide CydiaSubstrate framework compatibility dependency: {path}; runtime availability is not established here")
        if logical.startswith("usr/lib/") and "substrate" in logical.lower():
            require(logical == "usr/lib/libsubstrate.dylib", f"unexpected substrate dependency: {path}")
    else:
        require(path.startswith(("/System/Library/", "/usr/lib/")), f"non-system rootful or unresolved dependency: {path}")
        require(path != "/usr/lib/libsubstrate.dylib" and "CydiaSubstrate.framework/" not in path, f"rootful substrate dependency: {path}")


def inspect_slice(data: bytes, cpu: int, subtype: int, warnings: list[str]) -> dict:
    require(data[:4] == b"\xcf\xfa\xed\xfe", "expected little-endian 64-bit Mach-O")
    _, inner_cpu, inner_subtype, filetype, count, commands_size, _, _ = unpack("<IiiIIIII", data, 0)
    require(inner_cpu == cpu == CPU_TYPE_ARM64 and (inner_subtype & 0xFFFFFFFF) == subtype, "fat header and Mach-O CPU mismatch")
    require(filetype == 6, "expected MH_DYLIB")
    require(0 < count <= 4096 and 32 + commands_size <= len(data), "invalid Mach-O load-command region")
    architecture = {0: "arm64", 2: "arm64e"}.get(subtype & 0x00FFFFFF)
    require(architecture is not None, f"unexpected ARM64 CPU subtype: {subtype:#x}")
    result: dict[str, Any] = {"architecture": architecture, "cpu_subtype": f"0x{subtype:08x}", "sha256": sha256(data), "bytes": len(data), "load_commands": [], "rpaths": [], "initializers": []}
    versions = []
    identities = []
    offset = 32
    end = 32 + commands_size
    for _ in range(count):
        command, size = unpack("<II", data, offset, end)
        require(size >= 8 and size % 8 == 0 and offset + size <= end, "invalid Mach-O command size")
        base = command & 0x7FFFFFFF
        if base in DYLIB_COMMANDS:
            require(size >= 24, "truncated dylib command")
            path = command_string(data, offset, size)
            kind = DYLIB_COMMANDS[base]
            check_link_path(path, kind, warnings)
            result["load_commands"].append({"command": kind, "path": path})
            if base == 0x0D:
                identities.append(path)
        elif base == 0x1C:
            path = command_string(data, offset, size)
            check_link_path(path, "LC_RPATH", warnings)
            result["rpaths"].append(path)
        elif command == 0x32:
            platform, minimum, sdk, tools = unpack("<IIII", data, offset + 8, offset + size)
            require(platform == 2 and 24 + tools * 8 <= size, "expected iOS build-version command")
            versions.append((version_string(minimum), version_string(sdk)))
        elif command == 0x25:
            minimum, sdk = unpack("<II", data, offset + 8, offset + size)
            versions.append((version_string(minimum), version_string(sdk)))
        elif command == 0x19:
            require(size >= 72, "truncated segment command")
            sections, = unpack("<I", data, offset + 64, offset + size)
            require(72 + sections * 80 <= size, "truncated Mach-O section table")
            for index in range(sections):
                section_offset = offset + 72 + index * 80
                section = data[section_offset:section_offset + 16].split(b"\0", 1)[0].decode("ascii")
                if section in ("__init_offsets", "__mod_init_func", "__objc_nlclslist"):
                    section_size, = unpack("<Q", data, section_offset + 40, offset + size)
                    result["initializers"].append({"section": section, "bytes": section_size})
        elif command in (0x80000034, 0x80000022):
            result.setdefault("fixup_commands", []).append("LC_DYLD_CHAINED_FIXUPS" if command == 0x80000034 else "LC_DYLD_INFO_ONLY")
        offset += size
    require(offset == end, "Mach-O command count/size mismatch")
    require(len(identities) == 1, "expected exactly one RootHide dylib identity")
    require(len(versions) == 1, "expected one unambiguous iOS deployment-version command")
    result["minimum_ios"], result["sdk"] = versions[0]
    require(result["minimum_ios"] == "15.0.0", f"{architecture} deployment target must be 15.0.0")
    return result


def inspect_macho(data: bytes, warnings: list[str], expected_sdk: str | None) -> list[dict]:
    require(len(data) >= 8, "truncated Mach-O file")
    magic, count = unpack(">II", data, 0)
    require(magic in (0xCAFEBABE, 0xCAFEBABF) and count == 2, "expected fat Mach-O with exactly arm64 and arm64e slices")
    entry_size = 20 if magic == 0xCAFEBABE else 32
    table_end = 8 + count * entry_size
    require(table_end <= len(data), "truncated fat architecture table")
    result = []
    spans = []
    for index in range(count):
        entry = 8 + index * entry_size
        if entry_size == 20:
            cpu, subtype, offset, size, alignment = unpack(">IIIII", data, entry)
        else:
            cpu, subtype, offset, size, alignment, reserved = unpack(">IIQQII", data, entry)
            require(reserved == 0, "unexpected fat64 reserved value")
        require(alignment <= 30 and offset % (1 << alignment) == 0, "invalid fat slice alignment")
        require(offset >= table_end and size > 0 and offset + size <= len(data), "invalid fat slice range")
        require(all(offset + size <= low or offset >= high for low, high in spans), "overlapping fat slices")
        spans.append((offset, offset + size))
        result.append(inspect_slice(data[offset:offset + size], cpu, subtype, warnings))
    require({item["architecture"] for item in result} == {"arm64", "arm64e"}, "missing or duplicate arm64/arm64e slice")
    if expected_sdk is not None:
        expected = normalized_version(expected_sdk)
        require(all(item["sdk"] == expected for item in result), f"Mach-O SDK differs from pinned SDK {expected}")
    return result


def script_record(name: str, info: tarfile.TarInfo, data: bytes, warnings: list[str]) -> dict:
    require(info.isfile() and info.mode & 0o111, f"script must be a regular executable file: {name}")
    require(data.startswith(b"#!") and b"\r" not in data and b"\0" not in data, f"script must have a Unix shebang and LF line endings: {name}")
    data.decode("utf-8")
    if not data.endswith(b"\n"):
        warnings.append(f"script lacks a final LF (accepted for historical artifacts): {name}")
    return {"mode": f"{info.mode & 0o7777:04o}", "sha256": sha256(data), "bytes": len(data), "line_endings": "LF", "final_lf": data.endswith(b"\n")}


def validate_package(data: bytes, version: str = "0.9.5", expected_sdk: str | None = None) -> dict:
    warnings: list[str] = []
    require(re.fullmatch(r"[A-Za-z0-9.+:~_-]+", version), "invalid expected package version")
    ar = read_ar(data)
    control_names = [name for name in ar if name.startswith("control.tar")]
    data_names = [name for name in ar if name.startswith("data.tar")]
    require(len(control_names) == len(data_names) == 1, "missing or duplicate control/data tar archive")
    control = read_tar(ar[control_names[0]], "control")
    payload = read_tar(ar[data_names[0]], "data")
    fields = parse_control(regular_file(control, "control"))
    for key, expected in {"Package": PACKAGE, "Name": NAME, "Version": version, "Architecture": ARCHITECTURE}.items():
        require(fields.get(key) == expected, f"control {key}: expected {expected!r}, got {fields.get(key)!r}")
    dylib = regular_file(payload, LIBRARY)
    filter_bytes = regular_file(payload, FILTER)
    filter_value = parse_filter(filter_bytes)
    require(filter_value == {"Filter": {"Bundles": [BUNDLE]}}, "filter must target only com.koudai.weidian.buyer, with no extra selectors")
    slices = inspect_macho(dylib, warnings, expected_sdk)
    scripts = {}
    require("postinst" in control, "missing postinst")
    for name in ("preinst", "postinst", "prerm", "postrm", "config"):
        if name in control:
            info, script = control[name]
            scripts["DEBIAN/" + name] = script_record(name, info, script, warnings)
    for name, (info, content) in payload.items():
        if info.isfile() and (name.endswith(".sh") or content.startswith(b"#!")):
            scripts[name] = script_record(name, info, content, warnings)
    patches = []
    for name, (info, _) in payload.items():
        if not name.endswith(".roothidepatch"):
            continue
        require(name == LIBRARY + ".roothidepatch" and info.issym(), f"roothidepatch must be the expected symlink, never a regular copy: {name}")
        target = info.linkname
        require("\\" not in target and "\0" not in target, "invalid roothidepatch target")
        logical = posixpath.normpath(target if target.startswith("/") else posixpath.join("/" + posixpath.dirname(name), target))
        require(logical == PATCH_TARGET, f"unexpected roothidepatch target: {target}")
        patches.append({"path": name, "target": target, "resolved_logical_target": logical})
    return {
        "schema_version": 1,
        "status": "valid",
        "package": {"bytes": len(data), "sha256": sha256(data), "control": fields},
        "archives": {name: {"bytes": len(content), "sha256": sha256(content)} for name, content in ar.items()},
        "dylib": {"path": LIBRARY, "sha256": sha256(dylib), "bytes": len(dylib), "slices": slices},
        "filter": {"path": FILTER, "sha256": sha256(filter_bytes), "value": filter_value},
        "scripts": scripts,
        "roothidepatch_entries": patches,
        "warnings": sorted(set(warnings)),
        "runtime_validation": "not performed; no extraction, code execution, installation, or network requests",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deb", type=Path)
    parser.add_argument("--version", default="0.9.5", help="exact expected Debian Version (default: 0.9.5)")
    parser.add_argument("--expected-sdk", help="optional actual Mach-O SDK version; not the SDK directory label")
    parser.add_argument("--toolchain", type=Path, help="CI toolchain evidence JSON to embed in the manifest")
    parser.add_argument("--output", type=Path, help="also save the JSON manifest; stdout always receives JSON")
    args = parser.parse_args(argv)
    report: dict[str, Any] = {"schema_version": 1, "status": "invalid"}
    exit_code = 1
    try:
        require(args.deb.stat().st_size <= MAX_ARCHIVE_BYTES, "deb exceeds the archive size limit")
        data = args.deb.read_bytes()
        report["package"] = {"path": str(args.deb), "bytes": len(data), "sha256": sha256(data)}
        validated = validate_package(data, args.version, args.expected_sdk)
        if args.toolchain is not None:
            toolchain = json.loads(args.toolchain.read_text(encoding="utf-8"))
            require(isinstance(toolchain, dict), "toolchain evidence must be a JSON object")
            validated["toolchain"] = toolchain
        report = validated
        report["package"]["path"] = str(args.deb)
        exit_code = 0
    except (ValidationError, OSError, ValueError, UnicodeError, struct.error, OverflowError, RecursionError) as error:
        report["status"] = "invalid"
        report["errors"] = [str(error)]
    report["checked_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    text = json.dumps(report, ensure_ascii=True, indent=2, sort_keys=True) + "\n"
    if args.output is not None:
        args.output.write_text(text, encoding="utf-8", newline="\n")
    sys.stdout.write(text)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
