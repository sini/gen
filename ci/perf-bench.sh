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
# Exits: 0 all gates passed · 1 PERF REGRESSION (the published combination) · 2 the --update target
# is unusable, or the arguments are · 3 a dead cell (die_cell) · 4 COMBINATION UNRESOLVED · 5
# SUPPLY/DEMAND RESIDUE · 6 CANDIDATE OVER BOUND. 4/5/6 are separate codes on purpose: an
# unresolvable sibling used to exit 1, the same code as a performance regression, so no caller could
# tell "gen got slower" from "the network was down"; and a candidate breaching a bound derived at the
# baseline anchor is a fact about a combination the repository has NOT adopted, which is a different
# claim from "the published combination regressed".
#
# Injected by the flake app wrapper:
#   PERF_WORKLOADS    — store path of the workload corpus (ci/perf-bench.nix)
#   PERF_SRCS         — store path of a .nix attrset mapping lib names → source store paths (BASELINE)
#   PERF_COMBINATION  — store path of a .json map: key → { store, rev, flakeref, axis }
#
# Gates (rationale + baselines: ci/README.md) — every gate reads a DETERMINISTIC evaluator counter:
#   parity    — pure and ref digests identical for EVERY cell (byte-parity at benchmark scale)
#   ratio     — at the largest size per workload: pure thunks/alloc ≤ that row's OWN derived bound
#               (ROW_THUNKS_MAX / ROW_ALLOC_MAX below; COUNTER_RATIO_MAX only for an underived
#               workload; wideFreeform's THUNKS ride a band ≤ WIDEFREEFORM_RATIO_MAX)
#   linearity — pure counters across a ×4 size step grow ≤ 5.5× (linear ≈ 4×; quadratic ≥ 12×)
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
# nix version, taken from the last rep.

# ── the combination under test ────────────────────────────────────────────────
# `--at <member>=<source>` overlays ONE member of the pure-side source set onto the baseline. The
# baseline is the pinned locks via PERF_SRCS (members: the root flake.lock; references: ci/flake.lock), an EMPTY overlay passes it through
# untouched, and NOTHING is ever written: a combination is a value this run TAKES and NAMES, never
# state the repository must first adopt. Every run echoes the whole combination — all twelve keys,
# their revisions, and each one's LEAK set — into the report, so the artefact records the population
# it measured instead of leaving the reader to infer it from a lock file.
#
# The three REFERENCE keys are refused by name. A ratio's denominator is its control: if both arms
# float, a moved ratio is unattributable — you cannot tell whether gen got worse or nixpkgs got
# better — and the ci/README.md rejection of an absolute pure-counter ratchet rests on `ref` being
# byte-identical across arms.
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
        AT_STORE[$at_key]=$(readlink -f "$at_dir")
        AT_REV[$at_key]="(path — UNPINNED)"
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

