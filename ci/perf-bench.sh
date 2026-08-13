# gen perf-regression bench — drives ci/perf-bench.nix (pure vs reference stack) through
# nix-instantiate + NIX_SHOW_STATS, checks regression gates, prints a markdown report.
#
# Usage:
#   gen-perf-bench                     — report to stdout, enforce gates (exit 1 on regression)
#   gen-perf-bench --update FILE.md    — same, and splice the report into FILE.md's
#                                        <!-- BEGIN PERF-BENCH --> / <!-- END PERF-BENCH --> block
#                                        (the live BENCHMARKS.md section)
#
# Injected by the flake app wrapper:
#   PERF_WORKLOADS — store path of the workload corpus (ci/perf-bench.nix)
#   PERF_SRCS      — store path of a .nix attrset mapping lib names → source store paths
#
# Gates (rationale + baselines: ci/README.md):
#   parity    — pure and ref digests identical for EVERY cell (byte-parity at benchmark scale)
#   ratio     — at the largest size per workload: pure cpu ≤ 0.85×ref; pure thunks/alloc ≤ 0.90×ref
#               (wideFreeform exception: only ALLOC keeps the default gate; THUNKS ride a band ≤ WIDEFREEFORM_RATIO_MAX
#               and CPU rides a band ≤ WIDEFREEFORM_CPU_MAX — the cell is tiny + load-sensitive on cpu)
#   linearity — pure counters across a ×4 size step grow ≤ 5.5× (linear ≈ 4×; quadratic ≥ 12×)
#
# cpu is the median of $REPS runs (same-process ratio, robust to host speed); thunk/alloc counters
# are deterministic per nix version, taken from the last rep.

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
# (only alloc default-gated; thunks band ≤ WIDEFREEFORM_RATIO_MAX, cpu band ≤ WIDEFREEFORM_CPU_MAX), small/big = linearity pair (big = 4×small)
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
CPU_RATIO_MAX=0.85
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

# ── wideFreeform — THUNK band + CPU band (only alloc keeps the default win-gate) ──
# Freeform absorption is THUNK-parity with nixpkgs, not a pure win on that counter: unknown sibling keys
# route through the root freeformType, so absorption rides the SAME per-key type merges nixpkgs.lib
# performs (the pure engine's thunk win is on DECLARED option paths — see scalar/registry/aspects). So
# the THUNK ratio rides a band. CPU rides its OWN band too (same philosophy): absorption cpu IS genuinely
# sub-parity, but this cell is tiny (~0.07s) and the ratio is load-sensitive — measured spread 0.776-0.888
# at n=8000 across load conditions (quiet median ~0.80; an authoritative run under load hit 0.867), so the
# default 0.85 win-gate flakes on cpu noise, not a regression. Only ALLOC stays on the default win-gate.
# Deterministic anchors (2026-07-05, Nix 2.34.7, gen-merge fdbf140) at n=8000: thunks 1.099, alloc 0.821.
# The thunk ceiling 1.3 = measured 1.099 + ~18% headroom; the cpu ceiling 0.95 = above the load tail
# (0.888) as a gross-regression cap. The real teeth are LINEARITY (the O(n^2) freeform blowup this workload
# was built to catch — pre-fix n=8000 thunks were 468×ref, gated at GROWTH_MAX over a 4x step) + the thunk
# band + the deterministic counters; the cpu band is only a gross-regression cap. See
# den-architecture/parked/wideFreeform-b4/NOTES.md; regenerate via `nix run ./ci#perf-bench`.
WIDEFREEFORM_RATIO_MAX=1.3
WIDEFREEFORM_CPU_MAX=0.95

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

declare -A CPU THUNKS ALLOC DIG
declare -A CR TR AR PAR
declare -A LIN_SMALL LIN_BIG LIN_TG LIN_AG
declare -A CS_TR CS_AR CS_CR CS_BG
CS_LIN_FULL=""
CS_LIN_FIXED=""
declare -A OW_TR OW_AR OW_CR OW_BG
OW_LIN_COLD=""
OW_LIN_WARM=""
FAILURES=()

