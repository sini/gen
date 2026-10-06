#!/usr/bin/env python3
"""Record a perf-bench run's readings as ci/perf-bench.sh's bounds. The run's own printed lines are the only
input, so the writer cannot compute a bound the gate would not.

  perf-bench-bounds.py REPORT [--instrument] [SCRIPT]   (SCRIPT defaults to ci/perf-bench.sh)

REPORT is the bench's stdout. By verdict:
  8 RATCHET OWED      every `— lower NAME to V` and `— set NAME to V` (re-arm) line is applied to its assignment,
                      and ANCHOR_MEMBERS is written to the members the run read at.
  7 RE-ANCHOR OWED    the BOUNDS block is replaced by the run's `NAME=V   # …` lines (the identity lines
                      ANCHOR_EVALUATOR / ANCHOR_ALLOCATOR / ANCHOR_REFERENCE are written by hand, from the report).
  9 RE-ANCHOR BLOCKED refused: the members moved too. With --instrument (an edit to ci/perf-bench.{nix,sh} moves
                      every cell, so its own landing re-reads every bound at its member set; run it with
                      ANCHOR_EVALUATOR planted), as 7, and ANCHOR_MEMBERS is written to the run's members.
A raise is never written: a reading above its bound needs an owner reading (ci/README.md), and the bench prints
no assignment for it. Exits 0 on a write, 1 on a report it cannot record, 2 on an unreadable input.
"""
import re
import sys

args = [a for a in sys.argv[1:] if a != "--instrument"]
instrument = "--instrument" in sys.argv[1:]
if len(args) not in (1, 2):
    sys.exit(__doc__)
report_f, script_f = args[0], (args[1] if len(args) == 2 else "ci/perf-bench.sh")
try:
    report = open(report_f).read()
    script = open(script_f).read()
except OSError as e:
    print(f"perf-bench-bounds: unreadable input: {e}", file=sys.stderr)
    sys.exit(2)

if not re.search(r"^identity: evaluator ", report, re.M):
    print(f"perf-bench-bounds: {report_f} is not a complete bench report (no identity line) — UNREADABLE, not empty", file=sys.stderr)
    sys.exit(2)

NAME = r"(?:MARG_MAX|LOAD_MAX|LOADM|LOADI)\[[^\]]+\]"
VAL = r"(?:[0-9]+(?:/[0-9]+)?|-)"


def members_line(pat):
    m = re.findall(pat, report, re.M)
    if len(m) != 1:
        print(f"perf-bench-bounds: the report carries {len(m)} member lines, not 1", file=sys.stderr)
        sys.exit(2)
    return m[0]


def set_members(s, ids):
    pat = re.compile(r"^ANCHOR_MEMBERS=.*$", re.M)
    if len(pat.findall(s)) != 1:
        print("perf-bench-bounds: SCRIPT has no single ANCHOR_MEMBERS line", file=sys.stderr)
        sys.exit(2)
    return pat.sub(lambda _: f"ANCHOR_MEMBERS='{ids}'", s)


block = re.compile(r"# BEGIN BOUNDS\n.*?# END BOUNDS\n", re.S)
if len(block.findall(script)) != 1:
    print("perf-bench-bounds: SCRIPT has no single BEGIN/END BOUNDS block", file=sys.stderr)
    sys.exit(2)

if "RE-ANCHOR OWED" in report or "RE-ANCHOR BLOCKED" in report:
    if "RE-ANCHOR BLOCKED" in report and not instrument:
        print("perf-bench-bounds: RE-ANCHOR BLOCKED — the members moved with the identity; re-run at ANCHOR_MEMBERS, or pass --instrument for an instrument edit's own re-read", file=sys.stderr)
        sys.exit(1)
    lines = re.findall(rf"^  ({NAME}={VAL})   # ", report, re.M)
    if not lines:
        print("perf-bench-bounds: a re-anchor report with no assignment lines — UNREADABLE, not empty", file=sys.stderr)
        sys.exit(2)
    script = block.sub(lambda _: "# BEGIN BOUNDS\n" + "\n".join(lines) + "\n# END BOUNDS\n", script)
    if "RE-ANCHOR BLOCKED" in report:
        script = set_members(script, members_line(r"^  this run:\s+(.*)$"))
    n = len(lines)
elif "RATCHET OWED" in report:
    pairs = re.findall(rf"^  - (?:ratchet|re-arm): .* — (?:lower|set) ({NAME}) to ({VAL})$", report, re.M)
    if not pairs:
        print("perf-bench-bounds: a RATCHET OWED report with no lower/set lines — UNREADABLE, not empty", file=sys.stderr)
        sys.exit(2)
    for name, v in pairs:
        pat = re.compile(r"^" + re.escape(name) + r"=.*$", re.M)
        if len(pat.findall(script)) != 1:
            print(f"perf-bench-bounds: {name} has no single assignment in SCRIPT", file=sys.stderr)
            sys.exit(2)
        script = pat.sub(lambda _: f"{name}={v}", script)
    script = set_members(script, members_line(r"writes ANCHOR_MEMBERS='([^']*)'"))
    n = len(pairs)
else:
    print("perf-bench-bounds: the report records nothing (no RATCHET OWED or RE-ANCHOR verdict)", file=sys.stderr)
    sys.exit(1)

open(script_f, "w").write(script)
print(f"perf-bench-bounds: wrote {n} bound(s) to {script_f}")
