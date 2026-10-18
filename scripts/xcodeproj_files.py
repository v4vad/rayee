#!/usr/bin/env python3
"""Add, remove or rename Swift files in the Rayee app target.

project.pbxproj lists the app's source files by hand, so a new or deleted file in
swift/Rayee/Rayee/ must also be added to or removed from it. This edits only the
project file; create, delete or `git mv` the .swift file yourself.

Usage (file names only, no folders):
  python3 scripts/xcodeproj_files.py add NewFile.swift [More.swift ...]
  python3 scripts/xcodeproj_files.py remove OldFile.swift [...]
  python3 scripts/xcodeproj_files.py rename Old.swift New.swift
Set PBXPROJ=/path/to/project.pbxproj to work on a copy.
"""
import os
import pathlib
import re
import sys

PBX = pathlib.Path(os.environ.get("PBXPROJ") or
                   pathlib.Path(__file__).resolve().parent.parent / "swift/Rayee/Rayee.xcodeproj/project.pbxproj")

# Lines that every app source file has; new entries go right after UpdateManager's.
GROUP_ANCHOR = "\t\t\t\tA1000520000 /* UpdateManager.swift */,\n"
SOURCES_ANCHOR = "\t\t\t\tA1000520001 /* UpdateManager.swift in Sources */,\n"


def fail(message):
    sys.exit(f"xcodeproj_files: {message}")


def insert_once(text, anchor, addition, before=False):
    if text.count(anchor) != 1:
        fail(f"expected exactly one anchor {anchor.strip()!r}")
    return text.replace(anchor, addition + anchor if before else anchor + addition, 1)


def next_number(text):
    used = {int(n, 16) for n in re.findall(r"\bA1000([0-9A-F]{2})000[01]\b", text)}
    n = max(used) + 1
    while f"A1000{n:02X}0000" in text or f"A1000{n:02X}0001" in text:
        n += 1
    if n > 0xFF:
        fail("ran out of A1000xx IDs")
    return n


def add(text, name):
    if f"/* {name} */" in text:
        fail(f"{name} is already in the project")
    n = next_number(text)
    ref, build = f"A1000{n:02X}0000", f"A1000{n:02X}0001"
    text = insert_once(text, "/* End PBXBuildFile section */",
                       f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n",
                       before=True)
    text = insert_once(text, "/* End PBXFileReference section */",
                       f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
                       f'path = {name}; sourceTree = "<group>"; }};\n',
                       before=True)
    text = insert_once(text, GROUP_ANCHOR, f"\t\t\t\t{ref} /* {name} */,\n")
    text = insert_once(text, SOURCES_ANCHOR, f"\t\t\t\t{build} /* {name} in Sources */,\n")
    return text


def remove(text, name):
    if name == "UpdateManager.swift":
        fail("UpdateManager.swift is the anchor for new files; don't remove it")
    lines = text.splitlines(keepends=True)
    kept = [l for l in lines if f"/* {name} */" not in l and f"/* {name} in Sources */" not in l]
    if len(lines) - len(kept) != 4:
        fail(f"expected to remove 4 lines for {name}, found {len(lines) - len(kept)}")
    return "".join(kept)


def rename(text, old, new):
    if f"/* {new} */" in text:
        fail(f"{new} is already in the project")
    count = text.count(f"/* {old} */") + text.count(f"/* {old} in Sources */")
    if count == 0:
        fail(f"{old} is not in the project")
    text = text.replace(f"/* {old} in Sources */", f"/* {new} in Sources */")
    text = text.replace(f"/* {old} */", f"/* {new} */")
    return text.replace(f"path = {old};", f"path = {new};")


def main(args):
    if len(args) < 2:
        fail(__doc__)
    command, names = args[0], args[1:]
    text = PBX.read_text()
    if command == "add":
        for name in names:
            text = add(text, name)
    elif command == "remove":
        for name in names:
            text = remove(text, name)
    elif command == "rename" and len(names) == 2:
        text = rename(text, *names)
    else:
        fail(__doc__)
    PBX.write_text(text)
    print(f"xcodeproj_files: {command} {' '.join(names)} — done")


if __name__ == "__main__":
    main(sys.argv[1:])
