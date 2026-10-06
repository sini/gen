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
#   cost      — every cost row, through `gate`: EXACT and TWO-SIDED against its recorded bound. A
#               row whose denominator is INDEPENDENT of gen (nixpkgs `ref`, or a rev-pinned frozen
#               original) gates its ratio, NUM/DEN at full precision; a row whose only control is
#               gen itself gates the guarded arm's OWN count. Above the bound is a regression; below
#               it is `ratchet:`, refused until the bound is lowered in the same change
#               (den-hoag-r8y89: the bench catches regressions and never obstructs optimizations)
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
# path's length moved coordMatch coord n=400 by 576 B; with both removed, every rep and every
# environment read the same byte.

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

# "workload n tags" — tags: r = ratio-gated size (default win-gate), rb = wideFreeform ratio size
# (alloc on its own derived bound; thunks band ≤ WIDEFREEFORM_RATIO_MAX), small/big = linearity pair (big = 4×small)
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
  "lazyRegistry 2000 r"
  "threadedRegistry 500 small"
  "threadedRegistry 2000 r,big"
  "wrappedRegistry 500 small"
  "wrappedRegistry 2000 r,big"
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
ANCHOR_MEMBERS='gen-algebra=de93454e5a6466bdd724ce15c666647358f9622a gen-aspects=e1ad87c83e3c249d7b1ab2c70b8b10105e0cce04 gen-class=fed0139ca309405adf7fe82da71d27d0abe1fb3a gen-graph=6f7300d3f69f844f713e98c26443a72119eeff2c gen-identity=19338f554a0030645b1eba88dfa89a470e5f8f30 gen-memo=fe1b501b6f4bc35590d5ec708ba4c3b9dc54858d gen-merge=b15c2825912aa3893833c398d8e1bd93f862dd14 gen-prelude=7f0513dd21c06e92ffe5131ea85d6b32b1b77a90 gen-schema=cd67d648b7664b1ee22e2453e5e9c0ccf922ce7f gen-scope=3a50a9c64dc3210db6776417f2242b81c4715016 gen-select=ff3229ca56ad5b6762f87634cab8bba1942c3f61 gen-types=37258c458f451c1f19d6380b8d5ba0e86eb73e59'

