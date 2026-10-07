# gen perf-regression bench — drives ci/perf-bench.nix (pure vs reference stack) through
# nix-instantiate + NIX_SHOW_STATS, checks regression gates, prints a markdown report.
#
# Usage:
#   gen-perf-bench                     — report to stdout, enforce gates
#   gen-perf-bench --at K=SOURCE ...   — measure a COMBINATION: overlay member K onto the baseline,
#                                        SOURCE being rev:<sha> | ref:<branch> | path:<dir>.
#                                        Repeatable. Nothing is written and no lock is touched.
#   gen-perf-bench --update FILE.md    — same, and splice the report into FILE.md's
#                                        <!-- BEGIN PERF-BENCH --> / <!-- END PERF-BENCH --> block
#                                        (the live BENCHMARKS.md section). Refuses a non-empty overlay.
#
# Exits: 0 all gates passed, every cost reading EQUAL to its bound · 1 PERF REGRESSION (the published
# combination) · 2 the --update target is unusable, or the arguments are · 3 a dead cell (die_cell) ·
# 4 COMBINATION UNRESOLVED (an overlay, or the evaluator's own identity) · 5 SUPPLY/DEMAND RESIDUE ·
# 6 CANDIDATE OVER BOUND · 7 RE-ANCHOR OWED: the evaluator or a reference moved and the members are
# the anchored ones, so the printed readings are recordable as the new bounds · 8 RATCHET OWED: no
# regression, and at least one cost reading fell BELOW its bound, which the change adopting it lowers
# · 9 RE-ANCHOR BLOCKED: the evaluator or a reference moved AND the members did, so no reading is
# recordable until the bench is re-run at ANCHOR_MEMBERS (`--at K=rev:<anchored>`). 4–9 are separate
# codes on purpose: an unresolvable sibling used to exit 1, the same code as a performance
# regression, so no caller could tell "gen got slower" from "the network was down"; a candidate
# breaching a bound derived at the baseline anchor is a fact about a combination the repository has
# NOT adopted; "gen got faster" (8) is not "gen got slower" (1); and an evaluator moving (7, 9) is
# not gen moving. Precedence: 1/6 over 7/9 over 8.
#
# Injected by the flake app wrapper:
#   PERF_WORKLOADS    — store path of the workload corpus (ci/perf-bench.nix)
#   PERF_SRCS         — store path of a .nix attrset mapping lib names → source store paths (BASELINE)
#   PERF_COMBINATION  — store path of a .json map: key → { store, rev, flakeref, axis }
#
# Gates (rationale + baselines: ci/README.md) — every gate reads a DETERMINISTIC evaluator counter:
#   parity    — pure and ref digests identical for EVERY cell (byte-parity at benchmark scale)
#   cost      — every cost row, through `gate`: EXACT and TWO-SIDED against its recorded bound.
#               A row gates its MARGINAL, counter(big) − counter(small), so a per-process constant
#               cancels: a row whose denominator is INDEPENDENT of gen (nixpkgs `ref`, or a rev-pinned
#               frozen original) gates the ratio of marginals, NUM/DEN at full precision; a row whose
#               only control is gen itself gates the guarded arm's OWN marginal. Alloc is the
#               evaluator-attributed bytes. Above the bound is a regression; below it is `ratchet:`,
#               refused until the bound is lowered in the same change (den-hoag-r8y89: the bench
#               catches regressions and never obstructs optimizations)
#   load      — the per-process constant, through `gate` likewise: each member's load, the load its own
#               top-level values force, calls into its predecessors' functions included (one `load`
#               cell per member), each gated arm's small-size counter while its marginal holds, and
#               the startup cell. A load rise is a regression; a fall ratchets
#   linearity — pure counters across a ×4 size step grow ≤ 5.5× (linear ≈ 4×; quadratic ≥ 12×);
#               a complexity-class threshold, not a cost, so it does not ratchet
#
# cpu is measured, reported, and GATED BY NOTHING. Every gated axis above is a function of the
# evaluated expression alone; cpuTime is a function of the expression AND the machine's state, so
# gating it through the same `lte` types a non-deterministic quantity as deterministic — a defect no
# threshold and no rep count repairs. Measured: this host evaluates one tree at two stable frequency
# regimes ~2.2× apart — a RAW whole-cell ratio, not net-of-floor, and the two differ because the
# startup floor is itself bimodal — which exceeds the detection margin of five of the six cells the
# cpu gate used to cover, and the pure/ref ratio moved 0.734–1.873 across runs of byte-identical
# trees while every counter stayed byte-identical. The failure runs both ways, and the false GREEN (a regression
# passing because the host sped up between arms) is the dangerous half. Report-only cpu is this
# script's own prior convention: classShare's `cpu f/f` and overrideWarm's `cpu w/c` have always been
# computed, printed, and read by no gate. This bench detects regressions on counters; a change
# CLAIMING a wall-clock win is accepted under the P1–P5 protocol (den-architecture canreach-split
# spec §W), never here. The class that leaves unguarded is work moving INTO C++ builtins — counters
# are a lower bound by construction — and that is what §W acceptance is for.
#
# cpu is the median of $REPS INTERLEAVED samples: a row's arms are sampled round-robin, one rep of
# each in turn, never as separate blocks (see run_row). thunk/alloc counters are deterministic per
# evaluator identity, taken from the last rep. ALLOC is deterministic only because every cell runs
# with the collector off (GC_DONT_GC, sample_cell) and every source is a `<hash>-source` store path
# of one length (the `--at path:` arm adds the directory to the store): measured, a collecting cell
# moved by up to 9,648 B across six runs of one tree (deepSubmodule ref n=1600), and an overlay
# path's length moved coordMatch coord n=400 by 576 B; with both removed, every rep on one host read
# the same byte. Across hosts it also needs the host's nix-path pinned empty (NIX_PIN): unpinned, the
# CI runner and this workstation differed on 4 alloc gates.

