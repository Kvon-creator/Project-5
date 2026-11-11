#!/usr/bin/env python3
"""
Catch the class of GDScript error that only shows up when Godot parses a file.

There is no Godot binary on the machine this project's art is built on, so
mistakes like calling a helper that was never written survive until someone
opens the editor - and Godot stops at the FIRST parse error, so they surface
one at a time, one round trip each. This finds them all in one pass.

It checks, per file:

  1. Private methods (leading underscore) that are called but never defined.
     These can only come from the same script, so a missing one is always a
     bug. Public calls are skipped - they may be inherited or on another
     object.
  2. Signals that are emitted but never declared.
  3. Indentation that mixes tabs and spaces.
  4. Unbalanced brackets.

Heuristics, not a parser. It will not catch everything, but it catches the
mistakes that actually happen when writing GDScript without running it.

    python3 pipeline/check_gdscript.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")

# Callbacks Godot invokes on our behalf: defining them is normal, never
# calling them is normal, so they must not be reported as unused or missing.
GODOT_VIRTUALS = {
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_draw", "_enter_tree", "_exit_tree", "_init",
    "_notification", "_to_string", "_get", "_set", "_get_property_list",
    "_integrate_forces", "_gui_input", "_shortcut_input",
}

# Engine methods with a leading underscore that we may legitimately call.
GODOT_BUILTIN_CALLS = {
    "_on_body_entered", "_on_area_entered",
}


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def check_file(path):
    src = read(path)
    rel = os.path.relpath(path, ROOT)
    problems = []

    lines = src.split("\n")

    # Strip comments and strings so they cannot create false hits.
    stripped = []
    for line in lines:
        s = re.sub(r'"[^"]*"', '""', line)
        s = re.sub(r"'[^']*'", "''", s)
        s = s.split("#")[0]
        stripped.append(s)
    code = "\n".join(stripped)

    # --- 1. private methods called but not defined ----------------------
    defined = set(re.findall(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(", code,
                             re.M))
    called = set()
    for m in re.finditer(r"(?<![\w.])(_\w+)\s*\(", code):
        called.add(m.group(1))
    # Calls written as self._foo() or node._foo() - only self. is ours.
    for m in re.finditer(r"self\.(_\w+)\s*\(", code):
        called.add(m.group(1))

    missing = sorted(called - defined - GODOT_VIRTUALS - GODOT_BUILTIN_CALLS)
    for name in missing:
        for i, line in enumerate(stripped, 1):
            if re.search(r"(?<![\w.])%s\s*\(" % re.escape(name), line):
                problems.append(
                    (i, "calls %s() which is never defined in this file"
                     % name))
                break

    # --- 2. signals emitted but not declared ----------------------------
    declared = set(re.findall(r"^\s*(?:@\w+\([^)]*\)\s*\n\s*)?signal\s+(\w+)",
                              code, re.M))
    # Catch annotated signals too, which the pattern above can miss.
    declared |= set(re.findall(r"^\s*signal\s+(\w+)", code, re.M))
    for m in re.finditer(r"(?<![\w.])(\w+)\.emit\s*\(", code):
        name = m.group(1)
        if name in declared:
            continue
        # Only flag bare `foo.emit(` where foo is not a known local/property.
        if re.search(r"(?:var|const)\s+%s\b" % re.escape(name), code):
            continue
        if re.search(r"^\s*@onready\s+var\s+%s\b" % re.escape(name), code,
                     re.M):
            continue
        for i, line in enumerate(stripped, 1):
            if "%s.emit(" % name in line:
                problems.append(
                    (i, "emits signal '%s' which is never declared here"
                     % name))
                break

    # --- 2b. property setter assigning to its own property --------------
    # In Godot 4 this re-enters the setter and recurses until the stack
    # overflows. It parses fine, so nothing catches it until it runs.
    # Indentation must be matched with [ \t], not \s: \s includes newlines,
    # so a blank line before the declaration gets captured AS the indent and
    # every subsequent body test fails silently.
    for m in re.finditer(r"^([ \t]*)var\s+(\w+)[^\n]*:[ \t]*$", code, re.M):
        indent, prop = m.group(1), m.group(2)
        block = code[m.end():]
        # Take the property's body: lines indented deeper than the var.
        body_lines = []
        for line in block.split("\n"):
            if line.strip() and not line.startswith(indent + "\t") \
                    and not line.startswith(indent + "    "):
                break
            body_lines.append(line)
        body = "\n".join(body_lines)
        if "set(" not in body:
            continue
        if re.search(r"(?<![\w.])%s\s*=(?!=)" % re.escape(prop), body):
            line_no = code[:m.start()].count("\n") + 1
            problems.append(
                (line_no, "setter for '%s' assigns to %s - infinite "
                          "recursion in Godot 4; use a backing field"
                 % (prop, prop)))

    # --- 3. mixed indentation -------------------------------------------
    tabs = sum(1 for l in lines if l.startswith("\t"))
    spaces = sum(1 for l in lines if l.startswith("    "))
    if tabs and spaces:
        problems.append((0, "mixes tab and space indentation "
                            "(%d tab lines, %d space lines)" % (tabs, spaces)))

    # --- 4. bracket balance ---------------------------------------------
    for open_c, close_c in (("(", ")"), ("[", "]"), ("{", "}")):
        if code.count(open_c) != code.count(close_c):
            problems.append((0, "unbalanced %s%s : %d vs %d"
                             % (open_c, close_c, code.count(open_c),
                                code.count(close_c))))

    return rel, problems


def main():
    if not os.path.isdir(SCRIPTS):
        print("no scripts/ directory")
        return 1

    total = 0
    for name in sorted(os.listdir(SCRIPTS)):
        if not name.endswith(".gd"):
            continue
        rel, problems = check_file(os.path.join(SCRIPTS, name))
        if problems:
            print("\n%s" % rel)
            for line_no, msg in problems:
                where = "line %d" % line_no if line_no else "file"
                print("  %-9s %s" % (where, msg))
            total += len(problems)

    print("\n%s" % ("No problems found." if total == 0
                    else "%d problem(s) found." % total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