# The source set this whole run reads. With no overlay it IS $PERF_SRCS, byte for byte.
SRCS=$PERF_SRCS
if [[ ${#AT_ORDER[@]} -gt 0 ]]; then
  {
    printf '(import %s) // {\n' "$PERF_SRCS"
    for at_key in "${AT_ORDER[@]}"; do
      printf '  "%s" = "%s";\n' "$at_key" "${AT_STORE[$at_key]}"
    done
    printf '}\n'
  } >"$tmp/srcs.nix"
  SRCS=$tmp/srcs.nix
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
  "schemaHosts 400 small"
  "schemaHosts 1600 r,big"
  "aspects 400 small,noref"
  "aspects 1600 big,noref"
  "wideFreeform 2000 small"
  "wideFreeform 8000 rb,big"
  "deepSubmodule 400 small"
  "deepSubmodule 1600 r,big"
)

REPS=3
# The DEFAULT ratio ceiling — for a ratio-gated workload whose own bound has never been derived,
# i.e. the "new den shapes should be added to perf-bench.nix" path in ci/README.md. Every workload
# that HAS been derived carries its own bound in ROW_THUNKS_MAX / ROW_ALLOC_MAX below and never
# reads this one. Nothing in the matrix reads it today.
COUNTER_RATIO_MAX=0.90
GROWTH_MAX=5.5

# ── per-row ratio bounds — DERIVED, not chosen ────────────────────────────────
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
ROW_THUNKS_MAX[scalar,8000]=0.90
ROW_ALLOC_MAX[scalar,8000]=0.754
# registry n=2000 — anchors 0.776 / 0.631; ① 0.108340 / 0.101395, ② 0.064314 / 0.046820.
ROW_THUNKS_MAX[registry,2000]=0.808
ROW_ALLOC_MAX[registry,2000]=0.654
# lazyRegistry n=2000 — anchors 0.777 / 0.632; ① 0.108440 / 0.101548, ② 0.064373 / 0.046891.
ROW_THUNKS_MAX[lazyRegistry,2000]=0.809
ROW_ALLOC_MAX[lazyRegistry,2000]=0.655
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
ROW_THUNKS_MAX[schemaHosts,1600]=1.146 # INTERIM (xzchx): ends on a return toward the fdbf140 anchor
ROW_ALLOC_MAX[schemaHosts,1600]=0.982  # INTERIM (xzchx): ends on a return toward the fdbf140 anchor
# deepSubmodule n=1600 — anchors 0.575 / 0.463; ① 0.105358 / 0.090347, ② 0.087229 / 0.065271.
ROW_THUNKS_MAX[deepSubmodule,1600]=0.618
ROW_ALLOC_MAX[deepSubmodule,1600]=0.495
# wideFreeform n=8000 — alloc anchor 0.806; ① 0.000154, ② 0.000090 (~free: this shape rides the
# per-key type merges, not the declaration spine, so neither construction touches it). Its THUNK
# bound is WIDEFREEFORM_RATIO_MAX below, which carries that row's own claim.
ROW_ALLOC_MAX[wideFreeform,8000]=0.806

# ── classShare (gen-class tier-2 fixed-input spine gate) — its OWN threshold, own rationale ──
# The fixed-input path (applyCoreFixed) skips gen-merge's discharge/fold/verify spine for the shared
# core loc, so its thunk graph must be a fraction of the full re-merge's. Measured fixed/full thunk
# ratio ≈ 0.17 (2026-07-05, Nix 2.34.7, gen-merge fdbf140) — a ~5.8× spine reduction. The gate floor
# 0.30 = measured + ~75% relative headroom, and enforces ≥3.33× — comfortably past the A1 fixed-input
# reference (2.48×, ratio 0.403; the 1.89×→2.48× spine-tax band, spec §2.5) so an erosion BELOW the A1
# band fires the gate ("any reduction" is not a pass). Sizes mirror schemaHosts/aspects (400→1600, ×4).
CLASSSHARE_SMALL=400
CLASSSHARE_BIG=1600
CLASSSHARE_RATIO_MAX=0.30

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
WIDEFREEFORM_RATIO_MAX=1.096

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
OVERRIDEWARM_SMALL=400
OVERRIDEWARM_BIG=1600
OVERRIDEWARM_RATIO_MAX=0.30

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
declare -A KINDMATCH_THUNKS_MAX KINDMATCH_ALLOC_MAX
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
KINDMATCH_THUNKS_MAX[migrated,400]=0.973
KINDMATCH_ALLOC_MAX[migrated,400]=0.991
# migrated, n=1600 — anchors 0.962 / 0.976 (1,602,162 / 1,664,803 thunks; 85,042,560 / 87,154,096 B).
KINDMATCH_THUNKS_MAX[migrated,1600]=0.962
KINDMATCH_ALLOC_MAX[migrated,1600]=0.976
# sealed, n=400    — anchors 0.967 / 0.984.
KINDMATCH_THUNKS_MAX[sealed,400]=0.967
KINDMATCH_ALLOC_MAX[sealed,400]=0.984
# sealed, n=1600   — anchors 0.957 / 0.970 (1,602,745 / 1,675,319 thunks; 85,050,064 / 87,719,184 B).
KINDMATCH_THUNKS_MAX[sealed,1600]=0.957
KINDMATCH_ALLOC_MAX[sealed,1600]=0.970

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
# migrated, n=400  — anchors 1.311 / 1.125 (753,281 / 574,390 thunks; 37,814,800 / 33,622,624 B).
ENTITYMATCH_THUNKS_MAX[migrated,400]=1.311
ENTITYMATCH_ALLOC_MAX[migrated,400]=1.125
# migrated, n=1600 — anchors 1.307 / 1.116 (2,976,281 / 2,277,190 thunks; 148,649,792 / 133,249,584 B).
ENTITYMATCH_THUNKS_MAX[migrated,1600]=1.307
ENTITYMATCH_ALLOC_MAX[migrated,1600]=1.116
# sealed, n=400    — anchors 1.317 / 1.129 (756,521 / 574,390 thunks; 37,976,080 / 33,622,624 B).
ENTITYMATCH_THUNKS_MAX[sealed,400]=1.317
ENTITYMATCH_ALLOC_MAX[sealed,400]=1.129
# sealed, n=1600   — anchors 1.312 / 1.120 (2,986,721 / 2,277,190 thunks; 149,237,056 / 133,249,584 B).
ENTITYMATCH_THUNKS_MAX[sealed,1600]=1.312
ENTITYMATCH_ALLOC_MAX[sealed,1600]=1.120

declare -A CPU CPU_SAMPLES THUNKS ALLOC DIG
declare -A CR TR AR PAR
CELL_ERRF=""
CELL_OUT=""
declare -A LIN_SMALL LIN_BIG LIN_TG LIN_AG
declare -A CS_TR CS_AR CS_CR CS_BG
declare -A EM_TR EM_AR EM_CR EM_BG EM_LIN
CS_LIN_FULL=""
CS_LIN_FIXED=""
declare -A OW_TR OW_AR OW_CR OW_BG
OW_LIN_COLD=""
OW_LIN_WARM=""
declare -A KM_TR KM_AR KM_CR KM_BG KM_LIN
KM_PLANT_TR=""
KM_PLANT_AR=""
FAILURES=()
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
  status=0
  out=$(NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$statf" nix-instantiate --eval --strict \
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
  # CR is computed and reported but never gated — see the cpu note in the header.
  # Each gated assertion reads its OWN derived bound, falling back to the default for a workload
  # nobody has derived yet. The fallback is what keeps "new den shapes should be added" a live path;
  # it is not reached by anything in the matrix today.
  if has_tag "$tags" r; then
    tmax=${ROW_THUNKS_MAX[$w,$n]:-$COUNTER_RATIO_MAX}
    amax=${ROW_ALLOC_MAX[$w,$n]:-$COUNTER_RATIO_MAX}
    lte "${TR[$w,$n]}" "$tmax" || FAILURES+=("ratio: $w n=$n pure/ref thunks ${TR[$w,$n]} > $tmax")
    lte "${AR[$w,$n]}" "$amax" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $amax")
  elif has_tag "$tags" rb; then
    # wideFreeform: ALLOC is a win-gate, THUNKS ride a parity band — two different CLAIMS, which is
    # why the band keeps its own named constant and its own failure wording.
    amax=${ROW_ALLOC_MAX[$w,$n]:-$COUNTER_RATIO_MAX}
    lte "${AR[$w,$n]}" "$amax" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $amax")
    lte "${TR[$w,$n]}" "$WIDEFREEFORM_RATIO_MAX" || FAILURES+=("ratio-band: $w n=$n pure/ref thunks ${TR[$w,$n]} > $WIDEFREEFORM_RATIO_MAX")
  fi
done

for w in scalar registry schemaHosts aspects wideFreeform deepSubmodule; do
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
# the perf-scale twin of gateCore), gates the spine reduction against CLASSSHARE_RATIO_MAX, and owns its
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
  # SPINE-REDUCTION gate: fixed-input thunks ≤ full-merge thunks × threshold (the A1-band floor).
  lte "${CS_TR[$n]}" "$CLASSSHARE_RATIO_MAX" \
    || FAILURES+=("classShare spine gate: n=$n fixed/full thunks expected≤$CLASSSHARE_RATIO_MAX actual=${CS_TR[$n]} delta=$(delta "${CS_TR[$n]}" "$CLASSSHARE_RATIO_MAX") — spine reduction eroded below the A1 band")
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
# gates the warm reuse (thunks AND alloc) against OVERRIDEWARM_RATIO_MAX, and owns its linearity check.
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
  # REUSE gate: warm thunks AND alloc ≤ cold × threshold (both deterministic, both reduce under reuse).
  lte "${OW_TR[$n]}" "$OVERRIDEWARM_RATIO_MAX" \
    || FAILURES+=("overrideWarm reuse gate: n=$n warm/cold thunks expected≤$OVERRIDEWARM_RATIO_MAX actual=${OW_TR[$n]} delta=$(delta "${OW_TR[$n]}" "$OVERRIDEWARM_RATIO_MAX") — warm reuse eroded")
  lte "${OW_AR[$n]}" "$OVERRIDEWARM_RATIO_MAX" \
    || FAILURES+=("overrideWarm reuse gate: n=$n warm/cold alloc expected≤$OVERRIDEWARM_RATIO_MAX actual=${OW_AR[$n]} delta=$(delta "${OW_AR[$n]}" "$OVERRIDEWARM_RATIO_MAX") — warm reuse eroded")
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
    lte "${KM_TR[$fx,$n]}" "${KINDMATCH_THUNKS_MAX[$fx,$n]}" \
      || FAILURES+=("kindMatch ratio ($fx): n=$n kind/attrs-ref thunks expected≤${KINDMATCH_THUNKS_MAX[$fx,$n]} actual=${KM_TR[$fx,$n]} delta=$(delta "${KM_TR[$fx,$n]}" "${KINDMATCH_THUNKS_MAX[$fx,$n]}") — the kind path costs more: the live gen-select per node, or a kind's mint price (gen-schema's mark, gen-identity's mint)")
    lte "${KM_AR[$fx,$n]}" "${KINDMATCH_ALLOC_MAX[$fx,$n]}" \
      || FAILURES+=("kindMatch ratio ($fx): n=$n kind/attrs-ref alloc expected≤${KINDMATCH_ALLOC_MAX[$fx,$n]} actual=${KM_AR[$fx,$n]} delta=$(delta "${KM_AR[$fx,$n]}" "${KINDMATCH_ALLOC_MAX[$fx,$n]}") — the kind path allocates more: the live gen-select per node, or a kind's mint price (gen-schema's mark, gen-identity's mint)")
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
if lte "$KM_PLANT_TR" "${KINDMATCH_THUNKS_MAX[migrated,$KINDMATCH_SMALL]}"; then
  FAILURES+=("kindMatch arming: the planted per-node recompute read kind/attrs-ref thunks $KM_PLANT_TR ≤ ${KINDMATCH_THUNKS_MAX[migrated,$KINDMATCH_SMALL]} — the bound cannot see the class this row exists for")
fi

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
    lte "${EM_TR[$fx,$n]}" "${ENTITYMATCH_THUNKS_MAX[$fx,$n]}" \
      || FAILURES+=("entityMatch ratio ($fx): n=$n entity/attrs-ref thunks expected≤${ENTITYMATCH_THUNKS_MAX[$fx,$n]} actual=${EM_TR[$fx,$n]} delta=$(delta "${EM_TR[$fx,$n]}" "${ENTITYMATCH_THUNKS_MAX[$fx,$n]}") — the entity path costs more per node (gen-schema's stamp, or gen-identity's per-mint price)")
    lte "${EM_AR[$fx,$n]}" "${ENTITYMATCH_ALLOC_MAX[$fx,$n]}" \
      || FAILURES+=("entityMatch ratio ($fx): n=$n entity/attrs-ref alloc expected≤${ENTITYMATCH_ALLOC_MAX[$fx,$n]} actual=${EM_AR[$fx,$n]} delta=$(delta "${EM_AR[$fx,$n]}" "${ENTITYMATCH_ALLOC_MAX[$fx,$n]}") — the entity path allocates more per node (gen-schema's stamp, or gen-identity's per-mint price)")
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
if lte "$EM_PLANT_TR" "${ENTITYMATCH_THUNKS_MAX[migrated,$ENTITYMATCH_SMALL]}"; then
  FAILURES+=("entityMatch arming: the planted per-instance re-derivation read entity/attrs-ref thunks $EM_PLANT_TR ≤ ${ENTITYMATCH_THUNKS_MAX[migrated,$ENTITYMATCH_SMALL]} — the bound cannot see the class this row exists for")
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
  printf '> The leak column is the DEFAULTED formals this source set cannot name, so they resolved from that member'\''s OWN lock rather than from the combination above — gen-graph is not a key here, which is why a leak is a declared class and not a refusal. The REQUIRED-and-unnameable residue is empty, or this run would have refused at exit 5 before collecting a cell; arming, same predicate: %s. Entries that are not functions, so they declare no formals to read: %s. The three reference keys do not take --at, because a ratio'\''s denominator is its control.\n' \
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
  printf '> Every ratio-gated row carries its OWN bound, derived from its measured anchor plus a margin smaller than the cheaper of the two constructions the one-engine consolidation introduced on it (the derivation is in perf-bench.sh beside each constant, the record in ci/README.md). wideFreeform thunks ride a parity band (gate ≤ %s) rather than a win-gate, because freeform absorption is thunk-parity with nixpkgs. The cpu column is report-only on every row: cpu depends on the machine as well as on the expression, so no gate reads it (median of %s interleaved samples). See ci/README.md.\n' "$WIDEFREEFORM_RATIO_MAX" "$REPS"
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
  echo "### linearity (pure stack, ×4 size step; linear ≈ 4.0, gate ≤ $GROWTH_MAX)"
  echo
  echo "| workload | sizes | thunk growth | alloc growth |"
  echo "|---|---|---:|---:|"
  for w in scalar registry schemaHosts aspects wideFreeform deepSubmodule; do
    printf '| %s | %s → %s | %s | %s |\n' \
      "$w" "${LIN_SMALL[$w]}" "${LIN_BIG[$w]}" "${LIN_TG[$w]}" "${LIN_AG[$w]}"
  done
  echo
  echo "### classShare (gen-class tier-2 fixed-input spine gate; pure-full vs pure-fixed, gate ≤ $CLASSSHARE_RATIO_MAX)"
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
  echo "### overrideWarm (gen-merge warm re-eval / memoized override; cold vs warm, gate ≤ $OVERRIDEWARM_RATIO_MAX on thunks + alloc)"
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
  echo "### kindMatch (kind identity at scale, den-hoag-l0y; frozen-gen-select attrs-ref vs live kind, per-fixture per-size bounds on thunks + alloc at anchor + 0.000)"
  echo
  echo "| fixture | n | attrs-ref thunks | kind thunks | thunks k/a (≤) | alloc k/a (≤) | cpu k/a | byte gate |"
  echo "|---|---|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$KINDMATCH_SMALL" "$KINDMATCH_BIG"; do
      printf '| %s | %s | %s | %s | %s (%s) | %s (%s) | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[kindMatch,$n,attrs-ref$sfx]}" "${THUNKS[kindMatch,$n,kind$sfx]}" \
        "${KM_TR[$fx,$n]}" "${KINDMATCH_THUNKS_MAX[$fx,$n]}" "${KM_AR[$fx,$n]}" "${KINDMATCH_ALLOC_MAX[$fx,$n]}" "${KM_CR[$fx,$n]}" "${KM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): attrs-ref %s×, kind %s×, attrs-ref-sealed %s×, kind-sealed %s× (gate ≤ %s)\n' \
    "$KINDMATCH_SMALL" "$KINDMATCH_BIG" "${KM_LIN[attrs-ref]}" "${KM_LIN[kind]}" "${KM_LIN[attrs-ref-sealed]}" "${KM_LIN[kind-sealed]}" "$GROWTH_MAX"
  printf 'arming (planted per-node recompute, n=%s): kind/attrs-ref thunks %s, alloc %s — must exceed %s\n' \
    "$KINDMATCH_SMALL" "$KM_PLANT_TR" "$KM_PLANT_AR" "${KINDMATCH_THUNKS_MAX[migrated,$KINDMATCH_SMALL]}"
  echo
  echo "### entityMatch (instance identity at scale, den-hoag-l0y U2 + (β); frozen gen-schema + gen-select attrs-ref vs live entity, per-fixture per-size bounds on thunks + alloc at anchor + 0.000)"
  echo
  echo "| fixture | n | attrs-ref thunks | entity thunks | thunks e/a (≤) | alloc e/a (≤) | cpu e/a | projection |"
  echo "|---|---|---:|---:|---:|---:|---:|---|"
  for fx in migrated sealed; do
    sfx=""
    [[ "$fx" == sealed ]] && sfx="-sealed"
    for n in "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG"; do
      printf '| %s | %s | %s | %s | %s (%s) | %s (%s) | %s | %s |\n' \
        "$fx" "$n" "${THUNKS[entityMatch,$n,attrs-ref$sfx]}" "${THUNKS[entityMatch,$n,entity$sfx]}" \
        "${EM_TR[$fx,$n]}" "${ENTITYMATCH_THUNKS_MAX[$fx,$n]}" "${EM_AR[$fx,$n]}" "${ENTITYMATCH_ALLOC_MAX[$fx,$n]}" "${EM_CR[$fx,$n]}" "${EM_BG[$fx,$n]}"
    done
  done
  echo
  printf 'thunk linearity (%s → %s, ×4 step): attrs-ref %s×, entity %s×, attrs-ref-sealed %s×, entity-sealed %s× (gate ≤ %s)\n' \
    "$ENTITYMATCH_SMALL" "$ENTITYMATCH_BIG" "${EM_LIN[attrs-ref]}" "${EM_LIN[entity]}" "${EM_LIN[attrs-ref-sealed]}" "${EM_LIN[entity-sealed]}" "$GROWTH_MAX"
  printf 'arming (planted per-instance kind re-derivation, n=%s): entity/attrs-ref thunks %s, alloc %s — must exceed %s\n' \
    "$ENTITYMATCH_SMALL" "$EM_PLANT_TR" "$EM_PLANT_AR" "${ENTITYMATCH_THUNKS_MAX[migrated,$ENTITYMATCH_SMALL]}"
  echo
  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    echo "ALL GATES PASSED (parity + ratio + linearity)"
  elif [[ ${#AT_ORDER[@]} -gt 0 ]]; then
    echo "CANDIDATE OVER BOUND — ${#FAILURES[@]} gate(s) failed on the CANDIDATE combination above, which this repository has not adopted:"
    printf '  - %s\n' "${FAILURES[@]}"
  else
    echo "PERF REGRESSION — ${#FAILURES[@]} gate(s) failed:"
    printf '  - %s\n' "${FAILURES[@]}"
  fi
}

emit_report | tee "$tmp/report.md"

# ── optional: splice the report into a doc's marker block ─────────────────────
# The FAILURES exit fires AFTER the splice — a failing run still records what it measured.
# Tables are spliced compact (`|---|---:|`); the repo's format-before-commit pass pads them to the
# committed form, so run the formatter after an --update. Counters are deterministic, so a re-run then
# diffs only the timing values inside the markers.
if [[ -n "$UPDATE_FILE" ]]; then
  # report.md opens with a blank line and closes on the gate summary; the trailing `print ""`
  # supplies the blank line mdformat wants before the closing HTML comment, so the spliced block
  # is already treefmt-clean.
  awk -v rep="$tmp/report.md" '
    /<!-- BEGIN PERF-BENCH -->/ { print; while ((getline l < rep) > 0) print l; print ""; skip=1; next }
    /<!-- END PERF-BENCH -->/   { skip=0 }
    !skip { print }
  ' "$UPDATE_FILE" >"$UPDATE_FILE.tmp" && mv "$UPDATE_FILE.tmp" "$UPDATE_FILE"
fi

if [[ ${#FAILURES[@]} -ne 0 ]]; then
  # The bounds are derived at the BASELINE anchor, so a candidate breaching one is a real,
  # reportable fact about a combination the repository has not adopted — a different claim from
  # "the published combination regressed", and it gets its own code rather than being folded in.
  if [[ ${#AT_ORDER[@]} -gt 0 ]]; then
    echo "perf-bench: CANDIDATE OVER BOUND — ${#FAILURES[@]} gate(s) failed on a candidate combination (see report above)" >&2
    exit 6
  fi
  echo "PERF REGRESSION — ${#FAILURES[@]} gate(s) failed (see report above)" >&2
  exit 1
fi