# ── the combination under test ────────────────────────────────────────────────
# `--at <member>=<source>` overlays ONE member of the pure-side source set onto the baseline. The
# baseline is the pinned locks via PERF_SRCS (members: the root flake.lock; references: ci/flake.lock), an EMPTY overlay passes it through
# untouched, and NOTHING is ever written: a combination is a value this run TAKES and NAMES, never
# state the repository must first adopt. Every run echoes the whole combination — all twelve keys,
# their revisions, and each one's LEAK set — into the report, so the artefact records the population
# it measured instead of leaving the reader to infer it from a lock file.
#
# The five REFERENCE keys are refused by name. A ratio's denominator is its control: if both arms
# float, a moved ratio is unattributable — you cannot tell whether gen got worse or nixpkgs got
# better. A reference key moves only through ci/flake.lock, and that move owes a RE-ANCHOR (exit 7),
# never a verdict. (The 2026-09-21 re-baseline rejected an absolute pure-counter ratchet BESIDE an
# independent ratio, because there the ratio is the absolute up to a constant; den-hoag-r8y89 keeps
# that for the independent rows and gates the absolute only where the control is gen itself.)
UPDATE_FILE=""
declare -A AT_SRC AT_STORE AT_REV
AT_ORDER=()
UNRESOLVED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE_FILE=${2:?--update needs a file path}
      shift 2
      ;;
    --at)
      at_spec=${2:-}
      at_key=${at_spec%%=*}
      at_src=${at_spec#*=}
      if [[ "$at_spec" != *=* || -z "$at_key" || -z "$at_src" ]]; then
        UNRESOLVED+=("--at ${at_spec:-<no value>} — not of the form <member>=<source>")
      elif [[ -n "${AT_SRC[$at_key]:-}" ]]; then
        UNRESOLVED+=("$at_key — named twice by --at (${AT_SRC[$at_key]}, then $at_src)")
      else
        AT_SRC[$at_key]=$at_src
        AT_ORDER+=("$at_key")
      fi
      shift 2 || shift
      ;;
    *)
      echo "perf-bench: unknown argument '$1' — expected --at <member>=<source> or --update FILE.md" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$UPDATE_FILE" ]]; then
  # A candidate's numbers may not enter the published block. The live block in BENCHMARKS.md is the
  # project's claim about the combination it PUBLISHES, and splicing a candidate there certifies a
  # combination no consumer is on — this bench's founding defect, one surface over.
  if [[ ${#AT_ORDER[@]} -gt 0 ]]; then
    echo "perf-bench: --update refuses a non-empty overlay (${#AT_ORDER[@]} entry/entries) — $UPDATE_FILE publishes the ADOPTED combination, and a candidate's numbers there would certify a combination no consumer is on" >&2
    exit 2
  fi
  # Require both splice markers up front (before the ~2-min measurement): a missing END would let
  # the awk truncate the file at the splice (tail data loss); a missing BEGIN would silently no-op.
  if ! grep -q '<!-- BEGIN PERF-BENCH -->' "$UPDATE_FILE" 2>/dev/null \
    || ! grep -q '<!-- END PERF-BENCH -->' "$UPDATE_FILE" 2>/dev/null; then
    echo "no PERF-BENCH markers in $UPDATE_FILE" >&2
    exit 2
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Every evaluation reads the INSTRUMENT's nix-path, never the host's. The evaluator stores the host's
# nix-path (nix.conf `nix-path`/`extra-nix-path`, and NIX_PATH) on the GC heap at startup, and its
# value, and the channel it arrives by, move later allocations across heap-block boundaries (the same
# string as NIX_PATH reproduced CI's bytes on 1 of 3 cells, as nix.conf `extra-nix-path` on 3 of 3):
# measured, the CI runner's 78-character
# Determinate flakehub entry against this workstation's `nixpkgs=flake:nixpkgs` moved 4 alloc gates by
# up to 4,096 B with every thunk equal, and with this pin 0 of 282 rep-lines differed across the two
# hosts (den-hoag-r8y89 alloc host scout). The option overrides both channels; NIX_PATH= alone does
# not, since nix.conf's `extra-nix-path` still applies. The identity block refuses a run in which
# builtins.nixPath is not empty, so a lost NIX_PIN definition fails by name rather than as a 4 KiB
# drift. Every evaluation goes through nixi, so the pin has one definition and one use; an evaluation
# that calls nix-instantiate directly is NOT caught by the guard and reds as an unnamed alloc drift.
NIX_PIN=(--option nix-path '')
nixi() { nix-instantiate "${NIX_PIN[@]}" "$@"; }

# ── resolve the overlay, WHOLE-CLASS, before anything is collected (exit 4) ────
# Every entry is validated and fetched here and EVERY failure is named in one message: a partial
# matrix over a combination that could not be assembled is the confident-green shape this capability
# exists to remove. An unresolvable entry NEVER degrades to the baseline — a refusal is not a
# downgrade — and the default path touches no network at all, so an outage cannot red the hub's CI.
for at_key in ${AT_ORDER[@]+"${AT_ORDER[@]}"}; do
  at_src=${AT_SRC[$at_key]}
  at_axis=$(jq -r --arg k "$at_key" '.[$k].axis // "unknown"' "$PERF_COMBINATION")
  if [[ "$at_axis" == "unknown" ]]; then
    UNRESOLVED+=("$at_key=$at_src — not a key of the bench's source set")
    continue
  fi
  if [[ "$at_axis" == "reference" ]]; then
    UNRESOLVED+=("$at_key=$at_src — REFERENCE arm, which does not decouple: a floating denominator makes a moved ratio unattributable")
    continue
  fi
  case "$at_src" in
    path:*)
      at_dir=${at_src#path:}
      if [[ -d "$at_dir" ]]; then
        # Added to the store as `<hash>-source`, the shape and LENGTH of every pinned source: alloc
        # moves with the source path's length (header), so a content-identical directory read in
        # place would gate as a cost. A copy of a pinned tree resolves to that pin's own store path.
        at_st=0
        at_store=$(nix --extra-experimental-features nix-command store add --name source "$at_dir" 2>"$tmp/at-$at_key.err") || at_st=$?
        if [[ $at_st -ne 0 || "$at_store" != /nix/store/*-source ]]; then
          UNRESOLVED+=("$at_key=$at_src — adding it to the store failed (nix exit $at_st, '$at_store'): $(tr -s '[:space:]' ' ' <"$tmp/at-$at_key.err")")
        else
          AT_STORE[$at_key]=$at_store
          AT_REV[$at_key]="(path — UNPINNED)"
        fi
      else
        UNRESOLVED+=("$at_key=$at_src — no such directory")
      fi
      ;;
    rev:* | ref:*)
      at_ref="$(jq -r --arg k "$at_key" '.[$k].flakeref' "$PERF_COMBINATION")/${at_src#*:}"
      at_json=""
      at_st=0
      at_json=$(nix flake prefetch --json "$at_ref" 2>"$tmp/at-$at_key.err") || at_st=$?
      if [[ $at_st -ne 0 ]]; then
        UNRESOLVED+=("$at_key=$at_src — $at_ref did not resolve (nix exit $at_st): $(tr -s '[:space:]' ' ' <"$tmp/at-$at_key.err")")
      else
        at_store=$(printf '%s' "$at_json" | jq -er '.storePath | strings | select(. != "")') || at_store=""
        at_rev=$(printf '%s' "$at_json" | jq -er '.locked.rev | strings | select(. != "")') || at_rev=""
        if [[ -z "$at_store" ]]; then
          # exit 0 with nothing in it is the failure this whole block exists to refuse: a fetch that
          # reported nothing is not the same reading as a source with nothing to fetch.
          UNRESOLVED+=("$at_key=$at_src — $at_ref returned exit 0 but carries no storePath; the fetch is UNMEASURED, not empty")
        else
          AT_STORE[$at_key]=$at_store
          AT_REV[$at_key]=${at_rev:-"(resolved, no revision)"}
        fi
      fi
      ;;
    *)
      UNRESOLVED+=("$at_key=$at_src — a source is rev:<sha>, ref:<branch> or path:<dir>")
      ;;
  esac
done

if [[ ${#UNRESOLVED[@]} -gt 0 ]]; then
  {
    echo "perf-bench: COMBINATION UNRESOLVED — ${#UNRESOLVED[@]} overlay entry/entries could not be resolved; NO cells collected"
    printf '  - %s\n' "${UNRESOLVED[@]}"
  } >&2
  exit 4
fi

# The source set this whole run reads. With no overlay it IS $PERF_SRCS, byte for byte. An overlay's
# set is $PERF_SRCS with the entry's line rewritten, added to the store under the same name: the same
# flat attrset at a store path of the same length, so the overlay mechanism costs the cells nothing.
# Measured: an `(import base) // { … }` file at a tmp path moved coordMatch coord n=1600 alloc by one
# 4,080 B block with every source byte-identical, which an exact alloc gate reads as a regression.
SRCS=$PERF_SRCS
if [[ ${#AT_ORDER[@]} -gt 0 ]]; then
  cp "$PERF_SRCS" "$tmp/perf-srcs.nix"
  for at_key in "${AT_ORDER[@]}"; do
    at_line="  \"$at_key\" = \"${AT_STORE[$at_key]}\";"
    awk -v k="  \"$at_key\" = " -v l="$at_line" 'index($0, k) == 1 { print l; hit++; next } { print } END { exit hit != 1 }' \
      "$tmp/perf-srcs.nix" >"$tmp/perf-srcs.next" || {
      echo "perf-bench: COMBINATION UNRESOLVED — $at_key has no single line in $PERF_SRCS to overlay; NO cells collected" >&2
      exit 4
    }
    mv "$tmp/perf-srcs.next" "$tmp/perf-srcs.nix"
  done
  SRCS=$(nix --extra-experimental-features nix-command store add --mode flat --name perf-srcs.nix "$tmp/perf-srcs.nix") || {
    echo "perf-bench: COMBINATION UNRESOLVED — the overlaid source set could not be added to the store; NO cells collected" >&2
    exit 4
  }
fi

# The baseline half of the echo, read from the resolved lock rather than re-derived here.
declare -A BASE_STORE BASE_REV BASE_AXIS
COMB_KEYS=()
while IFS=$'\t' read -r bk ba br bs; do
  BASE_AXIS[$bk]=$ba
  BASE_REV[$bk]=$br
  BASE_STORE[$bk]=$bs
  COMB_KEYS+=("$bk")
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.axis)\t\(.value.rev)\t\(.value.store)"' "$PERF_COMBINATION")
if [[ ${#COMB_KEYS[@]} -eq 0 ]]; then
  echo "perf-bench: the combination record at $PERF_COMBINATION carries no keys — the population is UNREADABLE, not empty" >&2
  exit 4
fi

# "workload n tags" — tags: r = a ratio row's big size (its marginal runs from the row's `small`), rb =
# wideFreeform's (its thunk marginal is a parity band), small/big = the marginal and linearity pair (big = 4×small)
# noref = PURE-ONLY row: no reference cell is measured, so it carries no parity/ratio verdict and is
# reported apart from the pure/ref table. A pure/ref gate is only meaningful where a frozen reference
# can track its subject; the aspect grammar moves by design ruling, so no frozen aspect stack can (see
# perf-bench.nix header). Linearity and the absolute pure counters are unaffected — they never read ref.
MATRIX=(
  "startup 1 none"
  "scalar 2000 small"
  "scalar 8000 r,big"
  "registry 500 small"
  "registry 2000 r,big"
  "lazyRegistry 500 small"
  "lazyRegistry 2000 r"
  "threadedRegistry 500 small"
  "threadedRegistry 2000 r,big"
  "wrappedRegistry 500 small"
  "wrappedRegistry 2000 r,big"
  "steppedRegistry 500 small"
  "steppedRegistry 2000 r,big"
  "schemaHosts 400 small"
  "schemaHosts 1600 r,big"
  "inheritHosts 400 small,noref"
  "inheritHosts 1600 big,noref"
  "aspects 400 small,noref"
  "aspects 1600 big,noref"
  "wideFreeform 2000 small"
  "wideFreeform 8000 rb,big"
  "deepSubmodule 400 small"
  "deepSubmodule 1600 r,big"
  "foreignMount 500 small"
  "foreignMount 2000 r,big"
  "moduleFanIn 400 small"
  "moduleFanIn 1600 big"
  "sameLocFanIn 400 small"
  "sameLocFanIn 1600 big"
)

REPS=3
GROWTH_MAX=5.5

# ── the identity every bound below was read under (den-hoag-r8y89) ───────────
# A bound is a reading, and a reading is a function of the expression, the evaluator and the
# allocator it links, and the five REFERENCE sources. When the evaluator, the allocator or a reference
# differs from these lines the run gates NOTHING on cost: it prints every reading and exits 7 (or 9),
# because a gen verdict against bounds read under another identity is unattributable. Re-anchoring
# rewrites every bound and these lines together, and it is the one licensed raise of a bound without
# an owner reading. ANCHOR_MEMBERS is the RECORD of the member revisions the bounds were read at, and
# it is not part of the identity: a member is the change under test (owner ruling P5 (i), 2026-10-05),
# so a member move is gated against the bounds, never re-anchored. A re-anchor is recordable only
# from a run AT these members — otherwise a member regression travelling in the same relock as an
# evaluator bump would be recorded as the new baseline (gate C1). Every change that writes a bound
# (a ratchet, an owner-read raise, a re-anchor) writes ANCHOR_MEMBERS to the members it read at.
# The evaluator is the `pkgs.nix` this app prepends to PATH, so CI and a local run share it; the
# allocator is the boehm-gc in that evaluator's closure, keyed because `gc.totalBytes` is its
# counter and a nix rebuild can move it under an unchanged --version (gate C5).
ANCHOR_EVALUATOR='nix-instantiate (Nix) 2.34.8'
ANCHOR_ALLOCATOR='boehm-gc-8.2.12'
ANCHOR_REFERENCE='gen-graph-orig=0db4e73708f356024121336fcad1230ba0aed8d4 gen-prelude-orig=c471c9a12ef5495be5c50911ff45e3efa16cc67f gen-schema-orig=2b7c2d39ad30f8fa5165d6861c01374f7c9cf3f6 gen-select-orig=9285b5b8264a779894dd79e00fa0fe7683a9ffaf nixpkgs-lib=db3f255737b94216eb71cce308e2912cf6bc2d7c'
ANCHOR_MEMBERS='gen-algebra=7805ec1e7d07b1bc3768e7fea222b156bd3de0d4 gen-aspects=84b71cc739352a7218585936d6aae1a81fd4123b gen-class=e3f02f6349bf6d92d7e38c861a08682863562836 gen-graph=2b9dd3afd25f593e436f32f0e49b71935da572da gen-identity=6339f2332f4d2f62d7163d35cd4406fb3c91975b gen-memo=3fd98b36bdd4896c779b1ef2e70b1da206942bf2 gen-merge=d504add70eaa117ad2bac6172a536b9fe7385150 gen-prelude=0d3539d9ffaa4cc100b284d9c40e6d2e819a016d gen-schema=0b27f2002c2b3da8e6579975c33c15fd79e16016 gen-scope=0ef44ff099d9caa2a96305cf63f927660d9d816f gen-select=862833b05a13e5355c3fd6368a5a6b7ac9908a3f gen-types=5662d8a29c0ab18bbcf5deb1e3e0263f857c6062'

# ── marginal and load bounds, read at the anchor (den-hoag-r8y89) ──────────────────────────────
# Every bound is the EXACT reading at the anchor identity above, an integer count or, on a ratio row,
# NUM/DEN: the two raw marginals, compared by cross-multiplication. There is no margin and no per-row
# tolerance (owner sitting den-hoag-rwuqw, ruling 10 arm A; P1 (i), P5 (i)): the bound EQUALS the
# reading on a green run, a reading above it is a regression (raising it needs an owner reading on the
# five items in ci/README.md), and a reading below it is `ratchet:` until the bound is lowered to it
# in the same change. Four tables, keyed by row (the marginal and load section, below the report):
#   MARG_MAX  each cost row's marginal: counter(big) − counter(small), thunks and attributed bytes;
#             a ratio row reads pure over ref, NUM/DEN. wideFreeform's thunk marginal is a parity band
#             with nixpkgs (`…,t,band`), since freeform absorption rides the same per-key type merges
#             nixpkgs.lib performs; its alloc marginal is a win-gate like every other row's.
#   LOAD_MAX  the load: each member's own load (`member,<key>,t|a`), each gated arm's small-size thunk
#             counter, and the startup cell's thunks and attributed bytes.
#   LOADM     each gated arm's own thunk marginal at the anchor: its X_s is judged only while it holds.
#   LOADI     each gated arm's three-size thunk intercept at the anchor, or `-` where it is not affine.
# The block is written by ci/perf-bench-bounds.py from a run's own printed lines, never by hand. The
# per-size ratio bounds these rows gated until den-hoag-r8y89's marginal form, with every anchor, margin,
# ratchet and re-anchor recorded beside them, are at hub `94e07ff` (`git show 94e07ff:ci/perf-bench.sh`).
declare -A MARG_MAX LOAD_MAX LOADM LOADI
# BEGIN BOUNDS
MARG_MAX[scalar,t]=510000/632000
MARG_MAX[scalar,a]=28654000/39182000
LOAD_MAX[scalar]=173080
LOADM[scalar]=510000
LOADI[scalar]=18480000/6000
MARG_MAX[registry,t]=1007250/1632750
MARG_MAX[registry,a]=48914000/87727000
LOAD_MAX[registry]=339728
LOADM[registry]=1007250
LOADI[registry]=5967000/1500
MARG_MAX[lazyRegistry,t]=995250/1631250
MARG_MAX[lazyRegistry,a]=48458000/87595000
LOAD_MAX[lazyRegistry]=335727
LOADM[lazyRegistry]=995250
LOADI[lazyRegistry]=5965500/1500
MARG_MAX[threadedRegistry,t]=1159500/1632750
MARG_MAX[threadedRegistry,a]=56960000/87727000
LOAD_MAX[threadedRegistry]=392060
LOADM[threadedRegistry]=1159500
LOADI[threadedRegistry]=8340000/1500
MARG_MAX[wrappedRegistry,t]=1007250/1632750
MARG_MAX[wrappedRegistry,a]=48926000/87727000
LOAD_MAX[wrappedRegistry]=341583
LOADM[wrappedRegistry]=1007250
LOADI[wrappedRegistry]=8749500/1500
MARG_MAX[steppedRegistry,t]=795906/1417923
MARG_MAX[steppedRegistry,a]=39639059/76479824
LOAD_MAX[steppedRegistry]=269176
LOADM[steppedRegistry]=795906
LOADI[steppedRegistry]=-
MARG_MAX[schemaHosts,t]=1816000/2145200
MARG_MAX[schemaHosts,a]=93555600/115548200
LOAD_MAX[schemaHosts]=614879
LOADM[schemaHosts]=1816000
LOADI[schemaHosts]=11454800/1200
MARG_MAX[wideFreeform,t,band]=459000/512000
MARG_MAX[wideFreeform,a]=27134000/35030000
LOAD_MAX[wideFreeform]=156832
LOADM[wideFreeform]=459000
LOADI[wideFreeform]=22992000/6000
MARG_MAX[deepSubmodule,t]=4344000/8666400
MARG_MAX[deepSubmodule,a]=217915200/453759000
LOAD_MAX[deepSubmodule]=1451926
LOADM[deepSubmodule]=4344000
LOADI[deepSubmodule]=4711200/1200
MARG_MAX[foreignMount,t]=1275000/1254000
MARG_MAX[foreignMount,a]=68107000/67327000
LOAD_MAX[foreignMount]=428920
LOADM[foreignMount]=1275000
LOADI[foreignMount]=5880000/1500
MARG_MAX[classShare,fixed,t]=808200
LOAD_MAX[classShare,fixed]=276436
LOADM[classShare,fixed]=808200
LOADI[classShare,fixed]=8443200/1200
MARG_MAX[overrideWarm,warm,t]=1093800
MARG_MAX[overrideWarm,warm,a]=54126000
LOAD_MAX[overrideWarm,warm]=377445
LOADM[overrideWarm,warm]=1093800
LOADI[overrideWarm,warm]=15414000/1200
MARG_MAX[kindMatch,migrated,kind,t]=1192800
MARG_MAX[entityMatch,migrated,entity,t]=1629000/1702800
MARG_MAX[coordMatch,migrated,coord,t]=2373600
MARG_MAX[kindMatch,migrated,kind,a]=65289600
MARG_MAX[entityMatch,migrated,entity,a]=84026400/91557600
MARG_MAX[coordMatch,migrated,coord,a]=120668400
LOAD_MAX[kindMatch,migrated,kind]=412008
LOADM[kindMatch,migrated,kind]=1192800
LOADI[kindMatch,migrated,kind]=17289600/1200
LOAD_MAX[entityMatch,migrated,entity]=558022
LOADM[entityMatch,migrated,entity]=1629000
LOADI[entityMatch,migrated,entity]=18026400/1200
LOAD_MAX[coordMatch,migrated,coord]=801108
LOADM[coordMatch,migrated,coord]=2373600
LOADI[coordMatch,migrated,coord]=11889600/1200
MARG_MAX[kindMatch,sealed,kind,t]=1192800
MARG_MAX[entityMatch,sealed,entity,t]=1642200/1702800
MARG_MAX[coordMatch,sealed,coord,t]=2386800
MARG_MAX[kindMatch,sealed,kind,a]=65289600
MARG_MAX[entityMatch,sealed,entity,a]=84948000/91557600
MARG_MAX[coordMatch,sealed,coord,a]=121590000
LOAD_MAX[kindMatch,sealed,kind]=412669
LOADM[kindMatch,sealed,kind]=1192800
LOADI[kindMatch,sealed,kind]=18082800/1200
LOAD_MAX[entityMatch,sealed,entity]=563359
LOADM[entityMatch,sealed,entity]=1642200
LOADI[entityMatch,sealed,entity]=19150800/1200
LOAD_MAX[coordMatch,sealed,coord]=807892
LOADM[coordMatch,sealed,coord]=2386800
LOADI[coordMatch,sealed,coord]=14750400/1200
MARG_MAX[resolution,4-5,t]=168/196
MARG_MAX[resolution,5-6,t]=190/236
MARG_MAX[resolution,6-7,t]=212/276
MARG_MAX[resolution,7-100,t]=115878/200508
MARG_MAX[resolution,100-1000,t]=10952100/19814400
LOAD_MAX[resolution,resolve]=2388
LOADM[resolution,resolve]=168
LOAD_MAX[startup,t]=2982
LOAD_MAX[startup,a]=177389
LOAD_MAX[member,gen-prelude,t]=151
LOAD_MAX[member,gen-prelude,a]=15324
LOAD_MAX[member,gen-algebra,t]=81
LOAD_MAX[member,gen-algebra,a]=6801
LOAD_MAX[member,gen-identity,t]=13
LOAD_MAX[member,gen-identity,a]=810
LOAD_MAX[member,gen-graph,t]=1753
LOAD_MAX[member,gen-graph,a]=87864
LOAD_MAX[member,gen-types,t]=485
LOAD_MAX[member,gen-types,a]=28946
LOAD_MAX[member,gen-scope,t]=1754
LOAD_MAX[member,gen-scope,a]=108226
LOAD_MAX[member,gen-memo,t]=412
LOAD_MAX[member,gen-memo,a]=24242
LOAD_MAX[member,gen-merge,t]=942
LOAD_MAX[member,gen-merge,a]=54292
LOAD_MAX[member,gen-schema,t]=534
LOAD_MAX[member,gen-schema,a]=31868
LOAD_MAX[member,gen-aspects,t]=307
LOAD_MAX[member,gen-aspects,a]=19656
LOAD_MAX[member,gen-select,t]=51
LOAD_MAX[member,gen-select,a]=4755
LOAD_MAX[member,gen-class,t]=210
LOAD_MAX[member,gen-class,a]=10097
# END BOUNDS

# ── classShare (gen-class tier-2 fixed-input spine gate) — its OWN threshold, own rationale ──
# The fixed-input path (applyCoreFixed) skips gen-merge's discharge/fold/verify spine for the shared
# core loc, so its thunk graph must be a fraction of the full re-merge's. Measured fixed/full thunk
# ratio ≈ 0.17 (2026-07-05, Nix 2.34.7, gen-merge fdbf140) — a ~5.8× spine reduction. The gate floor
# 0.30 = measured + ~75% relative headroom, and enforces ≥3.33× — comfortably past the A1 fixed-input
# reference (2.48×, ratio 0.403; the 1.89×→2.48× spine-tax band, spec §2.5) so an erosion BELOW the A1
# band fires the gate ("any reduction" is not a pass). Sizes mirror schemaHosts/aspects (400→1600, ×4).
# GATED (den-hoag-r8y89): both arms are gen and no nixpkgs operation corresponds to fixed-input class
# sharing (spec OQ1), so the row gates the guarded arm's OWN cost: the `pure-fixed` thunk marginal and
# its load. Erosion of the reuse raises the marginal and reds; the 0.30 ratio (≥ 3.33×, the A1 band) is
# printed, gated by nothing. The domain, stated: a change that lowers the shared plane AND erodes the
# reuse by less moves the fixed arm DOWN, so it passes as a ratchet and the erosion is absorbed into the
# lowered bound; only the printed ratio shows it.
CLASSSHARE_SMALL=400
CLASSSHARE_BIG=1600

# ── wideFreeform — THUNK band (only alloc keeps the default win-gate) ──
# Freeform absorption is THUNK-parity with nixpkgs, not a pure win on that counter: unknown sibling keys
# route through the root freeformType, so absorption rides the SAME per-key type merges nixpkgs.lib
# performs (the pure engine's thunk win is on DECLARED option paths — see scalar/registry/aspects). So
# the thunk marginal ratio is a band, `MARG_MAX[wideFreeform,t,band]`, while the alloc marginal stays a
# win-gate: two claims, two bounds. The real teeth are LINEARITY (the O(n^2) freeform blowup this
# workload was built to catch — pre-fix n=8000 thunks were 468×ref, gated at GROWTH_MAX over a 4x step)
# and the deterministic counters. The cpu band this row once carried is retired with the rest (header).

# ── overrideWarm (gen-merge warm re-eval / memoized override) — its OWN threshold, own rationale ──
# The warm path (README §"Warm re-eval") reuses the previous eval's declared-leaf values for locs outside
# the edit's dirty footprint, so a class of overrides over one base pays the registry merge ONCE (in the
# shared `prev`) instead of once per override. Measured warm/cold thunk ratio ≈ 0.17 and alloc ≈ 0.17
# (2026-07-05, Nix 2.34.7, gen-merge fdbf140) at both sizes — a ~5.9× reduction (6 overrides amortising a
# single base merge: 1/6 ≈ 0.167 + the per-edit re-merge). The gate ceiling 0.30 = measured + ~75%
# relative headroom, and enforces ≥ 3.33× — an erosion of the reuse (a footprint that wrongly pulls the
# registry into the re-merge, or a lost splice) fires the gate well before warm stops beating cold. BOTH
# thunks AND alloc are gated (both are deterministic per Nix version and both genuinely reduce here — the
# whole warm stack allocates less, unlike classShare where the digest serialization dominates alloc).
# Sizes mirror classShare/schemaHosts/aspects (400 → 1600, ×4).
# GATED (den-hoag-r8y89), classShare's reason: the `warm` thunk and alloc marginals and its load; the
# warm/cold ratios are printed, gated by nothing. The same domain statement holds: a shared-plane gain
# larger than a simultaneous reuse erosion reads as a ratchet.
OVERRIDEWARM_SMALL=400
OVERRIDEWARM_BIG=1600

# ── kindMatch (kind identity at scale; den-hoag-l0y) — the owner's landing gate on ruling (a) ──
# Ruling (a) keys every kind by its MINTED identity, and the owner's condition on it was that the hub
# bench gates the landing and ANY regression is a defect (xzchx). The digest lives on the kind value
# (gen-schema's lazy `__mint.minted`) and every reader holds a shared reference, so the mint is paid
# once per KIND. The class this row exists for is the per-NODE recompute — each node re-deriving its
# kind and forcing a fresh digest — which is LINEAR (measured 3.99× over a 4× step), so GROWTH_MAX
# can never see it; only a ratio against a same-n denominator can.
#
# STACKS. The numerator is `kind` (`sel.kind A` through the LIVE gen-select). The denominator is
# `attrs-ref`: the same union and context matched with `sel.attrs` through a FROZEN gen-select
# (`gen-select-orig`, rev-pinned at `9285b5b` in ci/flake.nix, so no relock moves it). A denominator
# that runs the code under test does not cancel a cost both stacks pay in it, but it DILUTES it by
# the ratio: with the live `sel.attrs` as denominator, +3 thunks/node in the shared `matches` read
# exactly at the bounds and passed (den-hoag-l0y landing gate, plant C). TWO FIXTURES: `migrated`
# (the kind's sealed map is empty) and `sealed` (stacks `attrs-ref-sealed` / `kind-sealed`: `addr` is
# typed by nixpkgs `lib.types.str`, so a matching node reaches `sealedCollisionEq`'s non-empty arm,
# the unmigrated kinds den declares today). Without the second fixture a cost confined to that arm
# is invisible here (plant S3, same gate).
#
# THREE GATES per fixture. (1) BYTE: kind's projection equals attrs-ref's — the n/2 A instances. A
# name key that conflates the two same-name kinds returns all n, so this gate also reds the
# conflation itself. (2) COST, thunks AND alloc (a per-node primop recompute over a cached preimage
# costs ~1 thunk but allocates): the `kind` arm's own marginals and its load. The denominator runs the
# frozen matcher over the LIVE data plane (gen-merge, -schema, -scope, … — the reach census), so it is
# gen-vs-gen and no nixpkgs operation corresponds to kind-identity selection (spec OQ1): the
# kind/attrs-ref ratios are printed and gated by nothing, and what the frozen denominator buys is the
# byte gate. (3) LINEARITY on every stack. ARMING, every run: `kind-plant`'s thunk marginal must exceed
# MARG_MAX[kindMatch,migrated,kind,t].
KINDMATCH_SMALL=400
KINDMATCH_BIG=1600

# ── entityMatch (INSTANCE identity at scale; den-hoag-l0y U2) — the row that FORCES `id_hash` ──
# gen-schema's instance stamp carries the kind's minted identity beside the key values, so two
# same-name kinds that are different declarations mint different identities. kindMatch cannot meter
# that stamp: the registry adapter's `entryFor` tests the stamp's PRESENCE and never forces its value.
# This row reads every node's stamp through `sel.entity`.
#
# STACKS. The numerator is `entity` (`sel.entity kA hostsA.h0` through the LIVE gen-select over LIVE
# gen-schema instances). The denominator is `attrs-ref`, and it runs NO library under test: the
# frozen gen-schema (`gen-schema-orig`) on the pinned nixpkgs `lib.evalModules`, matched with
# `sel.attrs` through the frozen gen-select (`gen-select-orig`). Both frozen pins are rev-pinned in
# ci/flake.nix, so no relock moves the denominator. It must not run the live gen-schema: with a
# ratio above 1, a cost both stacks pay LOWERS the ratio, so a one-sided gate reads the regression
# as an improvement — measured with the live gen-schema in both stacks, the un-hoisted identity
# module (+6 thunks/node) read 1.6737 / 1.6707 against 1.6773 / 1.6744 and passed.
#
# THREE GATES. (1) PROJECTION: entity selects exactly `[ "a:h0" ]` (its digest is pinned below); a
# stamp keyed by the kind NAME selects both halves, `[ "a:h0" "b:h0" ]`, which is attrs-ref's
# projection and is pinned as the control. (2) COST, thunks AND alloc: the entity/attrs-ref marginal
# ratio, and the `entity` arm's load. (3) LINEARITY on every stack. ARMING, every run: `entity-plant`'s
# marginal ratio must exceed MARG_MAX[entityMatch,migrated,entity,t].
#
# TWO FIXTURES (den-hoag-l0y (β); kindMatch's precedent). `migrated` (the kinds' sealed maps are
# empty, so `sel.entity` decides on the stamp alone) and `sealed` (stacks `attrs-ref-sealed` /
# `entity-sealed`: `addr` is typed by nixpkgs `lib.types.str`, so the one matching node reaches the
# sealed arm, reading the node's kind key and deciding through `kindEq`). Without the second fixture a
# cost confined to that arm is invisible here: a gen-select that reads every node's kind before the
# stamp decides (+6 thunks/node, the (β) landing's plant, driven through `--at gen-select=path:`)
# reads 1.310 / 1.304 against the sealed bounds 1.305 / 1.300 and reds, while its migrated ratios and
# both projections are unchanged. The two denominators are the same frozen stack (the frozen side's
# `str` is nixpkgs' already), so each fixture's ratio is read against its own paired cell.
#
# THE PRICE, stated: the stamp's kind component costs +24.0 thunks per instance (one more
# ⟨label, value⟩ pair through the canonical encoder) plus the mark once per kind, which the stamp now
# forces — ≈3.3k thunks on this row's one-option kind, and more on a larger declaration, since every
# option attribute is a component of the mark. Stock gen-schema `cfec60d` as the numerator reads
# 731,629 / 2,906,629 thunks and fails the projection gate (both halves).
ENTITYMATCH_SMALL=400
ENTITYMATCH_BIG=1600
# sha256 of the JSON projections: `[ "a:h0" ]` (entity) and `[ "a:h0" "b:h0" ]` (attrs-ref).
ENTITYMATCH_DIGEST_ENTITY=6b6d42a882aa4068cc0009757746a29fd06a3ee757c08a55f179af91c2e88055
ENTITYMATCH_DIGEST_REF=b4d8cf97c0d1bfa8fe91136ed4d1fe56610ae23dadb1a30ecfd6df7f31a796a1

# ── coordMatch (the PRODUCT COORDINATE's identity decision at scale; den-hoag-8hqx0) ──
# `adapters.product.coord dim kind entry` decides as `sel.entity` does: the stamp, then — at an equal
# stamp whose kind has sealed components — the context's per-dimension kind (`mkContext`'s `kinds`,
# published once as the context field `coordKinds`) through `entityEq`. The node's kind is read ONLY
# there, so the per-cell cost is unchanged from the bare-stamp arm it replaced (+0.000 thunks/cell and
# +0.0 B/cell against stock on all three evaluators, den-hoag-8hqx0 §3a B1).
#
# STACKS. The numerator is `coord` (the LIVE gen-select, `coord "host" kH hosts.h0` over a context
# carrying `kinds`). The denominator is `coord-ref`: the FROZEN gen-select (`gen-select-orig`, rev-pinned
# in ci/flake.nix), whose two-argument `coord` compares the bare stamp, over its own mkContext. Both
# stacks share one set of live gen-schema instances, so this row meters gen-select's coordinate arm
# and nothing else; a cost in the stamp is common-mode here, and entityMatch meters it.
#
# 64 selectors each run over every cell (perf-bench.nix states why: with one, construction dilutes
# the matcher below the ratio's printed precision). THREE GATES, entityMatch's. (1) PROJECTION: both
# stacks select exactly `[ "h0" … "h63" ]`. (2) COST, thunks AND alloc: the `coord` arm's own marginals
# and its load. Both stacks share the live gen-schema instances and plane, so gen-merge c3 (`ownUnmatched
# = []` when nothing is undeclared) lowered coord and coord-ref alike and a coord/coord-ref ratio rose to
# 1.001 with the excess a constant +398: the ratios are printed, gated by nothing. (3) LINEARITY on
# every stack.
#
# WHY ALLOC IS GATED (den-hoag-8hqx0 gate PF5). The rejected construction A — the kind projected into
# every cell's `data` — is THUNK-NEUTRAL (+0.000/cell) and costs bytes only (+16.7 / +9.9 B/cell): a
# thunk-only row passes it. Both plants were driven through `--at gen-select=path:` at the landing and
# must exit non-zero: `plant-kindread` (the context kind read before the stamp decides, +3 thunks/cell)
# and `plant-A` (construction A). ALLOC is GC-quantised and depends on the source PATH string (the
# bank's perf-bench trap), so the anchor is read on a `path:` overlay and must be re-read at the relock
# that lands gen-select's tip.
COORDMATCH_SMALL=400
COORDMATCH_BIG=1600
# sha256 of the JSON projection `[ "h0" … "h63" ]` (each of the 64 selectors selects its own cell),
# both stacks.
COORDMATCH_DIGEST=ec30bebff99631b2d8ef98e29a6403135aea466f4b4d1d2ab303d1dffefe77dc

# ── resolution (the one resolution calculus at scale; den-hoag-gayc U2b, design §5.8) ──
# The hub's own peer shape — a COMPLETE peer relation with self-edges over n hosts, walked `peer*`
# from `h0` — through the LIVE gen-scope `resolve` (mode `reachable`, the walk law) over the relation
# lifted to an evaluated scope, against gen-graph FROZEN at `0db4e737` (`gen-graph-orig`, ci/flake.nix),
# whose `query { mode = "all"; }` over a `labeledFrom` record is the DENOMINATOR at a revision no
# relock moves. The denominator is frozen IN FULL: gen-graph-orig is applied with the gen-prelude its
# own lock pins (`gen-prelude-orig`, `c471c9a`), never the live one, so a prelude change can move only
# the numerator.
#
# GATES. (1) BYTE, every n: resolve's projection (the answer's nodes, sorted) equals query-orig's
# (sorted): a SET-parity gate (owner ruling 15, 2026-10-04, den-hoag-4or0a U0), since resolve
# answers in first-reach order and gen-scope's own order cell pins that order. (2) COST, THUNKS
# ONLY: the resolve/query-orig marginal between each pair of consecutive sizes (the walk is super-linear
# by the fixture, so it has no linear pair), and the resolve arm's load at n=4 (spec OQ8). Alloc is
# reported and gated by nothing: no alloc gate is built on this row. (3) ARMING, every run: the
# `witnesses` arm (mode `witnesses`, the acyclic-path law,
# which enumerates every simple path and is factorial in n here) at n = 4..7 only — it never returns
# at n = 100 (gate P2) — must step 6 → 7 by at least RESOLUTION_WITNESSES_GROWTH_MIN and by more
# than resolve's own 6 → 7 step. A polynomial of degree d steps 6 → 7 by (7/6)^d, so ×3 needs d ≥
# 7.1: the floor separates enumeration from every walk this row could regress to. A control that
# does not read super-linear is a broken instrument, and the row then has no result. No linearity
# gate: the complete relation has n² edges, so the walk is quadratic in n by the fixture, and only a
# same-n ratio can see a regression.
#
RESOLUTION_SIZES=(4 5 6 7 100 1000)
RESOLUTION_WITNESSES_SIZES=(4 5 6 7)
RESOLUTION_WITNESSES_GROWTH_MIN=3.0

declare -A CPU CPU_SAMPLES THUNKS ALLOC DIG ATT
declare -A CR TR AR PAR
CELL_ERRF=""
CELL_OUT=""
declare -A LIN_SMALL LIN_BIG LIN_TG LIN_AG
declare -A CS_TR CS_AR CS_CR CS_BG
declare -A EM_TR EM_AR EM_CR EM_BG EM_LIN
declare -A CM_TR CM_AR CM_CR CM_BG CM_LIN
declare -A RS_TR RS_AR RS_CR RS_BG
RS_WIT_STEP=""
RS_RES_STEP=""
CS_LIN_FULL=""
CS_LIN_FIXED=""
declare -A OW_TR OW_AR OW_CR OW_BG
OW_LIN_COLD=""
OW_LIN_WARM=""
declare -A KM_TR KM_AR KM_CR KM_BG KM_LIN
KM_PLANT_TR=""
KM_PLANT_AR=""
TRA_PURE=""
TRA_REF=""
FAILURES=()
RATCHETS=()
REANCHOR_LINES=()
CELL=""

# ── a dead cell names itself (exit 3) ─────────────────────────────────────────
# A cell that cannot be MEASURED must not be reported, and it must say which cell it was: the whole
# bench is comparative, and the operator's next move is always to re-run one cell by hand. So the
# run aborts at the FIRST dead cell carrying that cell's identity and BOTH captured streams. Every
# downstream consumer of a cell's counters is unconditional (the ratios, the printf table, the
# small/big linearity pair), and --update would splice a holed table into the live BENCHMARKS.md
# block, where a table that does not announce its hole is worse than no table.
# An EMPTY stream is REPORTED as empty — rendering it as silence would be this defect in miniature.
die_cell() {
  local reason=$1 status=$2 errf=$3 out=$4
  {
    echo "perf-bench: CELL EVAL FAILED — $CELL exit=$status"
    echo "perf-bench: $reason"
    echo "-- begin evaluator stdout --"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out"
    else
      echo "(evaluator wrote nothing to stdout)"
    fi
    echo "-- end evaluator stdout --"
    echo "-- begin evaluator stderr ($errf) --"
    if [[ -s "$errf" ]]; then
      cat "$errf"
    else
      echo "(evaluator wrote nothing to stderr)"
    fi
    echo "-- end evaluator stderr --"
  } >&2
  exit 3
}

# Every value that reaches a table is validated HERE, where the cell's identity is still in scope.
# The counters are read through `jq -e … | numbers | select(. > 0)`, which collapses missing file,
# unparseable JSON, absent field, non-numeric and zero into one non-zero status (measured: 2, 5, 4,
# 4, 4 respectively). Zero is a refusal rather than a value because a zero counter is an ABSENT
# INSTRUMENT — `.gc.totalBytes` is simply not emitted by a Nix built without the collector, and a
# zero carried forward surfaces far downstream as an awk division-by-zero at report stage, after
# the entire matrix has been measured and with no cell named. jq's own stderr is left unredirected
# so its parse error reaches the operator ahead of the identity line.
#
# ONE REP of one cell. The counters and the digest are recorded on EVERY rep rather than read off the
# last rep after the loop: they are deterministic per Nix version, so the recorded value is the same
# either way, and validating each rep keeps every die_cell inside the scope that still holds that
# rep's captured streams. The captures are also published as CELL_ERRF/CELL_OUT for the one check
# that cannot run until every rep is in — the median, back in run_row.
sample_cell() {
  local w=$1 n=$2 s=$3 rep=$4
  local statf="$tmp/$w-$n-$s-$rep.json" errf="$tmp/$w-$n-$s-$rep.err"
  local out="" status cpu thunks alloc dig
  # A load cell receives the census's order as an argument: deriving it inside the cell would run the
  # census there and pre-pay every member's `import`, which is part of that member's own load.
  local -a order_arg=()
  [[ $w == load ]] && order_arg=(--arg order "$LOAD_ORDER_NIX")
  CELL="workload=$w n=$n stack=$s rep=$rep"
  # errexit fires at the ASSIGNMENT — a failing command substitution carries its own status, so a
  # bare redirect plus a later stats-file test would never be reached. The status is taken by hand.
  # GC_DONT_GC: the collector off makes `gc.totalBytes` one byte count per tree (header); the
  # evaluator then warns on stderr that it could not collect before reporting, which is expected.
  status=0
  out=$(GC_DONT_GC=1 NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$statf" nixi --eval --strict \
    "$PERF_WORKLOADS" --arg srcs "import $SRCS" \
    --argstr stack "$s" --argstr workload "$w" --arg n "$n" "${order_arg[@]}" 2>"$errf") || status=$?
  CELL_ERRF=$errf
  CELL_OUT=$out
  # A LIVE cell's capture is never printed: a warning or trace on the healthy path would move the
  # report's shape, which is what a cross-rev comparison of this bench reads.
  # The status is judged BEFORE the artefacts. An evaluator that fails while still leaving a
  # plausible stats file and a digest would otherwise be measured and REPORTED — a whole matrix of
  # fabricated figures carrying a confident regression verdict, which names the wrong defect
  # instead of merely losing the right one.
  [[ $status -eq 0 ]] || die_cell "evaluator exited non-zero" "$status" "$errf" "$out"
  [[ -s "$statf" ]] || die_cell "no stats file at $statf" "$status" "$errf" "$out"
  cpu=$(jq -e '.cpuTime | numbers | select(. > 0)' "$statf") \
    || die_cell "no usable .cpuTime in $statf" "$status" "$errf" "$out"
  thunks=$(jq -e '.nrThunks | numbers | select(. > 0)' "$statf") \
    || die_cell "no usable .nrThunks in $statf" "$status" "$errf" "$out"
  att=0
  for bf in envs list sets values symbols; do
    bv=$(jq -e ".$bf.bytes | numbers | select(. > 0)" "$statf") \
      || die_cell "the attributed-bytes field .$bf.bytes is zero or absent in $statf: the evaluator's accounting is not the anchored one" "$status" "$errf" "$out"
    att=$((att + bv))
  done
  alloc=$(jq -e '.gc.totalBytes | numbers | select(. > 0)' "$statf") \
    || die_cell "no usable .gc.totalBytes in $statf" "$status" "$errf" "$out"
  # The digest is the parity oracle's datum, and perf-bench.nix emits it for every cell: its absence
  # from a SUCCESSFUL eval means the workload contract moved, not that parity failed. Reporting that
  # as a MISMATCH would name the wrong defect, and on a `noref` row nothing reads the digest at all,
  # so the absence would pass entirely unseen — the same silence, one surface over.
  dig=$(printf '%s' "$out" | grep -o 'digest = "[a-f0-9]*"' | cut -d'"' -f2) || dig=""
  [[ -n "$dig" ]] || die_cell "eval succeeded but stdout carries no digest" "$status" "$errf" "$out"
  CPU_SAMPLES["$w,$n,$s"]+="$cpu"$'\n'
  THUNKS["$w,$n,$s"]=$thunks
  ALLOC["$w,$n,$s"]=$alloc
  ATT["$w,$n,$s"]=$att
  DIG["$w,$n,$s"]=$dig
}

# A ROW's arms, sampled ROUND-ROBIN: rep 1 of every arm, then rep 2 of every arm, and so on — never
# block-sampled (every rep of one arm, then every rep of the next). A blocked protocol reads two
# arms at two different moments, so on a host that changes frequency regime it fabricates the
# between-arm ratio whenever the transition falls between the blocks — measured 2.1× on IDENTICAL
# work — while the tight spread WITHIN each block reads as confidence, because the spread inside one
# regime genuinely is small. Interleaving does not make cpu deterministic; nothing does, which is why
# no gate reads it. It is the difference between a reported figure whose arms saw the same machine
# and one whose arms did not. The arm list is variadic because every comparison in this script is a
# row of arms: pure/ref, the single-arm noref rows, pure-full/pure-fixed, cold/warm.
run_row() {
  local w=$1 n=$2
  shift 2
  local rep s med
  for rep in $(seq 1 "$REPS"); do
    for s in "$@"; do
      sample_cell "$w" "$n" "$s" "$rep"
    done
  done
  for s in "$@"; do
    med=$(printf '%s' "${CPU_SAMPLES[$w,$n,$s]}" | sort -g | sed -n 2p) || med=""
    CELL="workload=$w n=$n stack=$s"
    [[ -n "$med" ]] || die_cell "the median of $REPS cpu samples is empty" 0 "$CELL_ERRF" "$CELL_OUT"
    CPU["$w,$n,$s"]=$med
  done
}

ratio() { awk "BEGIN{printf \"%.3f\", ($1)/($2)}"; }
lte() { awk "BEGIN{exit !(($1) <= ($2))}"; }
has_tag() { [[ ",$1," == *",$2,"* ]]; }

# ── the cost gate: EXACT and TWO-SIDED (den-hoag-r8y89) ───────────────────────
# A reading and a bound are each an integer count or a ratio of two, NUM/DEN. qcmp compares them by
# cross-multiplying in shell integers, never through a printed decimal: a %.3f step was a tolerance
# nobody chose, and two-sided it flaps at a rounding boundary (gate C6). It prints `bad` for anything
# that is not such a value — an absent bound or a non-numeric reading is UNMEASURED, never a pass.
# ponytail: 64-bit products; the largest gated pair today is ~1e9 B × ~1e9 B, 10× under the limit.
qcmp() {
  local a=$1 b=$2 an ad=1 bn bd=1
  [[ $a =~ ^[0-9]+(/[1-9][0-9]*)?$ && $b =~ ^[0-9]+(/[1-9][0-9]*)?$ ]] || {
    echo bad
    return
  }
  an=${a%/*} bn=${b%/*}
  [[ $a == */* ]] && ad=${a#*/}
  [[ $b == */* ]] && bd=${b#*/}
  if ((an * bd < bn * ad)); then echo lt; elif ((an * bd > bn * ad)); then echo gt; else echo eq; fi
}
qshow() { if [[ $1 == */* ]]; then awk -v q="$1" 'BEGIN{split(q, p, "/"); printf "%s (%.6f)", q, p[1] / p[2]}'; else printf '%s' "$1"; fi; }
# gate LABEL READING BOUND BOUND-NAME — above is a regression; below is `ratchet:`, which names the
# assignment that lowers the bound to the reading. Under an identity change (REANCHOR) nothing is
# judged: the reading is printed as the assignment a re-anchor would record.
gate() {
  local label=$1 reading=$2 bound=$3 name=$4
  if [[ -n $REANCHOR ]]; then
    REANCHOR_LINES+=("$name=$reading   # $label; was $bound")
    return
  fi
  case $(qcmp "$reading" "$bound") in
    eq) ;;
    gt) FAILURES+=("$label $(qshow "$reading") > $(qshow "$bound") ($name)") ;;
    lt) RATCHETS+=("ratchet: $label $(qshow "$reading") < $(qshow "$bound") — lower $name to $reading") ;;
    *) FAILURES+=("unmeasured: $label — reading '$reading' or bound '$bound' ($name) is not a count or NUM/DEN") ;;
  esac
}

# ── pre-flight: the formals residue of THIS combination, before any cell ──────
# Each member's entry object is applied with exactly the formals IT declares, read live with
# `builtins.functionArgs` at the path the call site imports. This census reads those lambdas without
# applying them, so one pass names EVERY member the combination cannot satisfy. The evaluator can
# only ever report the first offender a workload happens to force — and most workloads force none,
# which is how a combination that cannot be constructed collects and gates a full matrix and says
# nothing at all. A census that could not RUN is reported as UNMEASURED, never as an empty residue:
# an error consumed as an empty value is this bench's own die_cell doctrine one layer up.
PREFLIGHT=""
pf_status=0
PREFLIGHT=$(nixi --eval --strict --json "$PERF_WORKLOADS" \
  --arg srcs "import $SRCS" --argstr stack pure --argstr workload preflight --arg n 1 \
  2>"$tmp/preflight.err") || pf_status=$?
if [[ $pf_status -ne 0 ]]; then
  {
    echo "perf-bench: PRE-FLIGHT CENSUS FAILED exit=$pf_status — the residue is UNMEASURED, not empty; NO cells collected"
    cat "$tmp/preflight.err"
  } >&2
  exit 5
fi
PF_RESIDUE=$(printf '%s' "$PREFLIGHT" | jq -er '.residue | length | numbers') || PF_RESIDUE=""
if [[ -z "$PF_RESIDUE" ]]; then
  {
    echo "perf-bench: PRE-FLIGHT CENSUS UNREADABLE — it evaluated but carries no .residue; UNMEASURED, not empty"
    printf '%s\n' "$PREFLIGHT" | head -c 2000
  } >&2
  exit 5
fi
PF_ARMING=$(printf '%s' "$PREFLIGHT" | jq -r '"striking \"\(.arming.strike)\" from the environment fires on \(.arming.fires) of \(.arming.of) applied entries"')
PF_UNAPPLIED=$(printf '%s' "$PREFLIGHT" | jq -r '.unappliedEntries | join(", ")')
# The load cells' order, read from the corpus so the two cannot drift: perf-bench.nix `loadOrder`, derived from `loadMembers`.
LOAD_ORDER=()
while IFS= read -r lk; do LOAD_ORDER+=("$lk"); done < <(printf '%s' "$PREFLIGHT" | jq -er '.loadOrder[] | strings')
LOAD_ORDER_NIX="[ $(printf '"%s" ' "${LOAD_ORDER[@]}")]"
if [[ ${#LOAD_ORDER[@]} -eq 0 ]]; then
  echo "perf-bench: PRE-FLIGHT CENSUS UNREADABLE — it carries no .loadOrder, so no member's load can be measured; UNMEASURED, not empty" >&2
  exit 5
fi
declare -A PF_LEAK
while IFS=$'\t' read -r lk lv; do PF_LEAK[$lk]=$lv; done < <(
  printf '%s' "$PREFLIGHT" | jq -r '.leaks[] | "\(.member)\t\(.leak | join(", "))"'
)
if [[ "$PF_RESIDUE" -ne 0 ]]; then
  {
    echo "perf-bench: SUPPLY/DEMAND RESIDUE — $PF_RESIDUE member(s) require a formal no key in this source set can name; NO cells collected"
    printf '%s' "$PREFLIGHT" | jq -r '.residue[] | "  - \(.member) (\(.entry)) UNSAT=[\(.unsat | join(", "))]"'
    echo "  arming, same predicate: $PF_ARMING — so an empty residue on another run is a reading, not a dead check"
  } >&2
  exit 5
fi

# ── the run's identity, against the anchor's (exit 4 if unreadable) ──────────
# Read BEFORE any cell and before any verdict, so a run under another identity never declares green
# and never splices (gate C4). An identity that cannot be read is UNRESOLVED, not "unchanged".
EVAL_ID=""
id_st=0
EVAL_ID=$(nix-instantiate --version 2>"$tmp/id.err") || id_st=$?
eval_store=$(readlink -f "$(command -v nix-instantiate)") || id_st=$?
eval_store=${eval_store%/bin/*}
nix-store --query --requisites "$eval_store" >"$tmp/id.closure" 2>>"$tmp/id.err" || id_st=$?
ALLOC_IDS=()
while IFS= read -r cp; do
  [[ $cp =~ ^/nix/store/[a-z0-9]{32}-(boehm-gc-[^/]+)$ ]] && ALLOC_IDS+=("${BASH_REMATCH[1]}")
done <"$tmp/id.closure"
if [[ $id_st -ne 0 || -z "$EVAL_ID" || ${#ALLOC_IDS[@]} -ne 1 ]]; then
  {
    echo "perf-bench: EVALUATOR IDENTITY UNRESOLVED — nix exit $id_st, version '${EVAL_ID}', ${#ALLOC_IDS[@]} boehm-gc path(s) in the closure of '$eval_store' (exactly one is required); NO cells collected"
    cat "$tmp/id.err"
  } >&2
  exit 4
fi
ALLOC_ID=${ALLOC_IDS[0]}
# The host's nix-path is part of the alloc identity (NIX_PIN, above). Read it the way every cell is
# evaluated; anything but an empty list means the pin was lost and the host reaches the readings.
np_st=0
NIX_PATH_SEEN=$(nixi --eval --strict --json --expr builtins.nixPath 2>"$tmp/np.err") || np_st=$?
if [[ $np_st -ne 0 || "$NIX_PATH_SEEN" != "[]" ]]; then
  {
    echo "perf-bench: HOST NIX-PATH REACHES THE EVALUATOR — builtins.nixPath read '${NIX_PATH_SEEN}' (nix exit $np_st), not []; its value moves alloc readings, so the --option nix-path '' pin (NIX_PIN) is lost; NO cells collected"
    cat "$tmp/np.err"
  } >&2
  exit 4
fi
REF_ID=$(jq -er '[to_entries[] | select(.value.axis == "reference") | "\(.key)=\(.value.rev)"] | sort | join(" ")' "$PERF_COMBINATION")
# The members this run MEASURES: an overlay replaces its key's revision unless it resolved to the
# baseline's own source; a `path:` overlay has no revision, so it never matches the anchor.
mem_ids=()
for ck in "${COMB_KEYS[@]}"; do
  [[ "${BASE_AXIS[$ck]}" == reference ]] && continue
  mrev=${BASE_REV[$ck]}
  if [[ -n "${AT_STORE[$ck]:-}" && "${AT_STORE[$ck]}" != "${BASE_STORE[$ck]}" ]]; then mrev=${AT_REV[$ck]}; fi
  mem_ids+=("$ck=$mrev")
done
MEMBERS_ID=$(printf '%s\n' "${mem_ids[@]}" | LC_ALL=C sort | paste -sd ' ')
REANCHOR=""
if [[ "$EVAL_ID" != "$ANCHOR_EVALUATOR" || "$ALLOC_ID" != "$ANCHOR_ALLOCATOR" || "$REF_ID" != "$ANCHOR_REFERENCE" ]]; then
  REANCHOR=1
fi

# ── measure ──────────────────────────────────────────────────────────────────
echo "collecting: ${#MATRIX[@]} cells (pure) + the ref arm of every non-noref row × $REPS reps ..." >&2
for row in "${MATRIX[@]}"; do
  read -r w n tags <<<"$row"
  if has_tag "$tags" noref; then
    run_row "$w" "$n" pure
  else
    run_row "$w" "$n" pure ref
  fi
done

# The load cells: one rep each, since a counter is deterministic and their cpu is reported nowhere.
for k in none "${LOAD_ORDER[@]}"; do
  sample_cell load 1 "$k" 1
done

# ── compute ratios + gate outcomes (no printing; emit_report reads these) ──────
# Every member has a load cell, and every load cell is a member: a member outside `loadOrder` would
# load ungated, and the census is what says so.
for ck in "${COMB_KEYS[@]}"; do
  [[ "${BASE_AXIS[$ck]}" == reference ]] && continue
  [[ " ${LOAD_ORDER[*]} " == *" $ck "* ]] || FAILURES+=("unmeasured: load: member $ck has no load cell (perf-bench.nix loadMembers)")
done
for k in "${LOAD_ORDER[@]}"; do
  [[ "${BASE_AXIS[$k]:-}" == member ]] || FAILURES+=("load: loadMembers names $k, which is not a member of the combination")
done
for row in "${MATRIX[@]}"; do
  read -r w n tags <<<"$row"
  # noref rows have no reference cell: no ratio is computable and no parity verdict is asserted.
  if has_tag "$tags" noref; then
    continue
  fi
  CR["$w,$n"]=$(ratio "${CPU[$w,$n,pure]}" "${CPU[$w,$n,ref]}")
  TR["$w,$n"]=$(ratio "${THUNKS[$w,$n,pure]}" "${THUNKS[$w,$n,ref]}")
  AR["$w,$n"]=$(ratio "${ALLOC[$w,$n,pure]}" "${ALLOC[$w,$n,ref]}")
  if [[ "${DIG[$w,$n,pure]}" == "${DIG[$w,$n,ref]}" && -n "${DIG[$w,$n,pure]}" ]]; then
    PAR["$w,$n"]="ok"
  else
    PAR["$w,$n"]="MISMATCH"
    FAILURES+=("parity: $w n=$n pure=${DIG[$w,$n,pure]:-<none>} ref=${DIG[$w,$n,ref]:-<none>}")
  fi
  # CR, TR and AR are printed, gated by nothing: the cost gates read the raw counters as marginals
  # (the marginal and load section, below the report).
done

for w in scalar registry threadedRegistry wrappedRegistry steppedRegistry schemaHosts inheritHosts aspects wideFreeform deepSubmodule foreignMount moduleFanIn sameLocFanIn; do
  small_n=""
  big_n=""
  for row in "${MATRIX[@]}"; do
    read -r rw rn tags <<<"$row"
    [[ "$rw" == "$w" ]] && has_tag "$tags" small && small_n=$rn
    [[ "$rw" == "$w" ]] && has_tag "$tags" big && big_n=$rn
  done
  LIN_SMALL["$w"]=$small_n
  LIN_BIG["$w"]=$big_n
  LIN_TG["$w"]=$(ratio "${THUNKS[$w,$big_n,pure]}" "${THUNKS[$w,$small_n,pure]}")
  LIN_AG["$w"]=$(ratio "${ALLOC[$w,$big_n,pure]}" "${ALLOC[$w,$small_n,pure]}")
  lte "${LIN_TG[$w]}" "$GROWTH_MAX" || FAILURES+=("linearity: $w thunks grew ${LIN_TG[$w]}× over a 4× size step")
  lte "${LIN_AG[$w]}" "$GROWTH_MAX" || FAILURES+=("linearity: $w alloc grew ${LIN_AG[$w]}× over a 4× size step")
done

# ── classShare — the gen-class tier-2 fixed-input spine gate (spec §2.5) ────────
# DEDICATED section: classShare's two "stacks" are pure-full / pure-fixed (both the PURE engine), so
# its ratios are fixed-vs-full — NOT the pure-vs-ref parity/counter-ratio semantics of the matrix loop
# above. It runs its own two sizes × REPS, asserts the in-bench BYTE gate (full == fixed byte-for-byte,
# the perf-scale twin of gateCore), gates the fixed arm's own thunks (re-based, den-hoag-r8y89), and owns its
# linearity growth check. Failures print expected/actual/delta (the verbose STOP-on-diff discipline).
delta() { awk "BEGIN{printf \"%+.4f\", ($1)-($2)}"; }
for n in "$CLASSSHARE_SMALL" "$CLASSSHARE_BIG"; do
  run_row classShare "$n" pure-full pure-fixed
  # BYTE GATE (in-bench): the fixed-input reconstruction must be byte-identical to the full re-merge.
  if [[ -n "${DIG[classShare,$n,pure-full]}" && "${DIG[classShare,$n,pure-full]}" == "${DIG[classShare,$n,pure-fixed]}" ]]; then
    CS_BG[$n]="ok"
  else
    CS_BG[$n]="MISMATCH"
    FAILURES+=("classShare byte gate: n=$n expected(full)=${DIG[classShare,$n,pure-full]:-<none>} actual(fixed)=${DIG[classShare,$n,pure-fixed]:-<none>}")
  fi
  CS_TR[$n]=$(ratio "${THUNKS[classShare,$n,pure-fixed]}" "${THUNKS[classShare,$n,pure-full]}")
  CS_AR[$n]=$(ratio "${ALLOC[classShare,$n,pure-fixed]}" "${ALLOC[classShare,$n,pure-full]}")
  CS_CR[$n]=$(ratio "${CPU[classShare,$n,pure-fixed]}" "${CPU[classShare,$n,pure-full]}")
  # COST gate (re-based, den-hoag-r8y89): the fixed-input arm's OWN thunks; the ratio is printed.
done
# LINEARITY: both stacks stay linear in the core size (a quadratic core-merge blowup would fail here).
CS_LIN_FULL=$(ratio "${THUNKS[classShare,$CLASSSHARE_BIG,pure-full]}" "${THUNKS[classShare,$CLASSSHARE_SMALL,pure-full]}")
CS_LIN_FIXED=$(ratio "${THUNKS[classShare,$CLASSSHARE_BIG,pure-fixed]}" "${THUNKS[classShare,$CLASSSHARE_SMALL,pure-fixed]}")
lte "$CS_LIN_FULL" "$GROWTH_MAX" \
  || FAILURES+=("classShare linearity: pure-full thunks expected≤$GROWTH_MAX actual=${CS_LIN_FULL}× delta=$(delta "$CS_LIN_FULL" "$GROWTH_MAX") over a 4× size step")
lte "$CS_LIN_FIXED" "$GROWTH_MAX" \
  || FAILURES+=("classShare linearity: pure-fixed thunks expected≤$GROWTH_MAX actual=${CS_LIN_FIXED}× delta=$(delta "$CS_LIN_FIXED" "$GROWTH_MAX") over a 4× size step")

# ── overrideWarm — the gen-merge warm re-eval (memoized override) gate (README §"Warm re-eval") ──
# DEDICATED section (classShare precedent): the two "stacks" are cold / warm (both the pure engine), so
# its ratios are warm-vs-cold — a class of `overrides` edits over one base, cold re-merging the shared
# registry per override, warm merging it ONCE (`prev`) and splicing it into each. It asserts the in-bench
# BYTE gate (warm == cold byte-for-byte, the perf-scale twin of gen-merge's warm-vs-cold byte oracle),
# gates the warm arm's own thunks AND alloc (re-based, den-hoag-r8y89), and owns its linearity check.
for n in "$OVERRIDEWARM_SMALL" "$OVERRIDEWARM_BIG"; do
  run_row overrideWarm "$n" cold warm
  # BYTE GATE (in-bench): the warm re-eval must be byte-identical to the cold from-scratch eval.
  if [[ -n "${DIG[overrideWarm,$n,cold]}" && "${DIG[overrideWarm,$n,cold]}" == "${DIG[overrideWarm,$n,warm]}" ]]; then
    OW_BG[$n]="ok"
  else
    OW_BG[$n]="MISMATCH"
    FAILURES+=("overrideWarm byte gate: n=$n expected(cold)=${DIG[overrideWarm,$n,cold]:-<none>} actual(warm)=${DIG[overrideWarm,$n,warm]:-<none>}")
  fi
  OW_TR[$n]=$(ratio "${THUNKS[overrideWarm,$n,warm]}" "${THUNKS[overrideWarm,$n,cold]}")
  OW_AR[$n]=$(ratio "${ALLOC[overrideWarm,$n,warm]}" "${ALLOC[overrideWarm,$n,cold]}")
  OW_CR[$n]=$(ratio "${CPU[overrideWarm,$n,warm]}" "${CPU[overrideWarm,$n,cold]}")
  # COST gate (re-based, den-hoag-r8y89): the warm arm's OWN thunks and alloc; the ratios are printed.
done
# LINEARITY: both stacks stay linear in the registry size (a quadratic base merge would fail here).
OW_LIN_COLD=$(ratio "${THUNKS[overrideWarm,$OVERRIDEWARM_BIG,cold]}" "${THUNKS[overrideWarm,$OVERRIDEWARM_SMALL,cold]}")
OW_LIN_WARM=$(ratio "${THUNKS[overrideWarm,$OVERRIDEWARM_BIG,warm]}" "${THUNKS[overrideWarm,$OVERRIDEWARM_SMALL,warm]}")
lte "$OW_LIN_COLD" "$GROWTH_MAX" \
  || FAILURES+=("overrideWarm linearity: cold thunks expected≤$GROWTH_MAX actual=${OW_LIN_COLD}× delta=$(delta "$OW_LIN_COLD" "$GROWTH_MAX") over a 4× size step")
lte "$OW_LIN_WARM" "$GROWTH_MAX" \
  || FAILURES+=("overrideWarm linearity: warm thunks expected≤$GROWTH_MAX actual=${OW_LIN_WARM}× delta=$(delta "$OW_LIN_WARM" "$GROWTH_MAX") over a 4× size step")

# ── kindMatch — kind identity at scale (den-hoag-l0y; the gate derivation is beside the constants) ──
# DEDICATED section (classShare precedent). Per fixture, the stacks are attrs-ref (the FROZEN
# gen-select's `sel.attrs`, the denominator) and kind (the live `sel.kind`); the sealed fixture's
# stacks carry the `-sealed` suffix.
for fx in migrated sealed; do
  sfx=""
  [[ "$fx" == sealed ]] && sfx="-sealed"
  for n in "$KINDMATCH_SMALL" "$KINDMATCH_BIG"; do
    run_row kindMatch "$n" "attrs-ref$sfx" "kind$sfx"
    den="${DIG[kindMatch,$n,attrs-ref$sfx]}"
    num="${DIG[kindMatch,$n,kind$sfx]}"
    # BYTE GATE: sel.kind A selects exactly the A instances, as the attrs match on A's value does.
    if [[ -n "$den" && "$den" == "$num" ]]; then
      KM_BG[$fx,$n]="ok"
    else
      KM_BG[$fx,$n]="MISMATCH"
      FAILURES+=("kindMatch byte gate ($fx): n=$n expected(attrs-ref)=${den:-<none>} actual(kind)=${num:-<none>} — sel.kind selected a different node set (a name key conflating two same-name kinds selects all n)")
    fi
    KM_TR[$fx,$n]=$(ratio "${THUNKS[kindMatch,$n,kind$sfx]}" "${THUNKS[kindMatch,$n,attrs-ref$sfx]}")
    KM_AR[$fx,$n]=$(ratio "${ALLOC[kindMatch,$n,kind$sfx]}" "${ALLOC[kindMatch,$n,attrs-ref$sfx]}")
    KM_CR[$fx,$n]=$(ratio "${CPU[kindMatch,$n,kind$sfx]}" "${CPU[kindMatch,$n,attrs-ref$sfx]}")
  done
  for s in "attrs-ref$sfx" "kind$sfx"; do
    KM_LIN[$s]=$(ratio "${THUNKS[kindMatch,$KINDMATCH_BIG,$s]}" "${THUNKS[kindMatch,$KINDMATCH_SMALL,$s]}")
    lte "${KM_LIN[$s]}" "$GROWTH_MAX" \
      || FAILURES+=("kindMatch linearity: $s thunks expected≤$GROWTH_MAX actual=${KM_LIN[$s]}× delta=$(delta "${KM_LIN[$s]}" "$GROWTH_MAX") over a 4× size step")
  done
done
# ARMING, every run: the planted per-node recompute (`kind-plant`: kindFor re-derives each node's
# kind) at the small size, on the migrated fixture. It selects the same nodes, so its byte gate must
# hold, and the thunk bound must refuse it; a plant the bound admits means the row cannot see the
# class it exists for.
sample_cell kindMatch "$KINDMATCH_SMALL" kind-plant 1
KM_PLANT_TR=$(ratio "${THUNKS[kindMatch,$KINDMATCH_SMALL,kind-plant]}" "${THUNKS[kindMatch,$KINDMATCH_SMALL,attrs-ref]}")
KM_PLANT_AR=$(ratio "${ALLOC[kindMatch,$KINDMATCH_SMALL,kind-plant]}" "${ALLOC[kindMatch,$KINDMATCH_SMALL,attrs-ref]}")
[[ "${DIG[kindMatch,$KINDMATCH_SMALL,kind-plant]}" == "${DIG[kindMatch,$KINDMATCH_SMALL,attrs-ref]}" ]] \
  || FAILURES+=("kindMatch arming: the planted per-node recompute selected a different node set (${DIG[kindMatch,$KINDMATCH_SMALL,kind-plant]}) — the plant no longer isolates cost")

# ── threadedRegistry arming, every run: does the row reach the threaded path? ───────────────────
# The planted element's `substSubModules` throws a token generated here and never written down
# whenever it is handed gen-merge's thread marker (a one-item module list whose `_file` is
# gen-merge's sentinel) and forwards every real module list. Only gen-merge's threaded rebuild
# channel hands it the marker, so `pure-plant` must die naming the token and `ref-plant` must evaluate. A
# pure arm that evaluates means the row folds some other way and its bounds price nothing of the
# channel; a ref arm that dies means the plant does not isolate it.
tra_token=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
[[ ${#tra_token} -eq 24 ]] || { echo "perf-bench: could not generate the threadedRegistry arming token" >&2; exit 4; }
for s in pure-plant ref-plant; do
  status=0
  nixi --eval --strict "$PERF_WORKLOADS" --arg srcs "import $SRCS" \
    --argstr stack "$s" --argstr workload threadedRegistry --arg n 4 --argstr token "$tra_token" \
    >"$tmp/tra-$s.out" 2>"$tmp/tra-$s.err" || status=$?
  hits=$(grep -c -- "$tra_token" "$tmp/tra-$s.err") || hits=0
  if [[ "$s" == pure-plant ]]; then
    TRA_PURE="exit $status, token lines $hits"
    [[ $status -ne 0 && $hits -gt 0 ]] \
      || FAILURES+=("threadedRegistry arming: pure-plant read $TRA_PURE — the pure arm does not reach gen-merge's threaded channel, so the row prices nothing of it")
  else
    TRA_REF="exit $status, token lines $hits"
    [[ $status -eq 0 && $hits -eq 0 ]] \
      || FAILURES+=("threadedRegistry arming: ref-plant read $TRA_REF — the plant fires without the threaded channel, so it does not isolate it")
  fi
done

# ── entityMatch — instance identity at scale (den-hoag-l0y U2; the gate derivation is beside the constants) ──
for fx in migrated sealed; do
  sfx=""
  [[ "$fx" == sealed ]] && sfx="-sealed"
  for n in "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG"; do
    run_row entityMatch "$n" "attrs-ref$sfx" "entity$sfx"
    den="${DIG[entityMatch,$n,attrs-ref$sfx]}"
    num="${DIG[entityMatch,$n,entity$sfx]}"
    # PROJECTION GATE: the entity selects its own half's `h0` alone; the control selects both halves.
    if [[ "$num" == "$ENTITYMATCH_DIGEST_ENTITY" && "$den" == "$ENTITYMATCH_DIGEST_REF" ]]; then
      EM_BG[$fx,$n]="ok"
    else
      EM_BG[$fx,$n]="MISMATCH"
      FAILURES+=("entityMatch projection gate ($fx): n=$n expected entity=$ENTITYMATCH_DIGEST_ENTITY attrs-ref=$ENTITYMATCH_DIGEST_REF actual entity=${num:-<none>} attrs-ref=${den:-<none>} — a stamp keyed by the kind name selects both same-name halves")
    fi
    EM_TR[$fx,$n]=$(ratio "${THUNKS[entityMatch,$n,entity$sfx]}" "${THUNKS[entityMatch,$n,attrs-ref$sfx]}")
    EM_AR[$fx,$n]=$(ratio "${ALLOC[entityMatch,$n,entity$sfx]}" "${ALLOC[entityMatch,$n,attrs-ref$sfx]}")
    EM_CR[$fx,$n]=$(ratio "${CPU[entityMatch,$n,entity$sfx]}" "${CPU[entityMatch,$n,attrs-ref$sfx]}")
  done
  for s in "attrs-ref$sfx" "entity$sfx"; do
    EM_LIN[$s]=$(ratio "${THUNKS[entityMatch,$ENTITYMATCH_BIG,$s]}" "${THUNKS[entityMatch,$ENTITYMATCH_SMALL,$s]}")
    lte "${EM_LIN[$s]}" "$GROWTH_MAX" \
      || FAILURES+=("entityMatch linearity: $s thunks expected≤$GROWTH_MAX actual=${EM_LIN[$s]}× delta=$(delta "${EM_LIN[$s]}" "$GROWTH_MAX") over a 4× size step")
  done
done
# ARMING, every run: the planted per-instance kind re-derivation (`entity-plant`) at the small size.
# It selects the same node, so its projection must hold, and the thunk bound must refuse it.
sample_cell entityMatch "$ENTITYMATCH_SMALL" entity-plant 1
EM_PLANT_TR=$(ratio "${THUNKS[entityMatch,$ENTITYMATCH_SMALL,entity-plant]}" "${THUNKS[entityMatch,$ENTITYMATCH_SMALL,attrs-ref]}")
EM_PLANT_AR=$(ratio "${ALLOC[entityMatch,$ENTITYMATCH_SMALL,entity-plant]}" "${ALLOC[entityMatch,$ENTITYMATCH_SMALL,attrs-ref]}")
[[ "${DIG[entityMatch,$ENTITYMATCH_SMALL,entity-plant]}" == "$ENTITYMATCH_DIGEST_ENTITY" ]] \
  || FAILURES+=("entityMatch arming: the planted per-instance re-derivation selected a different node set (${DIG[entityMatch,$ENTITYMATCH_SMALL,entity-plant]}) — the plant no longer isolates cost")

# ── coordMatch — the product coordinate's identity decision at scale (den-hoag-8hqx0; the gate derivation is beside the constants) ──
for fx in migrated sealed; do
  sfx=""
  [[ "$fx" == sealed ]] && sfx="-sealed"
  for n in "$COORDMATCH_SMALL" "$COORDMATCH_BIG"; do
    run_row coordMatch "$n" "coord-ref$sfx" "coord$sfx"
    den="${DIG[coordMatch,$n,coord-ref$sfx]}"
    num="${DIG[coordMatch,$n,coord$sfx]}"
    if [[ "$num" == "$COORDMATCH_DIGEST" && "$den" == "$COORDMATCH_DIGEST" ]]; then
      CM_BG[$fx,$n]="ok"
    else
      CM_BG[$fx,$n]="MISMATCH"
      FAILURES+=("coordMatch projection gate ($fx): n=$n expected coord=coord-ref=$COORDMATCH_DIGEST actual coord=${num:-<none>} coord-ref=${den:-<none>} — the coordinate selects a different cell set")
    fi
    CM_TR[$fx,$n]=$(ratio "${THUNKS[coordMatch,$n,coord$sfx]}" "${THUNKS[coordMatch,$n,coord-ref$sfx]}")
    CM_AR[$fx,$n]=$(ratio "${ALLOC[coordMatch,$n,coord$sfx]}" "${ALLOC[coordMatch,$n,coord-ref$sfx]}")
    CM_CR[$fx,$n]=$(ratio "${CPU[coordMatch,$n,coord$sfx]}" "${CPU[coordMatch,$n,coord-ref$sfx]}")
  done
  for s in "coord-ref$sfx" "coord$sfx"; do
    CM_LIN[$s]=$(ratio "${THUNKS[coordMatch,$COORDMATCH_BIG,$s]}" "${THUNKS[coordMatch,$COORDMATCH_SMALL,$s]}")
    lte "${CM_LIN[$s]}" "$GROWTH_MAX" \
      || FAILURES+=("coordMatch linearity: $s thunks expected≤$GROWTH_MAX actual=${CM_LIN[$s]}× delta=$(delta "${CM_LIN[$s]}" "$GROWTH_MAX") over a 4× size step")
  done
done

# ── resolution — the one resolution calculus at scale (den-hoag-gayc U2b; the gate derivation is beside the constants) ──
for n in "${RESOLUTION_SIZES[@]}"; do
  run_row resolution "$n" query-orig resolve
  den="${DIG[resolution,$n,query-orig]}"
  num="${DIG[resolution,$n,resolve]}"
  if [[ -n "$den" && "$den" == "$num" ]]; then
    RS_BG[$n]="ok"
  else
    RS_BG[$n]="MISMATCH"
    FAILURES+=("resolution byte gate: n=$n expected(query-orig)=${den:-<none>} actual(resolve)=${num:-<none>} — resolve reached a different node set (both sides are sorted, so order is not compared)")
  fi
  RS_TR[$n]=$(ratio "${THUNKS[resolution,$n,resolve]}" "${THUNKS[resolution,$n,query-orig]}")
  RS_AR[$n]=$(ratio "${ALLOC[resolution,$n,resolve]}" "${ALLOC[resolution,$n,query-orig]}")
  RS_CR[$n]=$(ratio "${CPU[resolution,$n,resolve]}" "${CPU[resolution,$n,query-orig]}")
done
# ARMING, every run: the witnesses control at n ≤ 7 must read super-linear (P2 pins it there).
for n in "${RESOLUTION_WITNESSES_SIZES[@]}"; do
  sample_cell resolution "$n" witnesses 1
done
RS_WIT_STEP=$(ratio "${THUNKS[resolution,7,witnesses]}" "${THUNKS[resolution,6,witnesses]}")
RS_RES_STEP=$(ratio "${THUNKS[resolution,7,resolve]}" "${THUNKS[resolution,6,resolve]}")
if lte "$RS_WIT_STEP" "$RESOLUTION_WITNESSES_GROWTH_MIN" || lte "$RS_WIT_STEP" "$RS_RES_STEP"; then
  FAILURES+=("resolution arming: the witnesses control stepped 6 → 7 by ${RS_WIT_STEP}× (resolve ${RS_RES_STEP}×), not above $RESOLUTION_WITNESSES_GROWTH_MIN and above resolve — the control is not super-linear, so the instrument is broken and this row has no result")
fi

# ── report (pure printing from the computed values above) ──────────────────────
emit_report() {
  echo
  echo "## gen module-system perf bench (pure vs pinned nixpkgs.lib stack)"
  echo
  # ── the combination block: the population, printed BEFORE the matrix that reads it ──
  # Without this the report says what it measured but never which sources it measured it over, and
  # an overlay that resolved to the baseline would be indistinguishable from one that applied. An
  # entry that changes nothing is announced as `no-op` rather than quietly accepted.
  echo "### combination under test"
  echo
  echo "| key | axis | source | rev / path | leak |"
  echo "|---|---|---|---|---|"
  for ck in "${COMB_KEYS[@]}"; do
    # A member is pinned by the root flake.lock (the hub's ci reads the root flake at `self`); a
    # reference key is ci's own declaration, pinned by ci/flake.lock.
    if [[ "${BASE_AXIS[$ck]}" == reference ]]; then csrc="baseline (ci/flake.lock)"; else csrc="baseline (flake.lock)"; fi
    crev="${BASE_REV[$ck]:0:12}"
    if [[ -n "${AT_STORE[$ck]:-}" ]]; then
      crev="${AT_REV[$ck]}"
      if [[ "${AT_STORE[$ck]}" == "${BASE_STORE[$ck]}" ]]; then
        csrc="overlay \`${AT_SRC[$ck]}\` — **no-op**, it resolves to the baseline source"
      else
        csrc="overlay \`${AT_SRC[$ck]}\`"
      fi
    fi
    printf '| %s | %s | %s | %s | %s |\n' "$ck" "${BASE_AXIS[$ck]}" "$csrc" "$crev" "${PF_LEAK[$ck]:-—}"
  done
  echo
  printf '> The leak column is the DEFAULTED formals this source set cannot name, so they resolved from that member'\''s OWN lock rather than from the combination above — gen-graph is not a key here, which is why a leak is a declared class and not a refusal. The REQUIRED-and-unnameable residue is empty, or this run would have refused at exit 5 before collecting a cell; arming, same predicate: %s. Entries that are not functions, so they declare no formals to read: %s. The five reference keys do not take --at, because a ratio'\''s denominator is its control.\n' \
    "$PF_ARMING" "$PF_UNAPPLIED"
  echo
  echo "| workload | n | ref cpu (s) | pure cpu (s) | cpu p/r | thunks p/r | alloc p/r | parity |"
  echo "|---|---:|---:|---:|---:|---:|---:|---|"
  for row in "${MATRIX[@]}"; do
    read -r w n tags <<<"$row"
    has_tag "$tags" noref && continue
    printf '| %s | %s | %.3f | %.3f | %s | %s | %s | %s |\n' \
      "$w" "$n" "${CPU[$w,$n,ref]}" "${CPU[$w,$n,pure]}" \
      "${CR[$w,$n]}" "${TR[$w,$n]}" "${AR[$w,$n]}" "${PAR[$w,$n]}"
  done
  echo
  printf '> The ratios are printed to three places; the gates do not read them. Every cost row gates its MARGINAL, the counter at its big size minus the counter at its small size (a ratio row: the pure marginal over the ref marginal, NUM/DEN), EXACTLY and two-sidedly against MARG_MAX: above it is a regression, below it is a ratchet: owed in the same change. Alloc is gated as the evaluator-attributed bytes, not gc.totalBytes. The per-process constant is gated apart, in the load table below. The cpu column is report-only on every row: cpu depends on the machine as well as on the expression, so no gate reads it (median of %s interleaved samples, collector off). See ci/README.md.\n' "$REPS"
  echo
  echo "### pure-only workloads (no reference arm; report-only counters, gated on linearity below)"
  echo
  echo "| workload | n | pure cpu (s) | pure thunks | pure alloc |"
  echo "|---|---:|---:|---:|---:|"
  for row in "${MATRIX[@]}"; do
    read -r w n tags <<<"$row"
    has_tag "$tags" noref || continue
    printf '| %s | %s | %.3f | %s | %s |\n' \
      "$w" "$n" "${CPU[$w,$n,pure]}" "${THUNKS[$w,$n,pure]}" "${ALLOC[$w,$n,pure]}"
  done
  echo
  echo "> These rows carry NO pure/ref digest parity and NO pure/ref win-gate: a frozen reference cannot"
  echo "> track a grammar that moves by design ruling, so such a gate would red on ruled improvements"
  echo "> rather than on regressions. Their linearity gates and absolute counters are unaffected."
  echo
  printf '> threadedRegistry arming (the planted element throws a fresh token only the threaded channel reaches): pure-plant %s (must die naming it); ref-plant %s (must evaluate).\n' "$TRA_PURE" "$TRA_REF"
  echo
  echo "### linearity (pure stack, ×4 size step; linear ≈ 4.0, gate ≤ $GROWTH_MAX)"
  echo
  echo "| workload | sizes | thunk growth | alloc growth |"
  echo "|---|---|---:|---:|"
  for w in scalar registry threadedRegistry wrappedRegistry steppedRegistry schemaHosts inheritHosts aspects wideFreeform deepSubmodule foreignMount moduleFanIn sameLocFanIn; do
    printf '| %s | %s → %s | %s | %s |\n' \
      "$w" "${LIN_SMALL[$w]}" "${LIN_BIG[$w]}" "${LIN_TG[$w]}" "${LIN_AG[$w]}"
  done
  echo
  echo "### classShare (gen-class tier-2 fixed-input spine gate; pure-full vs pure-fixed; gated: the pure-fixed thunk marginal and its load; the ratios printed)"
  echo
  echo "| n | full thunks | fixed thunks | thunks f/f | alloc f/f | cpu f/f | byte gate |"
  echo "|---|---:|---:|---:|---:|---:|---|"
  for n in "$CLASSSHARE_SMALL" "$CLASSSHARE_BIG"; do
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
      "$n" "${THUNKS[classShare,$n,pure-full]}" "${THUNKS[classShare,$n,pure-fixed]}" \
      "${CS_TR[$n]}" "${CS_AR[$n]}" "${CS_CR[$n]}" "${CS_BG[$n]}"
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): pure-full %s×, pure-fixed %s× (gate ≤ %s)\n' \
    "$CLASSSHARE_SMALL" "$CLASSSHARE_BIG" "$CS_LIN_FULL" "$CS_LIN_FIXED" "$GROWTH_MAX"
  echo
  echo "### overrideWarm (gen-merge warm re-eval / memoized override; cold vs warm; gated: the warm thunk and alloc marginals and its load; the ratios printed)"
  echo
  echo "| n | cold thunks | warm thunks | thunks w/c | alloc w/c | cpu w/c | byte gate |"
  echo "|---|---:|---:|---:|---:|---:|---|"
  for n in "$OVERRIDEWARM_SMALL" "$OVERRIDEWARM_BIG"; do
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
      "$n" "${THUNKS[overrideWarm,$n,cold]}" "${THUNKS[overrideWarm,$n,warm]}" \
      "${OW_TR[$n]}" "${OW_AR[$n]}" "${OW_CR[$n]}" "${OW_BG[$n]}"
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): cold %s×, warm %s× (gate ≤ %s)\n' \
    "$OVERRIDEWARM_SMALL" "$OVERRIDEWARM_BIG" "$OW_LIN_COLD" "$OW_LIN_WARM" "$GROWTH_MAX"
  echo
  echo "### kindMatch (kind identity at scale, den-hoag-l0y; frozen-gen-select attrs-ref vs live kind; gated: the kind thunk and alloc marginals and its load; the ratios printed)"
  echo
  echo "| fixture | n | attrs-ref thunks | kind thunks | kind alloc | thunks k/a | alloc k/a | cpu k/a | byte gate |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$KINDMATCH_SMALL" "$KINDMATCH_BIG"; do
      printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[kindMatch,$n,attrs-ref$sfx]}" "${THUNKS[kindMatch,$n,kind$sfx]}" \
        "${ALLOC[kindMatch,$n,kind$sfx]}" "${KM_TR[$fx,$n]}" "${KM_AR[$fx,$n]}" "${KM_CR[$fx,$n]}" "${KM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): attrs-ref %s×, kind %s×, attrs-ref-sealed %s×, kind-sealed %s× (gate ≤ %s)\n' \
    "$KINDMATCH_SMALL" "$KINDMATCH_BIG" "${KM_LIN[attrs-ref]}" "${KM_LIN[kind]}" "${KM_LIN[attrs-ref-sealed]}" "${KM_LIN[kind-sealed]}" "$GROWTH_MAX"
  printf 'arming (planted per-node recompute, n=%s→%s): kind thunk marginal %s (n=%s kind/attrs-ref %s, alloc %s) — must exceed MARG_MAX[kindMatch,migrated,kind,t] = %s\n' \
    "$KINDMATCH_SMALL" "$KINDMATCH_BIG" "$(marg t kindMatch "$KINDMATCH_SMALL" "$KINDMATCH_BIG" kind-plant)" "$KINDMATCH_SMALL" "$KM_PLANT_TR" "$KM_PLANT_AR" "${MARG_MAX[kindMatch,migrated,kind,t]:-}"
  echo
  echo "### entityMatch (instance identity at scale, den-hoag-l0y U2 + (β); frozen gen-schema + gen-select attrs-ref vs live entity; gated: the entity/attrs-ref marginal ratio, thunks + alloc, and the entity load)"
  echo
  echo "| fixture | n | attrs-ref thunks | entity thunks | thunks e/a | alloc e/a | cpu e/a | projection |"
  echo "|---|---|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG"; do
      printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[entityMatch,$n,attrs-ref$sfx]}" "${THUNKS[entityMatch,$n,entity$sfx]}" \
        "${EM_TR[$fx,$n]}" "${EM_AR[$fx,$n]}" "${EM_CR[$fx,$n]}" "${EM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): attrs-ref %s×, entity %s×, attrs-ref-sealed %s×, entity-sealed %s× (gate ≤ %s)\n' \
    "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" "${EM_LIN[attrs-ref]}" "${EM_LIN[entity]}" "${EM_LIN[attrs-ref-sealed]}" "${EM_LIN[entity-sealed]}" "$GROWTH_MAX"
  printf 'arming (planted per-instance kind re-derivation, n=%s→%s): entity/attrs-ref thunk marginal %s (n=%s ratio %s, alloc %s) — must exceed MARG_MAX[entityMatch,migrated,entity,t] = %s\n' \
    "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" "$(qshow "$(marg t entityMatch "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" entity-plant)/$(marg t entityMatch "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" attrs-ref)")" "$ENTITYMATCH_SMALL" "$EM_PLANT_TR" "$EM_PLANT_AR" "$(qshow "${MARG_MAX[entityMatch,migrated,entity,t]:-}")"
  echo
  echo "### coordMatch (the product coordinate's identity decision at scale, den-hoag-8hqx0; frozen gen-select coord-ref vs live coord; gated: the coord thunk and alloc marginals and its load; the ratios printed)"
  echo
  echo "| fixture | n | coord-ref thunks | coord thunks | coord alloc | thunks c/r | alloc c/r | cpu c/r | projection |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$COORDMATCH_SMALL" "$COORDMATCH_BIG"; do
      printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[coordMatch,$n,coord-ref$sfx]}" "${THUNKS[coordMatch,$n,coord$sfx]}" \
        "${ALLOC[coordMatch,$n,coord$sfx]}" "${CM_TR[$fx,$n]}" "${CM_AR[$fx,$n]}" "${CM_CR[$fx,$n]}" "${CM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): coord-ref %s×, coord %s×, coord-ref-sealed %s×, coord-sealed %s× (gate ≤ %s)\n' \
    "$COORDMATCH_SMALL" "$COORDMATCH_BIG" "${CM_LIN[coord-ref]}" "${CM_LIN[coord]}" "${CM_LIN[coord-ref-sealed]}" "${CM_LIN[coord-sealed]}" "$GROWTH_MAX"
  echo
  echo "### resolution (the one resolution calculus at scale, den-hoag-gayc U2b; frozen gen-graph query-orig vs live gen-scope resolve, gated: the resolve/query-orig thunk marginal between consecutive sizes, and the resolve load at the smallest; alloc reported, gated by nothing)"
  echo
  echo "| n | query-orig thunks | resolve thunks | thunks r/q | alloc r/q | cpu r/q | byte gate |"
  echo "|---|---:|---:|---:|---:|---:|---|"
  for n in "${RESOLUTION_SIZES[@]}"; do
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
      "$n" "${THUNKS[resolution,$n,query-orig]}" "${THUNKS[resolution,$n,resolve]}" \
      "${RS_TR[$n]}" "${RS_AR[$n]}" "${RS_CR[$n]}" "${RS_BG[$n]}"
  done
  echo
  printf 'arming (witnesses control, n=4..7 thunks): %s / %s / %s / %s; 6 → 7 step %s× (resolve %s×) — must exceed %s and resolve\n' \
    "${THUNKS[resolution,4,witnesses]}" "${THUNKS[resolution,5,witnesses]}" "${THUNKS[resolution,6,witnesses]}" "${THUNKS[resolution,7,witnesses]}" \
    "$RS_WIT_STEP" "$RS_RES_STEP" "$RESOLUTION_WITNESSES_GROWTH_MIN"
  echo
  echo "### load (the per-process constant: each member's own load, absolute; the small-size thunk counter of each gated arm, judged where its marginal held; startup, absolute)"
  echo
  echo "| row | reading | bound | delta | marginal | state | intercept |"
  echo "|---|---|---|---|---|---|---|"
  printf '%s' "$LOAD_TABLE"
  echo
  echo "$LOAD_LINE"
  echo
  local refs_v="DIFFER from" mems_v="differ from"
  [[ "$REF_ID" == "$ANCHOR_REFERENCE" ]] && refs_v=match
  [[ "$MEMBERS_ID" == "$ANCHOR_MEMBERS" ]] && mems_v=match
  printf 'identity: evaluator "%s", allocator %s (anchor: "%s", %s); references %s the anchor; members %s ANCHOR_MEMBERS.\n' \
    "$EVAL_ID" "$ALLOC_ID" "$ANCHOR_EVALUATOR" "$ANCHOR_ALLOCATOR" "$refs_v" "$mems_v"
  echo
  case $VERDICT in
    0) echo "ALL GATES PASSED (parity + cost, exact + linearity)" ;;
    1 | 6)
      if [[ $VERDICT -eq 6 ]]; then
        echo "CANDIDATE OVER BOUND — ${#FAILURES[@]} gate(s) failed on the CANDIDATE combination above, which this repository has not adopted:"
      else
        echo "PERF REGRESSION — ${#FAILURES[@]} gate(s) failed:"
      fi
      printf '  - %s\n' "${FAILURES[@]}"
      if [[ ${#RATCHETS[@]} -gt 0 ]]; then
        echo "and ${#RATCHETS[@]} reading(s) fell below their bound:"
        printf '  - %s\n' "${RATCHETS[@]}"
      fi
      if [[ ${#REARMS[@]} -gt 0 ]]; then
        echo "and ${#REARMS[@]} load row(s) re-arm with any change that adopts a moved marginal:"
        printf '  - %s\n' "${REARMS[@]}"
      fi
      ;;
    7 | 9)
      if [[ $VERDICT -eq 7 ]]; then
        echo "RE-ANCHOR OWED — the evaluator, its allocator or a reference differs from the anchor, and the members ARE the anchored ones, so these readings are the new bounds. Record them with the identity line above (ANCHOR_EVALUATOR / ANCHOR_ALLOCATOR / ANCHOR_REFERENCE); nothing was gated on cost:"
      else
        echo "RE-ANCHOR BLOCKED — the evaluator, its allocator or a reference differs from the anchor AND the members differ from ANCHOR_MEMBERS, so a reading here would record a member move as the baseline. Re-run with \`--at K=rev:<rev>\` for every member below that differs, then record; nothing was gated on cost."
        echo "  ANCHOR_MEMBERS: $ANCHOR_MEMBERS"
        echo "  this run:       $MEMBERS_ID"
      fi
      printf '  %s\n' "${REANCHOR_LINES[@]}"
      ;;
    8)
      echo "RATCHET OWED — no gate regressed, and ${#RATCHETS[@]} cost reading(s) fell BELOW their bound, and ${#REARMS[@]} load row(s) re-arm. The change that adopts this combination lowers each one and sets each re-arm (ci/perf-bench-bounds.py reads these lines), and writes ANCHOR_MEMBERS='$MEMBERS_ID':"
      printf '  - %s\n' "${RATCHETS[@]+"${RATCHETS[@]}"}" "${REARMS[@]+"${REARMS[@]}"}"
      ;;
  esac
}

# ── marginal and load (den-hoag-r8y89; owner ruling (b) and OQ7, 2026-10-06) ─────────────────────
# A cost row gates its MARGINAL, the counter at its big size minus the counter at its small size, so a
# per-process constant cancels out of every row. Thunks are nrThunks. Alloc is the evaluator-ATTRIBUTED
# bytes (ATT, sample_cell): exact, and free of the collector's 4,096 B block steps, which transfer 1:1
# into a difference of totalBytes (owner ruling OQ7, arm β + U0: the unattributed remainder, strings
# among it, is not gated). The constant is the LOAD, and it is gated three ways:
#   member  — each member's file-level load, the load its own top-level values force (calls into its
#             predecessors' functions included, so a change to a predecessor's function body reads on its
#             callers' rows): its `load` cell minus its predecessor's in perf-bench.nix
#             `loadOrder` (derived there from the census's supplied formals), thunks and ATT, absolute. Exact, n-independent and blind to the shape of any
#             workload cost, so a landing cannot hide a binding behind a change to a row's curvature
#             (gate F1, arm (A)).
#   row     — each gated arm's small-size thunk counter X_s, judged when the arm's own thunk marginal reads
#             EQUAL to LOADM: X_s's change is then the constant's change, exactly. When the marginal moved
#             it is judged on the three-size intercept against LOADI, if the arm is affine at three sizes
#             both at the anchor and now; otherwise it is `confounded`, printed and not judged. The row
#             reads what a member cell cannot: work a workload's first call does once (kindMatch's 13,888
#             thunks against 89 at n=0), and a constant number of merges.
#   startup — the startup cell, thunks and ATT, absolute.
# A moved marginal RE-ARMS its row: `re-arm:` lines print the LOADM, LOADI and LOAD_MAX assignments at
# this reading beside the marginal's own line, so adopting a marginal never leaves the row confounded for
# good (gate F2). A confounded row whose X_s rose keeps its LOAD_MAX, so the next run judges the rise.
REARMS=()
cv() { if [[ $1 == t ]]; then echo "${THUNKS[$2,$3,$4]}"; else echo "${ATT[$2,$3,$4]}"; fi; }
marg() { echo $(($(cv "$1" "$2" "$4" "$5") - $(cv "$1" "$2" "$3" "$5"))); }
# mgate NAME LABEL CTR W S B NUMARM [DENARM]
mgate() {
  local name=$1 label=$2 c=$3 w=$4 s=$5 b=$6 na=$7 da=${8:-} r
  r=$(marg "$c" "$w" "$s" "$b" "$na")
  [[ -n $da ]] && r="$r/$(marg "$c" "$w" "$s" "$b" "$da")"
  gate "marginal: $label" "$r" "${MARG_MAX[$name]:-}" "MARG_MAX[$name]"
}
LOAD_ROWS=()
# mid_l W S B ARM — sets LI to the exact thunk intercept NUM/DEN when the arm is affine at its two sizes
# and their midpoint, else to `-`. The mid cell (one rep) is sampled here, in this shell, never in a
# command substitution: there a dead cell's exit 3 would leave only the subshell, and a re-read re-sample.
LI=""
mid_l() {
  local w=$1 s=$2 b=$3 a=$4 m xs xb xm
  m=$(((s + b) / 2))
  [[ -n ${THUNKS[$w,$m,$a]:-} ]] || sample_cell "$w" "$m" "$a" 1
  xs=${THUNKS[$w,$s,$a]} xb=${THUNKS[$w,$b,$a]} xm=${THUNKS[$w,$m,$a]}
  if (((b - s) * xm == (b - m) * xs + (m - s) * xb)) && ((b * xs - s * xb > 0)); then
    LI="$((b * xs - s * xb))/$((b - s))"
  else
    LI="-"
  fi
}
nd() { awk -v r="$1" -v b="$2" 'function v(q, p) { if (q ~ /\//) { split(q, p, "/"); return p[1] / p[2] } return q + 0 } BEGIN { d = v(r) - v(b); if (d == int(d)) printf "%+d", d; else printf "%+.3f", d }'; }
# rearm NAME LABEL MARGINAL XS LI STATE — the assignments that make a moved marginal's row judgeable again
rearm() {
  local name=$1 label=$2 m=$3 xs=$4 li=$5 st=$6
  REARMS+=("re-arm: load: $label — set LOADM[$name] to $m")
  [[ -n $li ]] && REARMS+=("re-arm: load: $label — set LOADI[$name] to $li")
  if [[ $st == affine || $(qcmp "$xs" "${LOAD_MAX[$name]:-}") != gt ]]; then
    REARMS+=("re-arm: load: $label — set LOAD_MAX[$name] to $xs")
  fi
}
# lgate NAME LABEL W S B ARM — the row load of a gated arm (the header above).
lgate() {
  local name=$1 label=$2 w=$3 s=$4 b=$5 a=$6 xs m bm=${LOADM[$1]:-} st=judged li="-" d=""
  xs=$(cv t "$w" "$s" "$a")
  m=$(marg t "$w" "$s" "$b" "$a")
  if [[ -n $REANCHOR ]]; then
    mid_l "$w" "$s" "$b" "$a"
    li=$LI
    REANCHOR_LINES+=("LOAD_MAX[$name]=$xs   # load: $label; was ${LOAD_MAX[$name]:-}" "LOADM[$name]=$m   # load guard: $label marginal; was ${bm:-}" "LOADI[$name]=$li   # load intercept if affine at three sizes, else -; was ${LOADI[$name]:-}")
    LOAD_ROWS+=("$name|$xs|${LOAD_MAX[$name]:-}|$m|anchor|$li|anchor")
    return
  fi
  if [[ -z $bm ]]; then
    FAILURES+=("unmeasured: load: $label has no anchored marginal LOADM[$name]")
    st=unbound d=unbound
  elif [[ $(qcmp "$m" "$bm") == eq ]]; then
    gate "load: $label" "$xs" "${LOAD_MAX[$name]:-}" "LOAD_MAX[$name]"
    d=$(nd "$xs" "${LOAD_MAX[$name]:-0}")
    if [[ -n ${PERF_LOAD_MID:-} ]]; then
      mid_l "$w" "$s" "$b" "$a"
      li=$LI
    fi
  else
    st=confounded d=confounded
    mid_l "$w" "$s" "$b" "$a"
    li=$LI
    if [[ -n ${LOADI[$name]:-} && ${LOADI[$name]} != - && $li != - ]]; then
      st=affine
      gate "load (affine, marginal moved): $label" "$li" "${LOADI[$name]}" "LOADI[$name]"
      d=$(nd "$li" "${LOADI[$name]}")
    fi
    rearm "$name" "$label" "$m" "$xs" "$li" "$st"
  fi
  LOAD_ROWS+=("$name|$xs|${LOAD_MAX[$name]:-}|$m|$st|$li|$d")
}
# the planted arms, at the big size too, so that the arming compares a MARGINAL
sample_cell kindMatch "$KINDMATCH_BIG" kind-plant 1
sample_cell entityMatch "$ENTITYMATCH_BIG" entity-plant 1

for row in "${MATRIX[@]}"; do
  read -r w b tags <<<"$row"
  has_tag "$tags" r || has_tag "$tags" rb || continue
  s=""
  for row2 in "${MATRIX[@]}"; do
    read -r w2 n2 t2 <<<"$row2"
    [[ "$w2" == "$w" ]] && has_tag "$t2" small && { [[ -n $s ]] && FAILURES+=("marginal: $w has two small sizes in MATRIX ($s and $n2)"); s=$n2; }
  done
  if [[ -z $s ]]; then
    FAILURES+=("marginal: $w n=$b has no small size in MATRIX")
    continue
  fi
  if has_tag "$tags" r; then
    mgate "$w,t" "$w n=$s→$b pure/ref thunks" t "$w" "$s" "$b" pure ref
  else
    mgate "$w,t,band" "$w n=$s→$b pure/ref thunks (band)" t "$w" "$s" "$b" pure ref
  fi
  mgate "$w,a" "$w n=$s→$b pure/ref alloc" a "$w" "$s" "$b" pure ref
  lgate "$w" "$w n=$s→$b pure" "$w" "$s" "$b" pure
done
mgate "classShare,fixed,t" "classShare n=$CLASSSHARE_SMALL→$CLASSSHARE_BIG pure-fixed thunks" t classShare "$CLASSSHARE_SMALL" "$CLASSSHARE_BIG" pure-fixed
lgate "classShare,fixed" "classShare n=$CLASSSHARE_SMALL→$CLASSSHARE_BIG pure-fixed" classShare "$CLASSSHARE_SMALL" "$CLASSSHARE_BIG" pure-fixed
mgate "overrideWarm,warm,t" "overrideWarm n=$OVERRIDEWARM_SMALL→$OVERRIDEWARM_BIG warm thunks" t overrideWarm "$OVERRIDEWARM_SMALL" "$OVERRIDEWARM_BIG" warm
mgate "overrideWarm,warm,a" "overrideWarm n=$OVERRIDEWARM_SMALL→$OVERRIDEWARM_BIG warm alloc" a overrideWarm "$OVERRIDEWARM_SMALL" "$OVERRIDEWARM_BIG" warm
lgate "overrideWarm,warm" "overrideWarm n=$OVERRIDEWARM_SMALL→$OVERRIDEWARM_BIG warm" overrideWarm "$OVERRIDEWARM_SMALL" "$OVERRIDEWARM_BIG" warm
for fx in migrated sealed; do
  sfx=""
  [[ "$fx" == sealed ]] && sfx="-sealed"
  for c in t a; do
    mgate "kindMatch,$fx,kind,$c" "kindMatch ($fx) n=$KINDMATCH_SMALL→$KINDMATCH_BIG kind $c" "$c" kindMatch "$KINDMATCH_SMALL" "$KINDMATCH_BIG" "kind$sfx"
    mgate "entityMatch,$fx,entity,$c" "entityMatch ($fx) n=$ENTITYMATCH_SMALL→$ENTITYMATCH_BIG entity/attrs-ref $c" "$c" entityMatch "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" "entity$sfx" "attrs-ref$sfx"
    mgate "coordMatch,$fx,coord,$c" "coordMatch ($fx) n=$COORDMATCH_SMALL→$COORDMATCH_BIG coord $c" "$c" coordMatch "$COORDMATCH_SMALL" "$COORDMATCH_BIG" "coord$sfx"
  done
  lgate "kindMatch,$fx,kind" "kindMatch ($fx) n=$KINDMATCH_SMALL→$KINDMATCH_BIG kind" kindMatch "$KINDMATCH_SMALL" "$KINDMATCH_BIG" "kind$sfx"
  lgate "entityMatch,$fx,entity" "entityMatch ($fx) n=$ENTITYMATCH_SMALL→$ENTITYMATCH_BIG entity" entityMatch "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" "entity$sfx"
  lgate "coordMatch,$fx,coord" "coordMatch ($fx) n=$COORDMATCH_SMALL→$COORDMATCH_BIG coord" coordMatch "$COORDMATCH_SMALL" "$COORDMATCH_BIG" "coord$sfx"
done
# resolution is super-linear, so it has no linear intercept: its marginals are the steps between
# consecutive sizes, and its row load is the resolve arm at the smallest size, judged when the n=4→5
# resolve marginal held, else confounded (spec OQ8).
rs_prev=""
for n in "${RESOLUTION_SIZES[@]}"; do
  [[ -n $rs_prev ]] && mgate "resolution,$rs_prev-$n,t" "resolution n=$rs_prev→$n resolve/query-orig thunks" t resolution "$rs_prev" "$n" resolve query-orig
  rs_prev=$n
done
rs_xs=${THUNKS[resolution,${RESOLUTION_SIZES[0]},resolve]}
rs_m=$(marg t resolution "${RESOLUTION_SIZES[0]}" "${RESOLUTION_SIZES[1]}" resolve)
rs_label="resolution n=${RESOLUTION_SIZES[0]} resolve"
if [[ -n $REANCHOR ]]; then
  REANCHOR_LINES+=("LOAD_MAX[resolution,resolve]=$rs_xs   # load: $rs_label; was ${LOAD_MAX[resolution,resolve]:-}" "LOADM[resolution,resolve]=$rs_m   # load guard: resolution marginal; was ${LOADM[resolution,resolve]:-}")
  LOAD_ROWS+=("resolution,resolve|$rs_xs|${LOAD_MAX[resolution,resolve]:-}|$rs_m|anchor|-|anchor")
elif [[ $(qcmp "$rs_m" "${LOADM[resolution,resolve]:-}") == eq ]]; then
  gate "load: $rs_label" "$rs_xs" "${LOAD_MAX[resolution,resolve]:-}" "LOAD_MAX[resolution,resolve]"
  LOAD_ROWS+=("resolution,resolve|$rs_xs|${LOAD_MAX[resolution,resolve]:-}|$rs_m|judged|-|$(nd "$rs_xs" "${LOAD_MAX[resolution,resolve]:-0}")")
else
  rearm resolution,resolve "$rs_label" "$rs_m" "$rs_xs" "" confounded
  LOAD_ROWS+=("resolution,resolve|$rs_xs|${LOAD_MAX[resolution,resolve]:-}|$rs_m|confounded|-|confounded")
fi
# absolute load rows: startup, and every member's own load (its cell minus its predecessor's)
aload() {
  local name=$1 label=$2 r=$3
  gate "load: $label" "$r" "${LOAD_MAX[$name]:-}" "LOAD_MAX[$name]"
  LOAD_ROWS+=("$name|$r|${LOAD_MAX[$name]:-}|-|abs|-|$(nd "$r" "${LOAD_MAX[$name]:-0}")")
}
aload startup,t "startup pure thunks" "${THUNKS[startup,1,pure]}"
aload startup,a "startup pure alloc" "${ATT[startup,1,pure]}"
lprev=none
for k in "${LOAD_ORDER[@]}"; do
  aload "member,$k,t" "member $k thunks" "$(($(cv t load 1 "$k") - $(cv t load 1 "$lprev")))"
  aload "member,$k,a" "member $k alloc" "$(($(cv a load 1 "$k") - $(cv a load 1 "$lprev")))"
  lprev=$k
done
# ARMING: a planted per-node cost must read above the MARGINAL bound of the row it exists for
if [[ -z $REANCHOR ]]; then
  if [[ $(qcmp "$(marg t kindMatch "$KINDMATCH_SMALL" "$KINDMATCH_BIG" kind-plant)" "${MARG_MAX[kindMatch,migrated,kind,t]:-}") != gt ]]; then
    FAILURES+=("kindMatch arming: the planted per-node recompute's marginal thunks do not exceed MARG_MAX[kindMatch,migrated,kind,t] — the bound cannot see the class this row exists for")
  fi
  if [[ $(qcmp "$(marg t entityMatch "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" entity-plant)/$(marg t entityMatch "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" attrs-ref)" "${MARG_MAX[entityMatch,migrated,entity,t]:-}") != gt ]]; then
    FAILURES+=("entityMatch arming: the planted per-instance re-derivation's marginal entity/attrs-ref thunks do not exceed MARG_MAX[entityMatch,migrated,entity,t] — the bound cannot see the class this row exists for")
  fi
fi
# LOAD DELTA: one printed line, and a per-row table the landing's diff reads (ci/perf-bench-load-diff.py)
LOAD_MOVED=0
LOAD_JUDGED=0
LOAD_CONF=0
LOAD_MIN=""
LOAD_MAX_D=""
LOAD_TABLE=""
LOAD_START_T="n/a"
LOAD_START_A="n/a"
LOAD_MEM_MOVED=()
for lr in "${LOAD_ROWS[@]}"; do
  IFS='|' read -r ln lread lbound lm lst lli d <<<"$lr"
  LOAD_TABLE+="| $ln | $lread | ${lbound:-—} | $d | $lm | $lst | $lli |"$'\n'
  [[ $ln == startup,t ]] && LOAD_START_T=$d
  [[ $ln == startup,a ]] && LOAD_START_A=$d
  if [[ $ln == member,* ]]; then
    [[ $d != +0 ]] && LOAD_MEM_MOVED+=("${ln#member,} $d")
    continue
  fi
  [[ $lst == abs ]] && continue
  [[ $lst == confounded ]] && LOAD_CONF=$((LOAD_CONF + 1))
  if [[ $lst == judged || $lst == affine ]]; then
    LOAD_JUDGED=$((LOAD_JUDGED + 1))
    if [[ $d != +0 && $d != unbound ]]; then
      LOAD_MOVED=$((LOAD_MOVED + 1))
      LOAD_MIN=$(awk -v a="${LOAD_MIN:-$d}" -v b="$d" 'BEGIN { print (b + 0 < a + 0) ? b : a }')
      LOAD_MAX_D=$(awk -v a="${LOAD_MAX_D:-$d}" -v b="$d" 'BEGIN { print (b + 0 > a + 0) ? b : a }')
    fi
  fi
done
if [[ -n $REANCHOR ]]; then
  LOAD_LINE="LOAD DELTA vs anchor: not judged (the identity moved)"
else
  lmem="members moved ${#LOAD_MEM_MOVED[@]} of $((2 * ${#LOAD_ORDER[@]}))"
  [[ ${#LOAD_MEM_MOVED[@]} -gt 0 ]] && lmem+=" ($(printf '%s, ' "${LOAD_MEM_MOVED[@]}" | sed 's/, $//'))"
  LOAD_LINE="LOAD DELTA vs anchor: startup thunks $LOAD_START_T, startup alloc $LOAD_START_A B, $lmem, rows moved $LOAD_MOVED of $LOAD_JUDGED judged ($LOAD_CONF confounded), per-row thunks min ${LOAD_MIN:-+0} max ${LOAD_MAX_D:-+0}"
fi

# ── the verdict, decided BEFORE the report prints and before any splice (gate C4) ──
# Precedence: a regression or a non-cost failure (parity, linearity, arming, an unmeasured gate) is
# 1/6 whatever else holds; then an identity change, 7/9, under which no cost gate was judged; then
# readings below their bounds, 8. A ratchet-only run is never a regression (gate C2).
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  if [[ ${#AT_ORDER[@]} -gt 0 ]]; then VERDICT=6; else VERDICT=1; fi
elif [[ -n $REANCHOR ]]; then
  if [[ "$MEMBERS_ID" == "$ANCHOR_MEMBERS" ]]; then VERDICT=7; else VERDICT=9; fi
elif [[ ${#RATCHETS[@]} -gt 0 || ${#REARMS[@]} -gt 0 ]]; then
  VERDICT=8
else
  VERDICT=0
fi

emit_report | tee "$tmp/report.md"

# ── optional: splice the report into a doc's marker block ─────────────────────
# The FAILURES exit fires AFTER the splice — a failing run still records what it measured. A run
# under another identity (7/9) splices NOTHING: its numbers are not a reading of the anchored bench.
# Tables are spliced compact (`|---|---:|`); the repo's format-before-commit pass pads them to the
# committed form, so run the formatter after an --update. Counters are deterministic, so a re-run then
# diffs only the timing values inside the markers.
if [[ -n "$UPDATE_FILE" && $VERDICT -ne 7 && $VERDICT -ne 9 ]]; then
  # report.md opens with a blank line and closes on the gate summary; the trailing `print ""`
  # supplies the blank line mdformat wants before the closing HTML comment, so the spliced block
  # is already treefmt-clean.
  awk -v rep="$tmp/report.md" '
    /<!-- BEGIN PERF-BENCH -->/ { print; while ((getline l < rep) > 0) print l; print ""; skip=1; next }
    /<!-- END PERF-BENCH -->/   { skip=0 }
    !skip { print }
  ' "$UPDATE_FILE" >"$UPDATE_FILE.tmp" && mv "$UPDATE_FILE.tmp" "$UPDATE_FILE"
fi

# The bounds are derived at the BASELINE anchor, so a candidate breaching one is a real, reportable
# fact about a combination the repository has not adopted — a different claim from "the published
# combination regressed", and it gets its own code rather than being folded in.
case $VERDICT in
  1) echo "PERF REGRESSION — ${#FAILURES[@]} gate(s) failed (see report above)" >&2 ;;
  6) echo "perf-bench: CANDIDATE OVER BOUND — ${#FAILURES[@]} gate(s) failed on a candidate combination (see report above)" >&2 ;;
  7) echo "perf-bench: RE-ANCHOR OWED — identity '$EVAL_ID' / '$ALLOC_ID' / references differ from the anchor at the anchored members; record the ${#REANCHOR_LINES[@]} readings above" >&2 ;;
  8) echo "perf-bench: RATCHET OWED — ${#RATCHETS[@]} cost reading(s) below their bound and no regression; lower them in the adopting change (see report above)" >&2 ;;
  9) echo "perf-bench: RE-ANCHOR BLOCKED — identity and members both moved; re-run at ANCHOR_MEMBERS before recording" >&2 ;;
esac
exit "$VERDICT"