# ── per-row ratio bounds — DERIVED, not chosen ────────────────────────────────
# ★ THE FORM SINCE den-hoag-r8y89 (owner sitting den-hoag-rwuqw, ruling 10 arm A; P1 (i), P5 (i)):
# every bound in this file is the EXACT reading at the anchor identity above, written as an integer
# count or, on a ratio row, as NUM/DEN — the two raw counters, so the ratio is compared at full
# precision and the bound carries its own provenance. MARGIN is 0 by construction and there is no
# per-row tolerance: the bound EQUALS the reading on a green run, a reading above it is a regression
# (raising it needs an owner reading on the five items in ci/README.md), and a reading below it is
# `ratchet:` until the bound is lowered to it in the same change. The ANCHOR/MARGIN derivations that
# follow are the record of how each row's former decimal bound was reached; the decimals are gone.
# ADR-0032 ruling 5: the number is derived at implementation from the measured cost curve,
# recorded with its derivation, and re-derived when the engine changes. The licensing rule is
# ci/README.md §"Updating thresholds / workloads"; the derivation record is its 2026-09-21
# baseline block. Regenerate every figure below with `nix run ./ci#perf-bench`.
#
# ANCHOR — the measured pure/ref ratio at 2026-09-21, Nix 2.34.8, gen-merge `7516886` (the rev
# this hub pins; its lib/modules.nix is byte-identical to gen-merge main `275953b`, one relock
# commit ahead, which moves lock files only). Read at the precision the gate compares at:
# ratio() prints %.3f before lte(), so a bound of 1.210 admits a printed 1.210 and refuses 1.211.
#
# MARGIN — half the ratio-delta of the SMALLER of the two constructions the one-engine
# consolidation (gen-merge `564ad1c`) introduced, measured on THAT row and THAT counter,
# truncated down to three places. The two are ① `declarationGuard` (ADR-0033's refusal-by-name)
# and ② `driveKnot` (ADR-0006's one evaluator); each was re-measured per row at this pin by
# neutralising it in a throwaway tree. This is NOT a noise allowance: the gated counters have
# ZERO spread here (byte-identical across reps and across arms), so a margin buys exactly one
# thing — how much unattributed drift the project absorbs before it hears about it.
#
# WHAT EVERY BOUND BELOW STILL CATCHES, as one claim: a regression costing half of the cheaper
# of the two constructions this engine change is calibrated on, on that row and counter. Half
# rather than all of it is what keeps the gate's own red state testable — a cost seeded strictly
# between the margin and ②'s delta must red, and that is the acceptance cell this bound shipped
# with.
#
# Four of the twelve come out at margin 0.000, because ② is ~free on that row (`driveKnot` costs
# 147 thunks on scalar n=8000 — 0.0002 of ratio). A 0.000 margin is admissible on a deterministic
# counter and it is the tightest honest reading: the row holds AT its anchor and any move of 0.001
# is reported.
#
# THIS RE-BASELINE LOOSENS EXACTLY THREE OF THE TWELVE — scalar thunks, schemaHosts thunks,
# schemaHosts alloc — and each of the three is the attributed move (ci/README.md's 2026-09-21
# block carries all five licensing items). The other NINE tighten, most of them sharply: the old
# shared 0.90 was absorbing a silent +57% pure-side regression on deepSubmodule and +16% on
# registry/lazyRegistry with no gate firing at all.
declare -A ROW_THUNKS_MAX ROW_ALLOC_MAX
# scalar n=8000 — anchors 0.912 / 0.756; ① 0.037994 / 0.054458, ② 0.000174 / 0.000083 (~free).
# RATCHETED to the figures gen-merge d84ba687 lands (0.902 / 0.754, down from the pre-channel
# figure 0.912 / 0.756), at margin 0.000: a tightening, so it needs no licence (ci/README.md).
# RESTORED to the original 0.90 (xzchx arm A, gen-merge 63ae058's path-free declaration walk):
# 0.883 at gen-merge d37deb6. A tightening; the thunk bound is no longer interim.
ROW_THUNKS_MAX[scalar,8000]=691066/844626
ROW_ALLOC_MAX[scalar,8000]=42573120/56484848
# registry n=2000 — anchors 0.776 / 0.631; ① 0.108340 / 0.101395, ② 0.064314 / 0.046820.
ROW_THUNKS_MAX[registry,2000]=1418543/2179179
ROW_ALLOC_MAX[registry,2000]=73299264/126644096
# lazyRegistry n=2000 — anchors 0.777 / 0.632; ① 0.108440 / 0.101548, ② 0.064373 / 0.046891.
ROW_THUNKS_MAX[lazyRegistry,2000]=1402542/2177174
ROW_ALLOC_MAX[lazyRegistry,2000]=72657728/126453088
# threadedRegistry n=2000 — the registry shape over nixpkgs `attrsWith { placeholder = "host"; }`,
# a container outside the six, so the pure stack folds through gen-merge's threaded rebuild channel
# (its merge runs three times per option, nixpkgs' once). ANCHORS 0.772 / 0.675 at Nix 2.34.8, gen-merge
# 202cbd5 (branch f8mgj, the landing that opens the channel). MARGIN 0.000, the tightest honest
# reading on a deterministic counter (as entityMatch's): the row is new, so no consolidation delta
# was ever measured on it, and a bound below the then-default COUNTER_RATIO_MAX (0.90, retired) is a tightening, which
# needs no licence (ci/README.md). Arming: the planted stacks below, never a gated arm.
ROW_THUNKS_MAX[threadedRegistry,2000]=1619102/2179181
ROW_ALLOC_MAX[threadedRegistry,2000]=83947328/126644096
# wrappedRegistry n=2000 — the registry shape under nixpkgs `coercedTo` (a container that adds no step)
# over the stack's own `attrsOf`, which gen-merge keys at the option's root as the root is (keyWalk's
# step-free arm, den-hoag-t1j4z). ANCHORS 0.652 / 0.580 at Nix 2.34.8, gen-merge b15c282 (main,
# carrying t1j4z-b1's arm and t1j4z's agreeing-definitions serve) under this hub's other pins. MARGIN 0.000, the
# threadedRegistry precedent: the row is new, and a bound below the then-default COUNTER_RATIO_MAX (0.90, retired) is a
# tightening, which needs no licence (ci/README.md). Arming: a gen-merge without the arm cannot
# evaluate the row at all (class (a) under `coercedTo`), and a fresh token planted as the arm's body
# reds the bench naming it (landing-time seed; no per-run plant).
ROW_THUNKS_MAX[wrappedRegistry,2000]=1420336/2179234
ROW_ALLOC_MAX[wrappedRegistry,2000]=73401968/126648128
# schemaHosts n=1600 — anchors 1.171 / 0.995; ① 0.197886 / 0.187996, ② 0.079462 / 0.057494.
# The pure stack is HEAVIER than the frozen nixpkgs reference on this shape: this row is a
# stated band, not a win-gate. What the band buys is in ci/README.md's 2026-09-21 block; whether
# the project's PUBLIC claim moved with it was decided on 2026-09-21 — it did: BENCHMARKS.md's
# composition-plane claim is amended to this band and cites this bound back here.
# RATCHETED to the figures read at the gen-merge d84ba687 pin (1.207 / 1.018, down from the
# 1.210 / 1.023 band), at margin 0.000: a tightening, so it needs no licence (ci/README.md).
# RE-ANCHORED at gen-identity `410261b` (den-hoag-xvww), margin 0.000: 1.132 / 0.969 at the
# pre-relock pins, 1.146 / 0.982 at the relock that carries it. gen-identity names the kind and label
# in every mint refusal, and its price is PER MINT, never per value node: +4 thunks per encoder
# instance, labels + 1 instances per mint, so +12 thunks and +7 calls for a two-label mint. Measured
# on this row, one member swapped at a time: gen-identity alone +38,563 thunks / +2,037,984 B on the
# pure arm (0.981); gen-merge `aea02d1` +2 thunks / +24,112 B (0.00014, below a printed step), which
# is what takes the alloc anchor to 0.982. A +1-thunk-per-mint plant in gen-identity reads 1.146 /
# 0.982 here and does NOT red this row (measured at this re-anchor); entityMatch is the per-mint guard
# (below). A tightening of the xzchx INTERIM 1.207 / 1.018, in the direction its return clause asks.
# RE-ANCHORED 1.146 / 0.982 → 1.157 / 0.991, margin 0.000 (den-hoag-bfc0k + den-hoag-5xio7 relock),
# under owner sitting item R8's default (a correctness fix's stated price; defaulted, reversible).
# Bisect by root-lock arm on hub cb6953a, host and Determinate agreeing: gen-merge e332998/0943b2a
# (5xio7 alone, + export) does not red this row; + gen-schema fa26749 (`constructionRelation`, the
# per-construction merge relation every schema entry type now states) reads 1.155 / 0.990; the full
# landing (gen-merge 50250c1, gen-schema 4b4244a, gen-aspects 25c6f86) reads 1.157 / 0.991 locally
# (Nix 2.34.8 and Determinate 3.22.5) and 1.157 / 0.992 on the CI runner's Determinate (hub CI run
# 36228440647 on fcb8a69); the alloc bound is the larger measured figure, still margin 0.000.
# RE-ANCHORED thunks 1.157 → 1.163, margin 0.000 (den-hoag-ez1yq relock 32, R8 default; alloc unmoved,
# 0.991): bisect by root-lock arm on the relock-32 candidate (host evaluator): gen-scope a650104 (kinds minted by a staged
# fold) reads 1.158, + gen-scope 67b690c (the quotient accessor) 1.163; gen-graph e10c49d does not
# red this row.
# RESTORED to the original 0.90 on both counters (xzchx arm 4, gen-schema ffdf8ec: `_identity` is one
# `lazyAttrsOf (listOf str)` leaf closed to `keys` by its `apply`, not a submodule evaluating a nested
# module per instance with its own declaration guard and knot). Read 0.890 / 0.786 on the host evaluator
# (Nix 2.34.8) at hub b48c1d0 with that gen-schema; the thunk ratio is 0.890 under nix, Determinate and
# Lix alike. The bound is the restored promise, as scalar's was at ab05306, not ANCHOR + MARGIN; the
# ratchet to a derived anchor reads its alloc figure off CI's Determinate log, because the local
# Determinate binary's allocation diverges from CI's. A tightening; the bounds are no longer interim.
ROW_THUNKS_MAX[schemaHosts,1600]=2430537/2864692
ROW_ALLOC_MAX[schemaHosts,1600]=137815536/168214464
# deepSubmodule n=1600 — anchors 0.575 / 0.463; ① 0.105358 / 0.090347, ② 0.087229 / 0.065271.
# RE-DERIVED for the Unit 2 engine (den-hoag-n6dh7; owner ruling 2026-09-28, ADR-0032 ruling 5 "re-
# derived when the engine changes"), 0.618 / 0.495 → 0.643 / 0.595, margin 0.000, RATCHETED.
# The old anchor and margin measured ② `driveKnot`, one `scope.eval` per nested tree; Unit 2 retires
# it (every nested tree is an `nta` child of ONE `scope.eval`, ADR-0006 / ADR-0008 §1), so ② is no
# longer paid on this row and the rule gives margin 0.000, as on the rows where ② is ~free. ANCHOR:
# read on hub ec614fa at gen-merge 0c49041 (Unit 2 with arm (B): a child reads its definitions off
# its host's position record; L5c; den-hoag-9d80v, +0.001 alloc; den-hoag-1n12c), gen-scope ba726ef,
# gen-schema 33e4dda, gen-aspects afd8972, host evaluator. The five
# licensing items for this loosening: reports/den-hoag-n6dh7-reader-api-spike-v0.md (isolation by
# per-arm curves; the named construction, the `nta` node at 214.8 thunks / 14,640 B per tree over a
# plain knot; measured irreducibility, no lever reaches 0.618 / 0.495) and
# reports/den-hoag-n6dh7-u2-armb-build-v0.md (both suites of each member at the anchor revs).
# RATCHET: this row only ever tightens. A reading BELOW the bound refuses as `ratchet:` until the
# bound is lowered to it in the same change; a reading above it refuses as every row does, and
# raising it needs a fresh owner reading on top of the five licensing items.
# RATCHETED 0.643 / 0.595 → 0.583 / 0.536 by the gen-merge nesting-side rebuild (den-hoag-i4c0n: the
# walk reads the fold's own `typeDefs`, one discharge per nesting option; no freeform group without
# a declared freeform type, decided by key; gen-merge `0010eb7` + `fa73591`). Re-read at relock 40's
# hub, every member at its tip (gen-merge `f47c48a`, with gen-scope's L2 grammar), host evaluator.
# RATCHETED 0.583 / 0.536 → 0.557 / 0.533 by the gen-merge module graph (den-hoag-470xp arm F: a
# plain module list is its own closure, and the merge path collects by breadth-first levels with no
# minted id; gen-merge `7398fd3`). Read on hub 98c056c with `--at gen-merge=path:` at that tree,
# host evaluator (reports/den-hoag-470xp-arm-f-build-v0.md §5).
# RATCHETED 0.557 / 0.533 → 0.555 / 0.504 by the gen-scope eval cleanup (den-hoag-lk2ks: the nta
# channel's incidental cost removed by construction; gen-scope `9a4db95`). Relock 44.
# RATCHETED 0.555 / 0.504 → 0.551 / 0.503 by the gen-merge `_module.args` collector change
# (den-hoag-tl4nx: the same-name refusal, collected pay-per-use). Relock 47.
# RATCHETED 0.551 / 0.503 → 0.549 / 0.502 by the relock 48 set (gen-merge lnleu, d4gnx, a0c4z,
# o3oz5, f8mgj arm Q; gen-select l0y U3). Relock 48.
# RATCHETED 0.549 / 0.502 → 0.541 / 0.500 by the gen-merge tree-as-a-type option type
# (den-hoag-foreign-mount-parity-knhyg, built at the crossing site). Relock 49.
# RATCHETED 0.541 / 0.500 → 0.539 / 0.498 by the gen-merge relock 51 set (den-hoag-fpxsd construction
# L, den-hoag-threadedforeign-parity-residue-0hew4). Relock 51.
ROW_THUNKS_MAX[deepSubmodule,1600]=6226213/11557492
ROW_ALLOC_MAX[deepSubmodule,1600]=325449760/653164176
# foreignMount n=2000 — n option roots on ONE stock nixpkgs `submodule`, each mounted by gen-merge's
# foreign-mount path (den-hoag-gijly OQ2, arm (a) + this row; before it no row reached the mount, and
# an abort planted at its head left the bench green). The denominator is nixpkgs `evalModules` over
# the same modules: the reach census (every source key poisoned in turn) kills `ref` on nixpkgs-lib
# alone, and `pure` on gen-prelude, -types, -merge, -scope, -identity and -graph, so the row is
# INDEPENDENT. Anchored at its landing; the mount's measured price over nixpkgs is the reading.
ROW_THUNKS_MAX[foreignMount,2000]=1717897/1673781
ROW_ALLOC_MAX[foreignMount,2000]=98764240/97486576
# wideFreeform n=8000 — alloc anchor 0.806; ① 0.000154, ② 0.000090 (~free: this shape rides the
# per-key type merges, not the declaration spine, so neither construction touches it). Its THUNK
# bound is WIDEFREEFORM_RATIO_MAX below, which carries that row's own claim.
ROW_ALLOC_MAX[wideFreeform,8000]=40703680/52381456

