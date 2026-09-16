#!/usr/bin/env python3
"""Checks every inline Python program carried by the shell sources.

A program handed to Python as `python3 -c '...'` is delimited by single quotes,
so a single quote inside that program is consumed by the shell before Python ever
sees it. The program is then silently altered: an expression that read
`update.get('update_id')` arrives as `update.get(update_id)`, which fails at run
time instead of at parse time, and the command that depends on it never runs.

The rule enforced here is that a single-quoted `-c` program carries no single
quote of its own. A program that needs one belongs in a `python3 - ... <<'PY'`
heredoc, which the shell passes through unchanged.

Exit status is 0 when every program is intact and 1 when one is not.
"""

import re
import sys
from pathlib import Path

SHELL_SUFFIXES = {".sh", ".bash"}
SHELL_NAMES = {"batohub", "uninstall", "batohub-bot"}
MARKER = "python3 -c '"


def shell_files(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if ".git" in path.parts or "_generated" in path.parts:
            continue
        if path.suffix in SHELL_SUFFIXES or path.name in SHELL_NAMES:
            yield path


def programs(path: Path):
    """Yields (line_number, program_text) for every single-quoted -c program."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        start = line.find(MARKER)
        if start < 0:
            index += 1
            continue
        rest = line[start + len(MARKER):]
        if rest.strip():
            # The program opens and closes on this line; anything after the last
            # quote is the argument list of the invocation.
            close = rest.rfind("'")
            if close < 0:
                index += 1
                continue
            yield index + 1, rest[:close]
            index += 1
            continue
        # The program continues over the following lines and closes on a line
        # whose first character is the delimiter quote, which is then followed by
        # the arguments of the invocation.
        block = [rest]
        scan = index + 1
        while scan < len(lines) and not lines[scan].strip().startswith("'"):
            block.append(lines[scan])
            scan += 1
        if scan >= len(lines):
            yield index + 1, None
            return
        yield index + 1, "\n".join(block)
        index = scan + 1


def main(argv):
    root = Path(argv[1]) if len(argv) > 1 else Path(".")
    problems = []
    programs_seen = 0
    for path in shell_files(root):
        for line_number, program in programs(path):
            programs_seen += 1
            if program is None:
                problems.append(
                    "%s:%d: the program is never closed, so the rest of the file is "
                    "read as part of it" % (path, line_number)
                )
                continue
            if "'" not in program:
                continue
            quote = program.index("'")
            problems.append(
                "%s:%d: a single quote inside the program is consumed by the shell: %s"
                % (path, line_number, program[max(0, quote - 30):quote + 30].replace("\n", " "))
            )
    for item in problems:
        print("FAIL [inline python] %s" % item)
    if problems:
        print("%d inline python program(s) could not be used as written." % len(problems))
        return 1
    print("ok   %d inline python program(s) are intact" % programs_seen)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
