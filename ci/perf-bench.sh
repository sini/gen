# gen perf-regression bench — drives ci/perf-bench.nix (pure vs reference stack) through
# nix-instantiate + NIX_SHOW_STATS, checks regression gates, prints a markdown report.
#
# Usage:
#   gen-perf-bench                     — report to stdout, enforce gates (exit 1 on regression;
#                                        exit 3 if a workload cell's eval dies, with its stderr)
#   gen-perf-bench --update FILE.md    — same, and splice the report into FILE.md's
#                                        <!-- BEGIN PERF-BENCH --> / <!-- END PERF-BENCH --> block
#                                        (the live BENCHMARKS.md section)
#
# Injected by the flake app wrapper:
#   PERF_WORKLOADS — store path of the workload corpus (ci/perf-bench.nix)
#   PERF_SRCS      — store path of a .nix attrset mapping lib names → source store paths
#
# Gates (rationale + baselines: ci/README.md) — every gate reads a DETERMINISTIC evaluator counter:
#   parity    — pure and ref digests identical for EVERY cell (byte-parity at benchmark scale)
#   ratio     — at the largest size per workload: pure thunks/alloc ≤ 0.90×ref
#               (wideFreeform exception: only ALLOC keeps the default gate; THUNKS ride a band ≤ WIDEFREEFORM_RATIO_MAX)
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

UPDATE_FILE=""
if [[ "${1:-}" == "--update" ]]; then
  UPDATE_FILE=${2:?--update needs a file path}
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

# "workload n tags" — tags: r = ratio-gated size (default win-gate), rb = wideFreeform ratio size
# (only alloc default-gated; thunks band ≤ WIDEFREEFORM_RATIO_MAX), small/big = linearity pair (big = 4×small)
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
COUNTER_RATIO_MAX=0.90
GROWTH_MAX=5.5

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
# the THUNK ratio rides a band; only ALLOC stays on the default win-gate.
# Deterministic anchors (2026-07-05, Nix 2.34.7, gen-merge fdbf140) at n=8000: thunks 1.099, alloc 0.821.
# The thunk ceiling 1.3 = measured 1.099 + ~18% headroom. The real teeth are LINEARITY (the O(n^2)
# freeform blowup this workload was built to catch — pre-fix n=8000 thunks were 468×ref, gated at
# GROWTH_MAX over a 4x step) + the thunk band + the deterministic counters. This cell also used to carry
# a cpu band of its own; it was the thinnest-margin cpu gate in the matrix (0.914 measured against a 0.95
# ceiling — 3.9% headroom on an instrument whose noise floor is a ~2.2× raw frequency-regime step) and it is
# retired with the rest, along with the 0.776–0.888 spread that set it: that spread was produced by the
# blocked A-then-B protocol this script no longer runs, and a figure a blocked protocol produced on this
# host is not evidence about the subject. The same reasoning, with these figures, is written out in
# ci/README.md's wideFreeform section; regenerate via `nix run ./ci#perf-bench`.
WIDEFREEFORM_RATIO_MAX=1.3

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

declare -A CPU CPU_SAMPLES THUNKS ALLOC DIG
declare -A CR TR AR PAR
CELL_ERRF=""
CELL_OUT=""
declare -A LIN_SMALL LIN_BIG LIN_TG LIN_AG
declare -A CS_TR CS_AR CS_CR CS_BG
CS_LIN_FULL=""
CS_LIN_FIXED=""
declare -A OW_TR OW_AR OW_CR OW_BG
OW_LIN_COLD=""
OW_LIN_WARM=""
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
    "$PERF_WORKLOADS" --arg srcs "import $PERF_SRCS" \
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
  if has_tag "$tags" r; then
    lte "${TR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref thunks ${TR[$w,$n]} > $COUNTER_RATIO_MAX")
    lte "${AR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $COUNTER_RATIO_MAX")
  elif has_tag "$tags" rb; then
    # wideFreeform: only ALLOC keeps the DEFAULT win-gate; THUNKS ride their own parity band.
    lte "${AR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $COUNTER_RATIO_MAX")
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

# ── report (pure printing from the computed values above) ──────────────────────
emit_report() {
  echo
  echo "## gen module-system perf bench (pure vs pinned nixpkgs.lib stack)"
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
  printf '> wideFreeform thunks ride a parity band (gate ≤ %s, not the 0.90 win-gate — freeform absorption is thunk-parity with nixpkgs); only alloc keeps the default win-gate. The cpu column is report-only on every row: cpu depends on the machine as well as on the expression, so no gate reads it (median of %s interleaved samples). See ci/README.md.\n' "$WIDEFREEFORM_RATIO_MAX" "$REPS"
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
  if [[ ${#FAILURES[@]} -eq 0 ]]; then
    echo "ALL GATES PASSED (parity + ratio + linearity)"
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
  echo "PERF REGRESSION — ${#FAILURES[@]} gate(s) failed (see report above)" >&2
  exit 1
fi