# ── classShare (gen-class tier-2 fixed-input spine gate) — its OWN threshold, own rationale ──
# The fixed-input path (applyCoreFixed) skips gen-merge's discharge/fold/verify spine for the shared
# core loc, so its thunk graph must be a fraction of the full re-merge's. Measured fixed/full thunk
# ratio ≈ 0.17 (2026-07-05, Nix 2.34.7, gen-merge fdbf140) — a ~5.8× spine reduction. The gate floor
# 0.30 = measured + ~75% relative headroom, and enforces ≥3.33× — comfortably past the A1 fixed-input
# reference (2.48×, ratio 0.403; the 1.89×→2.48× spine-tax band, spec §2.5) so an erosion BELOW the A1
# band fires the gate ("any reduction" is not a pass). Sizes mirror schemaHosts/aspects (400→1600, ×4).
# RE-BASED (den-hoag-r8y89): both arms are gen, so a shared-plane improvement moved the denominator
# and a fixed/full ratio could refuse an optimization; no nixpkgs operation corresponds to fixed-input
# class sharing (spec OQ1), so the row gates the guarded arm's OWN cost: `pure-fixed` thunks, exact.
# Erosion of the reuse raises that cost and reds; the 0.30 ratio (≥ 3.33×, the A1 band) is printed,
# gated by nothing. The domain, stated: a change that lowers the shared plane AND erodes the reuse
# by less moves the fixed arm DOWN, so it passes as a ratchet and the erosion is absorbed into the
# lowered bound; only the printed ratio shows it.
CLASSSHARE_SMALL=400
CLASSSHARE_BIG=1600
declare -A CLASSSHARE_FIXED_THUNKS_MAX
CLASSSHARE_FIXED_THUNKS_MAX[400]=290629
CLASSSHARE_FIXED_THUNKS_MAX[1600]=1142029

