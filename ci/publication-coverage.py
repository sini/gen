#!/usr/bin/env python3
"""publication-coverage.py ROOT FILELIST [EXPECTED]  --  the ADR-0023 publication COVERAGE predicate, per statement.

The hub's `publication-coverage` check (ci/flake.nix) runs this over every tracked file. It is the successor of
den-ag-design's O-5 count-vs-fixture probe, whose spec is den-ag-design
`specs/2026-09-13-gen-invariant-publication-coverage-spec.md` (sections cited below by number).

For every file in FILELIST (the hub's tracked tree, enumerated by command in ci/flake.nix), enumerate every
PUBLICATION of the value-injection invariant (CLAIM) and require the interim CONDITION inside the SAME unit (§2.2):
  unit, rendered surface (*.md)   : the innermost block element of the cmark-gfm render (p, li, tr, h*),
                                    or ONE mermaid node label (mmdc SVG) for a claim inside a mermaid fence
  unit, source surface (all else) : the maximal CONTIGUOUS COMMENT BLOCK, markers stripped, flattened as one
                                    text; a non-comment line is its own unit. No window, no line join.
  TOTALITY (§2.4)                 : a claim the predicate cannot place in a unit is RESIDUE (red, named):
                                    a renderer drop (survival arm, md), fence text that is no node label,
                                    a code block, an unrenderable fence, unblocked text.
  ARMING (§2.4)                   : one literal unconditioned claim must score FAIL and one conditioned PASS,
                                    outside the population, before any file is read -- a COND over-match or a
                                    dead CLAIM is INVALID (exit 2), never green. This file carries that pair,
                                    so it is outside its own population (skipped by content identity, counted).
  EXPECTED                        : the totality tripwire -- the number of files the manifest names; a scanned
                                    count that differs is red, since a zero over an unread population is not clean.
No count fixture anywhere. Exit 0 = every publication conditioned; 1 = a FAIL or RESIDUE (rows on stderr,
file:line [kind]); 2 = invalid run (arming mis-scored, dead predicate, or an instrument missing).
"""
import html, os, re, shutil, subprocess, sys, tempfile, uuid
from html.parser import HTMLParser

CMARK = shutil.which("cmark-gfm")
MMDC = shutil.which("mmdc")
CLAIM = re.compile(r"types? never (leave|leaves|do|cross|crosses|enter)|only values cross|no gen type (crosses|leaves)"
                   r"|never (gen )?types|values cross|values,? (not|never) (gen )?types", re.I)
COND = re.compile(r"declared interim|declared opt-out", re.I)  # a bare ADR-0023 citation is not a condition
BLOCK = {"p", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "pre"}
# The arming pair: scored by the same predicates, outside the population, every run.
ARM = [("gen TYPES never leave the pure eval; only VALUES cross.", "FAIL"),
       ("gen TYPES never leave the pure eval; only VALUES cross — under ADR-0023's declared interim.", "PASS")]
# comment syntax: `#` is the marker in EVERY non-rendered file, plus `/* */` in nix. No suffix whitelist: one
# re-admitted the wrapped-claim class silently for Makefile/.gitattributes/.editorconfig. '//' in nix is the
# update operator and '--' in sh a flag, so neither is a marker.


def flat(s):
    return re.sub(r"\s+", " ", s).strip()


def strip_tags(s):
    return flat(html.unescape(re.sub(r"<[^>]+>", " ", s)))


def verdict(text):
    if not CLAIM.search(text):
        return None
    return "PASS" if COND.search(text) else "FAIL"


def joined(parts, first_line):
    """One text from per-line parts (single spaces), with (offset, source line) marks for witness mapping."""
    text, offs, pos = [], [], 0
    for k, p in enumerate(parts):
        p = flat(p)
        if not p:
            continue
        offs.append((pos, first_line + k))
        text.append(p)
        pos += len(p) + 1
    return " ".join(text), offs