run_cell() {
  local w=$1 n=$2 s=$3
  local cpus=() statf="" out="" rep
  for rep in $(seq 1 "$REPS"); do
    statf="$tmp/$w-$n-$s-$rep.json"
    out=$(NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$statf" nix-instantiate --eval --strict \
      "$PERF_WORKLOADS" --arg srcs "import $PERF_SRCS" \
      --argstr stack "$s" --argstr workload "$w" --arg n "$n" 2>/dev/null)
    cpus+=("$(jq -r .cpuTime "$statf")")
  done
  CPU["$w,$n,$s"]=$(printf '%s\n' "${cpus[@]}" | sort -g | sed -n 2p)
  THUNKS["$w,$n,$s"]=$(jq -r .nrThunks "$statf")
  ALLOC["$w,$n,$s"]=$(jq -r '.gc.totalBytes // 0' "$statf")
  DIG["$w,$n,$s"]=$(printf '%s' "$out" | grep -o 'digest = "[a-f0-9]*"' | cut -d'"' -f2)
}

ratio() { awk "BEGIN{printf \"%.3f\", ($1)/($2)}"; }
lte() { awk "BEGIN{exit !(($1) <= ($2))}"; }
has_tag() { [[ ",$1," == *",$2,"* ]]; }

# ── measure ──────────────────────────────────────────────────────────────────
echo "collecting: ${#MATRIX[@]} cells (pure) + the ref arm of every non-noref row × $REPS reps ..." >&2
for row in "${MATRIX[@]}"; do
  read -r w n tags <<<"$row"
  run_cell "$w" "$n" pure
  if ! has_tag "$tags" noref; then
    run_cell "$w" "$n" ref
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
  if has_tag "$tags" r; then
    lte "${CR[$w,$n]}" "$CPU_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref cpu ${CR[$w,$n]} > $CPU_RATIO_MAX")
    lte "${TR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref thunks ${TR[$w,$n]} > $COUNTER_RATIO_MAX")
    lte "${AR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $COUNTER_RATIO_MAX")
  elif has_tag "$tags" rb; then
    # wideFreeform: only ALLOC keeps the DEFAULT win-gate; THUNKS and CPU each ride their own parity band.
    lte "${AR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $COUNTER_RATIO_MAX")
    lte "${TR[$w,$n]}" "$WIDEFREEFORM_RATIO_MAX" || FAILURES+=("ratio-band: $w n=$n pure/ref thunks ${TR[$w,$n]} > $WIDEFREEFORM_RATIO_MAX")
    lte "${CR[$w,$n]}" "$WIDEFREEFORM_CPU_MAX" || FAILURES+=("ratio-band: $w n=$n pure/ref cpu ${CR[$w,$n]} > $WIDEFREEFORM_CPU_MAX")
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
# its ratios are fixed-vs-full — NOT the pure-vs-ref parity/CPU_RATIO_MAX semantics of the matrix loop
# above. It runs its own two sizes × REPS, asserts the in-bench BYTE gate (full == fixed byte-for-byte,
# the perf-scale twin of gateCore), gates the spine reduction against CLASSSHARE_RATIO_MAX, and owns its
# linearity growth check. Failures print expected/actual/delta (the verbose STOP-on-diff discipline).
delta() { awk "BEGIN{printf \"%+.4f\", ($1)-($2)}"; }
for n in "$CLASSSHARE_SMALL" "$CLASSSHARE_BIG"; do
  run_cell classShare "$n" pure-full
  run_cell classShare "$n" pure-fixed
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
  run_cell overrideWarm "$n" cold
  run_cell overrideWarm "$n" warm
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
  printf '> wideFreeform thunks ride a parity band (gate ≤ %s, not the 0.90 win-gate — freeform absorption is thunk-parity with nixpkgs) and cpu rides a band (gate ≤ %s — tiny load-sensitive cell); only alloc keeps the default win-gate. See ci/README.md.\n' "$WIDEFREEFORM_RATIO_MAX" "$WIDEFREEFORM_CPU_MAX"
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
# Tables are emitted compact (`|---|---:|`), the form treefmt's mdformat leaves untouched, so a
# re-run diffs only the timing values inside the markers (counters are deterministic).
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