# ── wideFreeform — THUNK band (only alloc keeps the default win-gate) ──
# Freeform absorption is THUNK-parity with nixpkgs, not a pure win on that counter: unknown sibling keys
# route through the root freeformType, so absorption rides the SAME per-key type merges nixpkgs.lib
# performs (the pure engine's thunk win is on DECLARED option paths — see scalar/registry/aspects). So
# the THUNK ratio rides a band while ALLOC stays a win-gate — two claims, two bounds.
# Deterministic anchor (2026-09-21, Nix 2.34.8, gen-merge 7516886) at n=8000: thunks 1.096, alloc 0.806
# (the 2026-07-05 fdbf140 reading was 1.099 / 0.821). The thunk ceiling is the anchor itself: under the
# per-row derivation above, this row's margin is 0.000 because BOTH constructions of the one-engine
# consolidation are ~free on it (① 0.000154, ② 0.000090 of ratio) — freeform absorption rides the
# per-key type merges, not the declaration spine. The former 1.3 was measured + ~18% headroom and was
# absorbing a silent +19% pure-side regression on this row; a band at the anchor keeps the parity claim
# and reports the next move instead of swallowing it. The real teeth are LINEARITY (the O(n^2)
# freeform blowup this workload was built to catch — pre-fix n=8000 thunks were 468×ref, gated at
# GROWTH_MAX over a 4x step) + the thunk band + the deterministic counters. This cell also used to carry
# a cpu band of its own; it was the thinnest-margin cpu gate in the matrix (0.914 measured against a 0.95
# ceiling — 3.9% headroom on an instrument whose noise floor is a ~2.2× raw frequency-regime step) and it is
# retired with the rest, along with the 0.776–0.888 spread that set it: that spread was produced by the
# blocked A-then-B protocol this script no longer runs, and a figure a blocked protocol produced on this
# host is not evidence about the subject. The same reasoning, with these figures, is written out in
# ci/README.md's wideFreeform section; regenerate via `nix run ./ci#perf-bench`.
# RE-ANCHORED 1.096 → 1.097 (owner ruling on den-hoag-7gp66 G8, arm (a), 2026-09-28): the P2 door
# price of gen-scope's L2 argument grammar, a CONSTANT +182 pure thunks per evaluation at gen-scope's
# entry (750,941 → 751,123 at n=8000, the same +182 at n=2000; ref 684,857), linearity and alloc
# unchanged. WHAT THE LOOSENED BAND PAYS FOR (owner-confirmed 2026-09-30, den-hoag-kvj78 arm (a)): the
# door cost is ONE-TIME construction PER gen-scope LIBRARY INSTANCE — 207 thunks built once per process
# (at the scout's pinned pair), 0 per crossing (101 crossings measured, 356.0 thunks each with and without
# the doors; identical on nix, Determinate and Lix). The lean door construction took 55 of it back; no
# internal-only path reaches 1.096, and publishing unchecked cores to reach it was rejected. A landing that
# brings wideFreeform back under 1.096 re-tightens this band.
WIDEFREEFORM_RATIO_MAX=615425/684873

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
# RE-BASED (den-hoag-r8y89), classShare's reason: `warm` thunks AND alloc, exact, against the arm's
# own recorded cost; the warm/cold ratios are printed, gated by nothing. The same domain statement
# holds: a shared-plane gain larger than a simultaneous reuse erosion reads as a ratchet.
OVERRIDEWARM_SMALL=400
OVERRIDEWARM_BIG=1600
declare -A OVERRIDEWARM_WARM_THUNKS_MAX OVERRIDEWARM_WARM_ALLOC_MAX
OVERRIDEWARM_WARM_THUNKS_MAX[400]=391368
OVERRIDEWARM_WARM_ALLOC_MAX[400]=20616848
OVERRIDEWARM_WARM_THUNKS_MAX[1600]=1528368
OVERRIDEWARM_WARM_ALLOC_MAX[1600]=80391888

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
# conflation itself. (2) RATIO, thunks AND alloc (classShare's pair: a per-node primop recompute over
# a cached preimage costs ~1 thunk but allocates), kind/attrs-ref ≤ the bound, at both sizes.
# (3) LINEARITY on every stack.
#
# BOUND = ANCHOR + MARGIN, MARGIN 0.000. ANCHOR — the measured ratio at the landing: hub `perf-bench`
# app, Nix 2.34.8, gen-select `2cd8c5d` (lib/ identical to `28a0968`), frozen gen-select `9285b5b`,
# gen-schema `a90bc54`. MARGIN — zero, because the thunk counters are deterministic and the owner
# ruled any regression a defect. ratio() prints %.3f, so the headroom under each bound is the distance
# from the exact anchor to the next printed step: thunks 63 / 211 (migrated, n=400 / 1600) and
# 159 / 1,373 (sealed); alloc 21,799 / 63,415 B and 20,482 / 13,244 B. Allocation carries a ~2.5 KB
# run-to-run jitter and moves a few KB between environments, which is inside every alloc headroom.
#
# STOCK, stated: the anchor is NOT the pre-landing cost. Stock gen-select `9285b5b` as the numerator
# costs 398,207 / 1,573,607 thunks on the migrated fixture, and its projection fails the byte gate
# (a name key selects all n). The landed construction is +11,155 / +28,555 over it: +14.5 thunks
# per node plus ≈5.4k constant (the two mints). About 8.5 per node of that is C-1's
# `sealedCollisionEq` on the matching half; the rest is the per-node kind-key projection and its
# admission read (den-hoag-l0y build and landing-gate reports). The bound holds that price; it
# does not claim the price is zero.
#
# WHAT IT CATCHES, derived from the headroom: any per-node cost the live gen-select adds to a
# `sel.kind` match above ~0.16 thunk/node on the migrated fixture (~0.4 on the sealed one at n=400),
# including cost in the matcher every selector shares, because the frozen denominator does not pay
# it; and any rise of more than ~30 thunks in either kind's mint price, since the two mints
# are in the numerator (so a gen-schema change to `markOf`'s cost moves this row, as it should). The
# arming control below re-proves the per-node recompute on every run. WHAT IT CANNOT SEE: cost in the
# instance data plane (gen-merge, gen-schema), which both stacks still pay through the live members
# and which the ratio therefore dilutes, not cancels — the pure/ref rows gate that plane; a cost in the
# live gen-select below the headroom; and anything that makes the kind path CHEAPER (the ratio gates
# are one-sided). Re-derive with `nix run ./ci#perf-bench`.
KINDMATCH_SMALL=400
KINDMATCH_BIG=1600
# RE-ANCHORED at gen-identity `410261b` (den-hoag-xvww), margin 0.000: the two kinds' mints cost
# +275 thunks, a CONSTANT at both sizes, which moves the two n=400 thunk ratios one printed step
# (0.972 → 0.973, 0.966 → 0.967; kind 408,851 / 409,422 against attrs-ref 420,215 / 423,531 thunks at
# the relock, headroom 228 / 344). The cost is gen-identity's per-mint price (+12 thunks and +7 calls
# per two-label mint), not gen-select's: gen-select's lib is unmoved. The other bounds print unchanged.
# sealed n=1600 alloc RE-ANCHORED 0.969 → 0.970, margin 0.000 (relock26, den-hoag-ez1yq; raw bytes at
# reports/den-hoag-ez1yq-relock26-v0.md §0.1): it reads 0.970 only when gen-identity `410261b`
# (+16,368 B on kind-sealed, alone 0.96948) and gen-merge `aea02d1` (+126,512 B kind-sealed /
# +122,416 B attrs-ref-sealed, alone 0.96939) combine (0.96957) — neither reds this gate alone, and
# the sum crosses one printed step jointly. Both are correctness landings (xvww's attribution;
# gen-merge's w1k40/jzatq/2f4gm). Priced and re-anchored under owner sitting item R8's default
# (den-hoag-xwhq4): a correctness fix's stated, re-anchored price is not an xzchx regression.
# migrated, n=400  — anchors 0.973 / 0.991.
# RE-ANCHORED thunks 0.973 → 0.974, margin 0.000 (den-hoag-ez1yq relock 32, R8 default): gen-scope
# a650104 (kinds minted by a staged fold) alone; neither 67b690c nor gen-graph e10c49d moves it.
# migrated, n=1600 — anchors 0.962 / 0.976 (1,602,162 / 1,664,803 thunks; 85,042,560 / 87,154,096 B).
# RE-ANCHORED 0.962 / 0.976 → 0.963 / 0.977, margin 0.000 (den-hoag-bfc0k + 5xio7 relock, R8 default):
# thunks cross one printed step at + gen-schema fa26749 (`constructionRelation`); alloc crosses only
# with the full landing (gen-merge 50250c1 + gen-schema 4b4244a + gen-aspects 25c6f86), no arm alone.
# sealed, n=400    — anchors 0.967 / 0.984.
# RE-ANCHORED thunks 0.967 → 0.968, margin 0.000 (den-hoag-ez1yq relock 32, R8 default): gen-scope
# 67b690c (the quotient accessor); a650104 and gen-graph e10c49d leave it at 0.967.
# sealed, n=1600   — anchors 0.957 / 0.970 (1,602,745 / 1,675,319 thunks; 85,050,064 / 87,719,184 B).
# RE-ANCHORED thunks 0.957 → 0.958, margin 0.000 (den-hoag-bfc0k + 5xio7 relock, R8 default): crosses
# one printed step only with the full landing; no single-member arm reds it.
# RE-BASED (den-hoag-r8y89): the denominator runs the frozen matcher over the LIVE data plane
# (gen-merge, -schema, -scope, … — the reach census), so it is gen-vs-gen and a shared-plane
# improvement moved it. No nixpkgs operation corresponds to kind-identity selection (spec OQ1), so the
# row gates the guarded arm's OWN cost, `kind` thunks and alloc, exact, per fixture and size; the
# kind/attrs-ref ratios above are printed and gated by nothing. The KINDMATCH_{THUNKS,ALLOC}_MAX ratio
# bounds whose derivation is recorded above are retired with them. What the frozen denominator still
# buys is the byte gate. The arming control re-points: `kind-plant`'s thunks must exceed
# KINDMATCH_KIND_THUNKS_MAX[migrated,400].
declare -A KINDMATCH_KIND_THUNKS_MAX KINDMATCH_KIND_ALLOC_MAX
KINDMATCH_KIND_THUNKS_MAX[migrated,400]=411476
KINDMATCH_KIND_ALLOC_MAX[migrated,400]=24024384
KINDMATCH_KIND_THUNKS_MAX[migrated,1600]=1604276
KINDMATCH_KIND_ALLOC_MAX[migrated,1600]=93375664
KINDMATCH_KIND_THUNKS_MAX[sealed,400]=412013
KINDMATCH_KIND_ALLOC_MAX[sealed,400]=24035072
KINDMATCH_KIND_THUNKS_MAX[sealed,1600]=1604813
KINDMATCH_KIND_ALLOC_MAX[sealed,1600]=93386352

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
# projection and is pinned as the control. (2) RATIO, thunks AND alloc, entity/attrs-ref ≤ the bound,
# at both sizes. (3) LINEARITY on every stack.
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
# BOUND = ANCHOR + MARGIN, MARGIN 0.000 (xzchx: any regression is a defect). ANCHOR — the measured
# ratio at the landing: Nix 2.34.8, gen-schema `9289268`, gen-select `410f517`, frozen gen-schema
# `2b7c2d3`, frozen gen-select `9285b5b`. ratio() prints %.3f, so the headroom is the distance from the
# exact anchor to the next printed step: migrated thunks 390 / 1,972 (n=400 / 1600), alloc 20,702 /
# 60,871 B; sealed thunks 10 / 629, alloc 23,439 / 131,663 B (at (β); the gen-identity `410261b`
# re-anchor below restates them).
# (β)'s own price over `9791baf`: +12 thunks constant on the migrated fixture (the kind key the
# selector now carries); the sealed arm adds the node's kind key and one `kindEq` on the one match.
#
# THE PRICE, stated: the stamp's kind component costs +24.0 thunks per instance (one more
# ⟨label, value⟩ pair through the canonical encoder) plus the mark once per kind, which the stamp now
# forces — ≈3.3k thunks on this row's one-option kind, and more on a larger declaration, since every
# option attribute is a component of the mark. Stock gen-schema `cfec60d` as the numerator reads
# 731,629 / 2,906,629 thunks and fails the projection gate (both halves).
#
# WHAT IT CATCHES: a per-instance cost in the stamp above the headroom (~1 thunk/node), including
# the identity module built per instance rather than once per kind type (+6 thunks/node, measured
# red at landing through `--at gen-schema=path:`, exit 6); and the per-instance kind re-derivation,
# re-proved every run by the arming control below. WHAT IT CANNOT SEE: anything that makes the
# entity path CHEAPER (one-sided), and a cost below the headroom.
ENTITYMATCH_SMALL=400
ENTITYMATCH_BIG=1600
# sha256 of the JSON projections: `[ "a:h0" ]` (entity) and `[ "a:h0" "b:h0" ]` (attrs-ref).
ENTITYMATCH_DIGEST_ENTITY=6b6d42a882aa4068cc0009757746a29fd06a3ee757c08a55f179af91c2e88055
ENTITYMATCH_DIGEST_REF=b4d8cf97c0d1bfa8fe91136ed4d1fe56610ae23dadb1a30ecfd6df7f31a796a1
declare -A ENTITYMATCH_THUNKS_MAX ENTITYMATCH_ALLOC_MAX
# RE-ANCHORED at gen-identity `410261b` (den-hoag-xvww), margin 0.000. gen-identity names the kind
# and label in every mint refusal; its price is PER MINT and never per value node: +4 thunks per
# encoder instance, labels + 1 instances per mint, so +12 thunks and +7 calls for a two-label mint
# and +16 thunks for the stamp's three-label one. Measured here, one member swapped at a time:
# gen-identity alone moves entity +6,675 / +25,875 thunks (migrated) and +6,663 / +25,863 (sealed),
# i.e. +16 per instance plus a constant, and attrs-ref (which runs no library under test) is
# unmoved. Every other member of the relock together moves entity +2 thunks and +7,056 / +28,208 B
# (migrated) — gen-merge `aea02d1` — which is below a printed step alone, and takes the migrated
# alloc anchors from 1.124 / 1.115 (gen-identity alone) to 1.125 / 1.116. Headroom to the next
# printed step: migrated thunks 31 / 1,144, sealed 237 / 2,090 — so a +1-thunk-per-mint regression
# in gen-identity (+400 at n=400) reds the migrated fixture.
# RE-ANCHORED, margin 0.000 (den-hoag-bfc0k + den-hoag-5xio7 relock, owner sitting R8's default:
# a correctness fix's stated price; defaulted, reversible). Bisect by root-lock arm on hub cb6953a,
# host and Determinate agreeing:
#   (i) gen-merge e332998 (5xio7: `callD` applies `extra // declArgs`, `slotsDiffer`) and 0943b2a
#       (+ the `closuresFirst` export) red the four ALLOC gates by +0.001 each, thunks unmoved. The
#       5xio7 spec priced the `callD` swap at nil; that is FALSE on this row.
#   (ii) + gen-schema fa26749 (`constructionRelation`) moves thunks about +0.012 and alloc about
#       +0.010 more; the full landing (gen-merge 50250c1, gen-schema 4b4244a, gen-aspects 25c6f86)
#       reads the anchors below.
# migrated, n=400  — 1.311 / 1.125 → 1.326 / 1.137.
# RE-ANCHORED (den-hoag-ez1yq relock 32, R8 default), bisect by root-lock arm on the relock-32 candidate (host evaluator):
#   gen-scope a650104 (kinds minted by a staged fold) +0.001 to +0.002 on every fixture; + gen-scope
#   67b690c (the quotient accessor) about +0.006 more; gen-graph e10c49d (the key-former door) alone
#   moves only sealed n=400, 1.331 → 1.332. Alloc unmoved.
# migrated, n=400  — 1.326 → 1.334.
ENTITYMATCH_THUNKS_MAX[migrated,400]=557444/574411
ENTITYMATCH_ALLOC_MAX[migrated,400]=31319392/33627840
# migrated, n=1600 — anchors 1.307 / 1.116 (2,976,281 / 2,277,190 thunks; 148,649,792 / 133,249,584 B).
# migrated, n=1600 — 1.307 / 1.116 → 1.321 / 1.128.
# migrated, n=1600 — 1.321 → 1.329.
ENTITYMATCH_THUNKS_MAX[migrated,1600]=2186444/2277211
ENTITYMATCH_ALLOC_MAX[migrated,1600]=122482304/133250800
# sealed, n=400    — anchors 1.317 / 1.129 (756,521 / 574,390 thunks; 37,976,080 / 33,622,624 B).
# sealed, n=400    — 1.317 / 1.129 → 1.331 / 1.142.
# sealed, n=400    — 1.331 → 1.339.
ENTITYMATCH_THUNKS_MAX[sealed,400]=562659/574411
ENTITYMATCH_ALLOC_MAX[sealed,400]=31651680/33627840
# sealed, n=1600   — anchors 1.312 / 1.120 (2,986,721 / 2,277,190 thunks; 149,237,056 / 133,249,584 B).
# sealed, n=1600   — 1.312 / 1.120 → 1.326 / 1.133.
# sealed, n=1600   — 1.326 → 1.334.
ENTITYMATCH_THUNKS_MAX[sealed,1600]=2204859/2277211
ENTITYMATCH_ALLOC_MAX[sealed,1600]=123732096/133250800

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
# stacks select exactly `[ "h0" … "h63" ]`. (2) RATIO, thunks
# AND alloc, coord/coord-ref ≤ the bound, per fixture and size. (3) LINEARITY on every stack.
#
# WHY ALLOC IS GATED (den-hoag-8hqx0 gate PF5). The rejected construction A — the kind projected into
# every cell's `data` — is THUNK-NEUTRAL (+0.000/cell) and costs bytes only (+16.7 / +9.9 B/cell): a
# thunk-only row passes it. Both plants were driven through `--at gen-select=path:` at the landing and
# must exit non-zero: `plant-kindread` (the context kind read before the stamp decides, +3 thunks/cell)
# and `plant-A` (construction A). ALLOC is GC-quantised and depends on the source PATH string (the
# bank's perf-bench trap), so the anchor is read on a `path:` overlay and must be re-read at the relock
# that lands gen-select's tip.
#
# BOUND = ANCHOR + MARGIN, MARGIN 0.000 (xzchx). ANCHOR — measured at the landing: Nix 2.34.8, hub
# ec614fa, gen-select 8hqx0 tip `5348baf` (`--at gen-select=path:`), frozen gen-select `9285b5b`:
# migrated 815,275 / 814,878 thunks (n=400), 3,236,875 / 3,236,478 (n=1600) — the +397 is the constant
# (64 kind keys and the context's `coordKinds`); sealed 819,976 / 818,096 and 3,248,776 / 3,246,896 —
# the +1,880 is the 64 matching cells' `entityEq`. Constant, as the bound demands: +0.000 per cell.
# The plants, same instrument, same paths' length: plant-kindread reads thunks 1.095 / 1.095 / 1.096 /
# 1.095 and alloc 1.030-1.031; plant-A reads thunks IDENTICAL to the anchor (thunk-neutral) and alloc
# 1.010 / 1.010 / 1.012 / 1.010, so only the alloc gate refuses it.
# HEADROOM AT THE CONSTANT FLOOR (den-hoag-8hqx0 landing gate PF-b): migrated n=400 reds on any growth of
# the numerator over 10 thunks or 556 B, CONSTANT (n=1600: 1,221 thunks / 58,935 B; sealed n=400: 165 /
# 23,839 B). So a red here is not by itself a per-cell cost: compare the n=1600 and n=400 excesses over
# coord-ref — a per-cell cost scales ×4 across the step, a constant does not. The FAILURES text says so.
COORDMATCH_SMALL=400
COORDMATCH_BIG=1600
# sha256 of the JSON projection `[ "h0" … "h63" ]` (each of the 64 selectors selects its own cell),
# both stacks.
COORDMATCH_DIGEST=ec30bebff99631b2d8ef98e29a6403135aea466f4b4d1d2ab303d1dffefe77dc
# RAISED 1.000 → 1.001 (owner-approved, den-hoag-470xp arm F): the residue is one GC heap block, not a
# cost. ΔThunks coord−ref stays the row's constant 397 at gen-merge `3a8d116`, and the byte excess moves
# by whole 4 096 B blocks whose sign changes with n (+1 block at n=400, −2 at n=1600), which a per-cell
# cost could not do (reports/den-hoag-470xp-arm-f-landing-gate-v0.md §4.3).
# RE-BASED (den-hoag-r8y89), and this row is the measured case: both stacks share the live gen-schema
# instances and plane, so gen-merge c3 (`ownUnmatched = []` when nothing is undeclared) lowered coord
# and coord-ref alike and the ratio rose to 1.001 with the excess a constant +398. The row gates the
# guarded arm's OWN cost, `coord` thunks and alloc, exact; the ratios are printed, gated by nothing,
# and the COORDMATCH_{THUNKS,ALLOC}_MAX ratio bounds derived above are retired.
declare -A COORDMATCH_COORD_THUNKS_MAX COORDMATCH_COORD_ALLOC_MAX
COORDMATCH_COORD_THUNKS_MAX[migrated,400]=800763
COORDMATCH_COORD_ALLOC_MAX[migrated,400]=43747504
COORDMATCH_COORD_THUNKS_MAX[migrated,1600]=3174363
COORDMATCH_COORD_ALLOC_MAX[migrated,1600]=173125712
COORDMATCH_COORD_THUNKS_MAX[sealed,400]=807425
COORDMATCH_COORD_ALLOC_MAX[sealed,400]=44134416
COORDMATCH_COORD_THUNKS_MAX[sealed,1600]=3194225
COORDMATCH_COORD_ALLOC_MAX[sealed,1600]=174442400

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
# answers in first-reach order and gen-scope's own order cell pins that order. (2) RATIO, THUNKS
# ONLY, every n: resolve/query-orig ≤ the bound. Alloc is reported and gated by nothing: at n = 4..7
# a cell allocates 75–211 KB, so allocation's ~2.5 KB run-to-run jitter is over 1% and crosses a
# printed step (that jitter was the collector's: with GC_DONT_GC every cell reads one byte count,
# but no alloc gate is built on this row yet). (3) ARMING, every run: the `witnesses` arm (mode `witnesses`, the acyclic-path law,
# which enumerates every simple path and is factorial in n here) at n = 4..7 only — it never returns
# at n = 100 (gate P2) — must step 6 → 7 by at least RESOLUTION_WITNESSES_GROWTH_MIN and by more
# than resolve's own 6 → 7 step. A polynomial of degree d steps 6 → 7 by (7/6)^d, so ×3 needs d ≥
# 7.1: the floor separates enumeration from every walk this row could regress to. A control that
# does not read super-linear is a broken instrument, and the row then has no result. No linearity
# gate: the complete relation has n² edges, so the walk is quadratic in n by the fixture, and only a
# same-n ratio can see a regression.
#
# BOUND = ANCHOR + MARGIN, MARGIN 0.000 (kindMatch's convention). ANCHOR — the measured ratio at
# gen-scope `32e39c0` (gayc-u2e, the revision this hub pins): hub `perf-bench` app, Nix 2.34.8, frozen
# gen-graph `0db4e737`. Raw thunks resolve / query-orig: n=4 2,368 / 1,237 · 5 2,537 / 1,433 · 6 2,728
# / 1,669 · 7 2,941 / 1,945 · 100 118,912 / 202,453 · 1000 11,071,912 / 20,016,853. The small sizes
# read above 1 because the lift and the WFL's construction are a constant the frozen `query` does not
# pay; from n = 100 the walk is the cheaper. witnesses: 3,467 / 8,506 / 36,507 / 219,188 at n = 4..7
# (6 → 7: ×6.004). RE-ANCHORED (den-hoag-gayc U2d): the row landed anchored at gen-scope `cd653a2`
# (U2b), and gen-scope `32e39c0` (U2e, the converse) costs `resolve` one thunk per node more
# (n=4..7 +4..+7, n=100 +100, n=1000 +1,000), which crossed the n = 4..7 bounds by +0.003..+0.004;
# the same hub with gen-scope at `cd653a2` passes every gate, the same run. RE-ANCHORED AGAIN at
# gen-scope `35b106b` (den-hoag-di165: every node-id table keyed by the id's text through
# `key.attrKey`, once per id, so a store-path-context id resolves). That is di165's price, a
# correctness fix's linear cost: about +6 thunks fixed plus about 1 per node (attrKey's context check
# per node-id read). resolve thunks at `32e39c0` → `35b106b`: n=4 2,368 → 2,378 · 5 2,537 → 2,548 ·
# 6 2,728 → 2,740 · 7 2,941 → 2,954 · 100 118,912 → 119,018 · 1000 11,071,912 → 11,072,918;
# witnesses 3,477 / 8,517 / 36,519 / 219,201. (di165's first build `8a5586f` cost +47..+53 / +239 /
# +2,039; the bounds are held at `35b106b`, so a return to that cost reds.)
# THE DENOMINATOR FROZEN IN FULL (relock 60): until then `gen-graph-orig` ran on the LIVE gen-prelude,
# so the "frozen" query floated with every relock, and gen-prelude `ae1ce68` (door `next`, which
# refuses an unwired record step) could no longer evaluate it at all. Under `gen-prelude-orig`
# `c471c9a`, with gen-scope `35b106b` and gen-prelude `ae1ce68`, raw thunks resolve / query-orig:
# n=4 2,396 / 1,263 · 5 2,566 / 1,459 · 6 2,758 / 1,695 · 7 2,972 / 1,971 · 100 119,036 / 202,479 ·
# 1000 11,072,936 / 20,016,879; witnesses 3,495 / 8,535 / 36,537 / 219,219 (6 → 7: ×6.000). The new
# prelude's price on `resolve` is +18 thunks, constant in n. The bounds above stand: the ratios read
# 1.897 / 1.759 / 1.627 / 1.508 / 0.588 / 0.553, under every bound.
RESOLUTION_SIZES=(4 5 6 7 100 1000)
RESOLUTION_WITNESSES_SIZES=(4 5 6 7)
RESOLUTION_WITNESSES_GROWTH_MIN=3.0
declare -A RESOLUTION_THUNKS_MAX
RESOLUTION_THUNKS_MAX[4]=2365/1267
RESOLUTION_THUNKS_MAX[5]=2533/1463
RESOLUTION_THUNKS_MAX[6]=2723/1699
RESOLUTION_THUNKS_MAX[7]=2935/1975
RESOLUTION_THUNKS_MAX[100]=118813/202483
RESOLUTION_THUNKS_MAX[1000]=11070913/20016883

