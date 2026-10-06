#!/usr/bin/env python3
"""A member landing's own load delta (den-hoag-r8y89 gate C2): the per-row difference of the `### load` tables of two
runs of the same bench at PERF_LOAD_MID=1, `--at <member>=rev:<parent>` and `--at <member>=rev:<landing>`.

  perf-bench-load-diff.py PARENT.out LANDING.out

A `member`, `startup` or other absolute row (state `abs`) and a row whose thunk marginal is equal in the two runs
are compared on their reading; a row both runs read affine, on its intercept; any other row is `confounded`. Prints
one `LANDING LOAD DELTA` line and one `ROSE:` line per row that rose. Exits 0 when none rose, 1 when one did, and
2 when either table is unreadable or the two do not hold the same rows (UNMEASURED, never a clean +0).
"""
import re
import sys
from fractions import Fraction

ROW = re.compile(r"^\| (\S+) \| (\d+) \| (\S+) \| (\S+) \| (\S+) \| (\S+) \| (\S+) \|$")


def table(f):
    rows, on = {}, False
    for line in open(f):
        if line.startswith("### load"):
            on = True
            continue
        if on and line.startswith("###"):
            break
        m = ROW.match(line.rstrip("\n")) if on else None
        if m:
            # reading, marginal, state, intercept
            rows[m.group(1)] = (int(m.group(2)), m.group(5), m.group(6), m.group(7))
    return rows


if len(sys.argv) != 3:
    sys.exit(__doc__)
try:
    p, q = table(sys.argv[1]), table(sys.argv[2])
except OSError as e:
    print(f"load-diff: unreadable: {e}", file=sys.stderr)
    sys.exit(2)
if not p or set(p) != set(q) or "startup,t" not in p:
    print("load-diff: the two load tables are unreadable or hold different rows — UNMEASURED", file=sys.stderr)
    sys.exit(2)
d, conf = {}, 0
for k in p:
    if p[k][2] == "abs" or p[k][1] == q[k][1]:
        d[k] = q[k][0] - p[k][0]
    elif p[k][3] != "-" and q[k][3] != "-":
        v = Fraction(q[k][3]) - Fraction(p[k][3])
        d[k] = int(v) if v.denominator == 1 else float(v)
    else:
        conf += 1
fmt = lambda v: f"{v:+d}" if isinstance(v, int) else f"{v:+.3f}"
mem = [k for k in d if k.startswith("member,") and d[k] != 0]
rows = [k for k in d if p[k][2] != "abs"]
moved = [d[k] for k in rows if d[k] != 0]
mem_s = f"members moved {len(mem)} of {sum(1 for k in p if k.startswith('member,'))}"
if mem:
    mem_s += " (" + ", ".join(f"{k[len('member,'):]} {fmt(d[k])}" for k in mem) + ")"
print(
    f"LANDING LOAD DELTA: startup thunks {fmt(d['startup,t'])}, startup alloc {fmt(d['startup,a'])} B, {mem_s}, "
    f"rows moved {len(moved)} of {len(rows)} judged ({conf} confounded), "
    f"per-row thunks min {fmt(min(moved, default=0))} max {fmt(max(moved, default=0))}"
)
rose = [k for k in d if d[k] > 0]
for k in rose:
    print("  ROSE:", k, fmt(d[k]))
sys.exit(1 if rose else 0)