def line_of(offs, idx):
    ln = offs[0][1] if offs else 0
    for start, l in offs:
        if start <= idx:
            ln = l
        else:
            break
    return ln


class Units(HTMLParser):
    """Innermost-block units with sourcepos. A <pre> unit records whether it is a mermaid fence."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack, self.units, self.loose = [], [], []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in BLOCK:
            self.stack.append({"tag": tag, "pos": a.get("data-sourcepos", "?"), "text": [], "mermaid": False})
        elif tag == "code" and self.stack and self.stack[-1]["tag"] == "pre" and "language-mermaid" in (a.get("class") or ""):
            self.stack[-1]["mermaid"] = True

    def handle_endtag(self, tag):
        if tag in BLOCK and self.stack and self.stack[-1]["tag"] == tag:
            u = self.stack.pop()
            u["text"] = flat("".join(u["text"]))
            self.units.append(u)

    def handle_data(self, data):
        (self.stack[-1]["text"] if self.stack else self.loose).append(data)


def span(pos):
    m = re.match(r"(\d+):\d+-(\d+):", pos)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def mermaid_units(fence_lines, start_line):
    """Render the fence with mmdc; each node label is a unit. Unrenderable => one RESIDUE unit.
    Survival: a fence-source line carrying the claim that no CLAIM-matching label witnesses => RESIDUE."""
    with tempfile.TemporaryDirectory() as d:  # no fixed temp path
        mmd, svg = os.path.join(d, "f.mmd"), os.path.join(d, "f.svg")
        open(mmd, "w").write("\n".join(fence_lines) + "\n")
        env = dict(os.environ, PUPPETEER_SKIP_DOWNLOAD="1")
        r = subprocess.run(["timeout", "180", MMDC, "-i", mmd, "-o", svg], capture_output=True, text=True, env=env)
        if r.returncode != 0 or not os.path.exists(svg):
            # The row carries the CAUSE, as `RESIDUE:cmark-failed` below already does: a row naming only the
            # fence says an environment could not render it and never why, so a runner failure (chromium in a
            # nested sandbox) is undiagnosable from the log by construction. mmdc puts its reason in the FIRST
            # stderr lines and node_modules stack frames after it, so frames are dropped and the head kept; the
            # verbatim output goes to the log too, since the row excerpt is truncated at print.
            raw = (r.stderr or "").strip() or (r.stdout or "").strip()
            why = flat(" ".join(l for l in raw.splitlines() if not l.lstrip().startswith("at "))) or "(no output)"
            print(f"MMDC FAILED rc={r.returncode} svg={int(os.path.exists(svg))} {MMDC} -- verbatim output follows\n"
                  f"{raw}\n-- end mmdc output", file=sys.stderr)
            return [{"kind": "RESIDUE:mermaid-unrendered", "line": start_line,
                     "text": f"mmdc rc={r.returncode} svg={int(os.path.exists(svg))}: {why[:150]}"
                             f" | fence: {flat(' '.join(fence_lines))[:60]}"}]
        labels = re.findall(r'class="nodeLabel"[^>]*>(.*?)</span>', open(svg).read(), re.S)
    stripped = [strip_tags(l) for l in fence_lines]
    out, witnessed = [], set()
    for lab in labels:
        t = strip_tags(lab)
        line = None
        for i, sl in enumerate(stripped):
            if t[:20] and t[:20] in sl:
                line = start_line + i
                break
        if line is not None and CLAIM.search(t):
            witnessed.add(line)
        out.append({"kind": "mermaid-node", "line": line if line is not None else start_line, "text": t})
    for i, sl in enumerate(stripped):
        if CLAIM.search(sl) and start_line + i not in witnessed:
            out.append({"kind": "RESIDUE:mermaid-claim-not-in-label", "line": start_line + i, "text": sl[:200]})
    return out


def md_units(path, src_lines):
    r = subprocess.run([CMARK, "-e", "table", "-e", "strikethrough", "--sourcepos", "--to", "html", path], capture_output=True, text=True)
    if r.returncode != 0:
        return [{"kind": "RESIDUE:cmark-failed", "line": 0, "text": r.stderr[:200]}]
    p = Units()
    p.feed(r.stdout)
    out = []
    for u in p.units:
        a, b = span(u["pos"])
        if u["tag"] == "pre":
            if u["mermaid"]:
                body = src_lines[a:b - 1]  # fence lines exclusive of the ``` markers
                if CLAIM.search(flat(" ".join(body))):
                    out.extend(mermaid_units(body, a + 1))
            elif CLAIM.search(u["text"]):
                out.append({"kind": "RESIDUE:code-block", "line": a, "text": u["text"][:200]})
        else:
            out.append({"kind": u["tag"], "line": a, "text": u["text"]})
    loose = flat("".join(p.loose))
    if CLAIM.search(loose):
        out.append({"kind": "RESIDUE:unblocked-text", "line": 0, "text": loose[:200]})
    # TOTALITY, source->render: the source is read as CHUNKS (maximal runs of non-blank lines), blockquote
    # markers stripped, flattened as one text. Every CLAIM match in a chunk must SURVIVE into a rendered unit
    # whose sourcepos span meets the match's lines AND whose text still carries the claim.
    # cmark-gfm silently drops excess table cells and omits raw HTML; span coverage alone is a false clean.
    spans = [(*span(u["pos"]), u) for u in p.units]
    n, failing, i = len(src_lines), set(), 0
    while i < n:
        if not src_lines[i].strip():
            i += 1
            continue
        j = i
        while j + 1 < n and src_lines[j + 1].strip():
            j += 1
        parts = [re.sub(r"^(\s*>)+\s?", "", src_lines[k]) for k in range(i, j + 1)]
        text, offs = joined(parts, i + 1)
        for m in CLAIM.finditer(text):
            ls, le = line_of(offs, m.start()), line_of(offs, m.end() - 1)
            covering = [u for a, b, u in spans if a <= le and ls <= b]
            if not any(CLAIM.search(u["text"]) for u in covering):
                failing.add(ls)
        i = j + 1
    prev = None
    for ln in sorted(failing):  # one row per run of consecutive dropped lines
        if prev is None or ln != prev + 1:
            out.append({"kind": "RESIDUE:source-claim-not-rendered", "line": ln, "text": flat(src_lines[ln - 1])[:200]})
        prev = ln
    return out


def comment_text(rel, src_lines):
    """Per line: the comment text with its marker stripped, or None for a non-comment line."""
    n = len(src_lines)
    ct = [None] * n
    nix, in_block = rel.endswith(".nix"), False
    for i, l in enumerate(src_lines):
        s = l.strip()
        if in_block:
            t = s.split("*/", 1)[0] if "*/" in s else s
            in_block = "*/" not in s
            ct[i] = re.sub(r"^\*+\s?", "", t)
        elif s.startswith("#"):
            ct[i] = re.sub(r"^#+\s?", "", s)
        elif nix and s.startswith("/*"):
            t = s[2:]
            in_block = "*/" not in t
            ct[i] = t.split("*/", 1)[0] if "*/" in t else t
    return ct


def src_units(rel, src_lines):
    """unit = the maximal contiguous comment block (markers stripped), else the single line."""
    ct = comment_text(rel, src_lines)
    n, out, i = len(src_lines), [], 0
    while i < n:
        if ct[i] is None:
            t = flat(src_lines[i])
            if t:
                out.append({"kind": "src-line", "line": i + 1, "text": t, "show": t})
            i += 1
            continue
        j = i
        while j + 1 < n and ct[j + 1] is not None:
            j += 1
        text, offs = joined(ct[i:j + 1], i + 1)
        m = CLAIM.search(text)
        line = line_of(offs, m.start()) if m else i + 1
        out.append({"kind": f"src-block {i + 1}-{j + 1}", "line": line, "text": text, "show": flat(src_lines[line - 1])})
        i = j + 1
    return out


def invalid(msg):
    print(f"INVALID: {msg}", file=sys.stderr)
    sys.exit(2)


def main():
    root, filelist = sys.argv[1], sys.argv[2]
    expected = int(sys.argv[3]) if len(sys.argv) > 3 else None
    for tool, name in ((CMARK, "cmark-gfm"), (MMDC, "mmdc")):
        if not tool:  # a missing instrument is never an absence finding
            invalid(f"{name} not on PATH -- instrument missing, no file read")
    for text, want in ARM:  # the arming pair, before the population
        got = verdict(text)
        if got != want:
            invalid(f"arming unit expected {want}, scored {got} -- predicate broken (COND over-match or dead CLAIM)")
    self_bytes = open(os.path.abspath(__file__), "rb").read()
    files = [l.strip() for l in open(filelist) if l.strip()]
    ctrl = uuid.uuid4().hex[:10]  # fresh negative-control token, never printed
    ctrl_re = re.compile(re.escape(ctrl))
    stats = dict(files=0, binary=0, self=0, md=0, units=0, pubs=0, ok=0, fail=0, residue=0, ctrl_hits=0)
    rows = []
    for rel in files:
        path = os.path.join(root, rel)
        raw = open(path, "rb").read()
        stats["files"] += 1
        if raw == self_bytes:  # the oracle carries the arming pair; it is outside its own population
            stats["self"] += 1
            continue
        if b"\0" in raw[:8192]:
            stats["binary"] += 1
            continue
        src_lines = raw.decode("utf-8", "replace").split("\n")
        if rel.endswith(".md"):
            stats["md"] += 1
            units = md_units(path, src_lines)
        else:
            units = src_units(rel, src_lines)
        for u in units:
            stats["units"] += 1
            if ctrl_re.search(u["text"]):
                stats["ctrl_hits"] += 1
            if u["kind"].startswith("RESIDUE:"):
                stats["residue"] += 1
                rows.append(("RESIDUE", rel, u["line"], u["kind"], u["text"]))
                continue
            v = verdict(u["text"])
            if v is None:
                continue
            stats["pubs"] += 1
            stats["ok" if v == "PASS" else "fail"] += 1
            rows.append((v, rel, u["line"], u["kind"], u.get("show") or u["text"]))
    for v, rel, line, kind, text in rows:  # offending rows to stderr, the rest to stdout
        print(f"{v:7} {rel}:{line} [{kind}] {text[:110]}", file=sys.stdout if v == "PASS" else sys.stderr)
    print("-- excerpt = unit text; for a source block, the claim LINE (the witness) -- the block extent is in [ ]")
    print("-- arming: literal FAIL/PASS pair scored as expected, outside the population")
    print(f"-- files={stats['files']} (binary skipped={stats['binary']}, self skipped={stats['self']}, md={stats['md']}) "
          f"units={stats['units']} publications={stats['pubs']} conditioned={stats['ok']} UNCONDITIONED={stats['fail']} "
          f"RESIDUE={stats['residue']} | negative-control(fresh 10-hex token over all units)={stats['ctrl_hits']}")
    sys.stdout.flush()
    if stats["pubs"] == 0:
        invalid("CLAIM predicate matched no unit -- dead predicate, not a clean absence")
    if expected is not None and stats["files"] != expected:
        print(f"PUBLICATION COVERAGE SCAN INCOMPLETE — {stats['files']} of {expected} tracked files reached the predicate. "
              "A zero over a population that was not read is not a clean result", file=sys.stderr)
        sys.exit(1)
    if stats["fail"] or stats["residue"]:
        print("PUBLICATION COVERAGE REGRESSION — a publication of the value-injection invariant carries no ADR-0023 "
              "interim condition in its own statement, or a claim could not be placed in a unit; each row is named "
              "above as file:line [kind]. Attach the condition to THAT statement (a neighbour's does not count)", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