declare -A CPU CPU_SAMPLES THUNKS ALLOC DIG
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
  CELL="workload=$w n=$n stack=$s rep=$rep"
  # errexit fires at the ASSIGNMENT — a failing command substitution carries its own status, so a
  # bare redirect plus a later stats-file test would never be reached. The status is taken by hand.
  # GC_DONT_GC: the collector off makes `gc.totalBytes` one byte count per tree (header); the
  # evaluator then warns on stderr that it could not collect before reporting, which is expected.
  status=0
  out=$(GC_DONT_GC=1 NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$statf" nix-instantiate --eval --strict \
    "$PERF_WORKLOADS" --arg srcs "import $SRCS" \
    --argstr stack "$s" --argstr workload "$w" --arg n "$n" 2>"$errf") || status=$?
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
PREFLIGHT=$(nix-instantiate --eval --strict --json "$PERF_WORKLOADS" \
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

# ── compute ratios + gate outcomes (no printing; emit_report reads these) ──────
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
  # CR is computed and reported but never gated — see the cpu note in the header. TR/AR are the
  # printed ratios; the gates read the raw counters as NUM/DEN. A row with no recorded bound is
  # UNMEASURED (gate), so a new workload's first landing records its reading as its bound.
  tq="${THUNKS[$w,$n,pure]}/${THUNKS[$w,$n,ref]}"
  aq="${ALLOC[$w,$n,pure]}/${ALLOC[$w,$n,ref]}"
  if has_tag "$tags" r; then
    gate "ratio: $w n=$n pure/ref thunks" "$tq" "${ROW_THUNKS_MAX[$w,$n]:-}" "ROW_THUNKS_MAX[$w,$n]"
    gate "ratio: $w n=$n pure/ref alloc" "$aq" "${ROW_ALLOC_MAX[$w,$n]:-}" "ROW_ALLOC_MAX[$w,$n]"
  elif has_tag "$tags" rb; then
    # wideFreeform: ALLOC is a win-gate, THUNKS ride a parity band — two different CLAIMS, which is
    # why the band keeps its own named constant and its own failure wording.
    gate "ratio: $w n=$n pure/ref alloc" "$aq" "${ROW_ALLOC_MAX[$w,$n]:-}" "ROW_ALLOC_MAX[$w,$n]"
    gate "ratio-band: $w n=$n pure/ref thunks" "$tq" "$WIDEFREEFORM_RATIO_MAX" "WIDEFREEFORM_RATIO_MAX"
  fi
done

for w in scalar registry threadedRegistry wrappedRegistry schemaHosts inheritHosts aspects wideFreeform deepSubmodule foreignMount moduleFanIn sameLocFanIn; do
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
  gate "classShare: n=$n pure-fixed thunks (the spine reduction eroded, or the shared plane moved)" "${THUNKS[classShare,$n,pure-fixed]}" "${CLASSSHARE_FIXED_THUNKS_MAX[$n]:-}" "CLASSSHARE_FIXED_THUNKS_MAX[$n]"
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
  gate "overrideWarm: n=$n warm thunks (warm reuse eroded, or the shared plane moved)" "${THUNKS[overrideWarm,$n,warm]}" "${OVERRIDEWARM_WARM_THUNKS_MAX[$n]:-}" "OVERRIDEWARM_WARM_THUNKS_MAX[$n]"
  gate "overrideWarm: n=$n warm alloc (warm reuse eroded, or the shared plane moved)" "${ALLOC[overrideWarm,$n,warm]}" "${OVERRIDEWARM_WARM_ALLOC_MAX[$n]:-}" "OVERRIDEWARM_WARM_ALLOC_MAX[$n]"
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
    gate "kindMatch ($fx): n=$n kind thunks (the live gen-select per node, a kind's mint price, or the data plane)" "${THUNKS[kindMatch,$n,kind$sfx]}" "${KINDMATCH_KIND_THUNKS_MAX[$fx,$n]:-}" "KINDMATCH_KIND_THUNKS_MAX[$fx,$n]"
    gate "kindMatch ($fx): n=$n kind alloc (the live gen-select per node, a kind's mint price, or the data plane)" "${ALLOC[kindMatch,$n,kind$sfx]}" "${KINDMATCH_KIND_ALLOC_MAX[$fx,$n]:-}" "KINDMATCH_KIND_ALLOC_MAX[$fx,$n]"
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
if [[ $(qcmp "${THUNKS[kindMatch,$KINDMATCH_SMALL,kind-plant]}" "${KINDMATCH_KIND_THUNKS_MAX[migrated,$KINDMATCH_SMALL]:-}") != gt ]]; then
  FAILURES+=("kindMatch arming: the planted per-node recompute read kind thunks ${THUNKS[kindMatch,$KINDMATCH_SMALL,kind-plant]}, not above KINDMATCH_KIND_THUNKS_MAX[migrated,$KINDMATCH_SMALL]=${KINDMATCH_KIND_THUNKS_MAX[migrated,$KINDMATCH_SMALL]:-} — the bound cannot see the class this row exists for")
fi

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
  nix-instantiate --eval --strict "$PERF_WORKLOADS" --arg srcs "import $SRCS" \
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
    gate "entityMatch ratio ($fx): n=$n entity/attrs-ref thunks (gen-schema's stamp, or gen-identity's per-mint price)" "${THUNKS[entityMatch,$n,entity$sfx]}/${THUNKS[entityMatch,$n,attrs-ref$sfx]}" "${ENTITYMATCH_THUNKS_MAX[$fx,$n]:-}" "ENTITYMATCH_THUNKS_MAX[$fx,$n]"
    gate "entityMatch ratio ($fx): n=$n entity/attrs-ref alloc (gen-schema's stamp, or gen-identity's per-mint price)" "${ALLOC[entityMatch,$n,entity$sfx]}/${ALLOC[entityMatch,$n,attrs-ref$sfx]}" "${ENTITYMATCH_ALLOC_MAX[$fx,$n]:-}" "ENTITYMATCH_ALLOC_MAX[$fx,$n]"
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
if [[ $(qcmp "${THUNKS[entityMatch,$ENTITYMATCH_SMALL,entity-plant]}/${THUNKS[entityMatch,$ENTITYMATCH_SMALL,attrs-ref]}" "${ENTITYMATCH_THUNKS_MAX[migrated,$ENTITYMATCH_SMALL]:-}") != gt ]]; then
  FAILURES+=("entityMatch arming: the planted per-instance re-derivation read entity/attrs-ref thunks $EM_PLANT_TR ≤ ${ENTITYMATCH_THUNKS_MAX[migrated,$ENTITYMATCH_SMALL]} — the bound cannot see the class this row exists for")
fi

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
    gate "coordMatch ($fx): n=$n coord thunks (PER CELL if the n=1600 excess over coord-ref is ~4× the n=400 excess, a CONSTANT if equal, the shared plane if coord-ref moved too)" "${THUNKS[coordMatch,$n,coord$sfx]}" "${COORDMATCH_COORD_THUNKS_MAX[$fx,$n]:-}" "COORDMATCH_COORD_THUNKS_MAX[$fx,$n]"
    gate "coordMatch ($fx): n=$n coord alloc (PER CELL if the n=1600 excess over coord-ref is ~4× the n=400 excess, a CONSTANT if equal, the shared plane if coord-ref moved too)" "${ALLOC[coordMatch,$n,coord$sfx]}" "${COORDMATCH_COORD_ALLOC_MAX[$fx,$n]:-}" "COORDMATCH_COORD_ALLOC_MAX[$fx,$n]"
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
  gate "resolution ratio: n=$n resolve/query-orig thunks (per edge or per ⟨node, state⟩ if the n=1000 excess dominates, a constant if only n=4..7 move)" "${THUNKS[resolution,$n,resolve]}/${THUNKS[resolution,$n,query-orig]}" "${RESOLUTION_THUNKS_MAX[$n]:-}" "RESOLUTION_THUNKS_MAX[$n]"
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
  printf '> The ratios are printed to three places; the gates do not read them. Every ratio-gated row compares its two raw counters, NUM/DEN at full precision, EXACTLY and two-sidedly against its recorded bound (perf-bench.sh, beside each constant): above it is a regression, below it is a ratchet: owed in the same change. wideFreeform thunks are a parity band (WIDEFREEFORM_RATIO_MAX) rather than a win-gate, and ratchet like every other cost row. The cpu column is report-only on every row: cpu depends on the machine as well as on the expression, so no gate reads it (median of %s interleaved samples, collector off). See ci/README.md.\n' "$REPS"
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
  for w in scalar registry threadedRegistry wrappedRegistry schemaHosts inheritHosts aspects wideFreeform deepSubmodule foreignMount moduleFanIn sameLocFanIn; do
    printf '| %s | %s → %s | %s | %s |\n' \
      "$w" "${LIN_SMALL[$w]}" "${LIN_BIG[$w]}" "${LIN_TG[$w]}" "${LIN_AG[$w]}"
  done
  echo
  echo "### classShare (gen-class tier-2 fixed-input spine gate; pure-full vs pure-fixed; gated: pure-fixed thunks = CLASSSHARE_FIXED_THUNKS_MAX, the ratios printed)"
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
  echo "### overrideWarm (gen-merge warm re-eval / memoized override; cold vs warm; gated: warm thunks + alloc = OVERRIDEWARM_WARM_{THUNKS,ALLOC}_MAX, the ratios printed)"
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
  echo "### kindMatch (kind identity at scale, den-hoag-l0y; frozen-gen-select attrs-ref vs live kind; gated: kind thunks + alloc, exact, against their own bounds; the ratios printed)"
  echo
  echo "| fixture | n | attrs-ref thunks | kind thunks (bound) | kind alloc (bound) | thunks k/a | alloc k/a | cpu k/a | byte gate |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$KINDMATCH_SMALL" "$KINDMATCH_BIG"; do
      printf '| %s | %s | %s | %s (%s) | %s (%s) | %s | %s | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[kindMatch,$n,attrs-ref$sfx]}" "${THUNKS[kindMatch,$n,kind$sfx]}" "${KINDMATCH_KIND_THUNKS_MAX[$fx,$n]:-}" \
        "${ALLOC[kindMatch,$n,kind$sfx]}" "${KINDMATCH_KIND_ALLOC_MAX[$fx,$n]:-}" "${KM_TR[$fx,$n]}" "${KM_AR[$fx,$n]}" "${KM_CR[$fx,$n]}" "${KM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): attrs-ref %s×, kind %s×, attrs-ref-sealed %s×, kind-sealed %s× (gate ≤ %s)\n' \
    "$KINDMATCH_SMALL" "$KINDMATCH_BIG" "${KM_LIN[attrs-ref]}" "${KM_LIN[kind]}" "${KM_LIN[attrs-ref-sealed]}" "${KM_LIN[kind-sealed]}" "$GROWTH_MAX"
  printf 'arming (planted per-node recompute, n=%s): kind thunks %s (kind/attrs-ref %s, alloc %s) — must exceed KINDMATCH_KIND_THUNKS_MAX[migrated,%s] = %s\n' \
    "$KINDMATCH_SMALL" "${THUNKS[kindMatch,$KINDMATCH_SMALL,kind-plant]}" "$KM_PLANT_TR" "$KM_PLANT_AR" "$KINDMATCH_SMALL" "${KINDMATCH_KIND_THUNKS_MAX[migrated,$KINDMATCH_SMALL]:-}"
  echo
  echo "### entityMatch (instance identity at scale, den-hoag-l0y U2 + (β); frozen gen-schema + gen-select attrs-ref vs live entity; gated: the ratios, thunks + alloc, exact at full precision)"
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
  printf 'arming (planted per-instance kind re-derivation, n=%s): entity/attrs-ref thunks %s, alloc %s — must exceed %s\n' \
    "$ENTITYMATCH_SMALL" "$EM_PLANT_TR" "$EM_PLANT_AR" "$(qshow "${ENTITYMATCH_THUNKS_MAX[migrated,$ENTITYMATCH_SMALL]:-}")"
  echo
  echo "### coordMatch (the product coordinate's identity decision at scale, den-hoag-8hqx0; frozen gen-select coord-ref vs live coord; gated: coord thunks + alloc, exact, against their own bounds; the ratios printed)"
  echo
  echo "| fixture | n | coord-ref thunks | coord thunks (bound) | coord alloc (bound) | thunks c/r | alloc c/r | cpu c/r | projection |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$COORDMATCH_SMALL" "$COORDMATCH_BIG"; do
      printf '| %s | %s | %s | %s (%s) | %s (%s) | %s | %s | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[coordMatch,$n,coord-ref$sfx]}" "${THUNKS[coordMatch,$n,coord$sfx]}" "${COORDMATCH_COORD_THUNKS_MAX[$fx,$n]:-}" \
        "${ALLOC[coordMatch,$n,coord$sfx]}" "${COORDMATCH_COORD_ALLOC_MAX[$fx,$n]:-}" "${CM_TR[$fx,$n]}" "${CM_AR[$fx,$n]}" "${CM_CR[$fx,$n]}" "${CM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): coord-ref %s×, coord %s×, coord-ref-sealed %s×, coord-sealed %s× (gate ≤ %s)\n' \
    "$COORDMATCH_SMALL" "$COORDMATCH_BIG" "${CM_LIN[coord-ref]}" "${CM_LIN[coord]}" "${CM_LIN[coord-ref-sealed]}" "${CM_LIN[coord-sealed]}" "$GROWTH_MAX"
  echo
  echo "### resolution (the one resolution calculus at scale, den-hoag-gayc U2b; frozen gen-graph query-orig vs live gen-scope resolve, gated: the thunk ratio, exact at full precision; alloc reported, gated by nothing)"
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
      echo "RATCHET OWED — no gate regressed, and ${#RATCHETS[@]} cost reading(s) fell BELOW their bound. The change that adopts this combination lowers each one, and writes ANCHOR_MEMBERS='$MEMBERS_ID':"
      printf '  - %s\n' "${RATCHETS[@]}"
      ;;
  esac
}

# ── the verdict, decided BEFORE the report prints and before any splice (gate C4) ──
# Precedence: a regression or a non-cost failure (parity, linearity, arming, an unmeasured gate) is
# 1/6 whatever else holds; then an identity change, 7/9, under which no cost gate was judged; then
# readings below their bounds, 8. A ratchet-only run is never a regression (gate C2).
if [[ ${#FAILURES[@]} -gt 0 ]]; then
  if [[ ${#AT_ORDER[@]} -gt 0 ]]; then VERDICT=6; else VERDICT=1; fi
elif [[ -n $REANCHOR ]]; then
  if [[ "$MEMBERS_ID" == "$ANCHOR_MEMBERS" ]]; then VERDICT=7; else VERDICT=9; fi
elif [[ ${#RATCHETS[@]} -gt 0 ]]; then
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
