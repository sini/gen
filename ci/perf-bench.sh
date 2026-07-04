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
#   linearity — pure counters across a ×4 size step grow ≤ 5.5× (linear ≈ 4×; quadratic ≥ 12×)
#
# cpu is the median of $REPS runs (same-process ratio, robust to host speed); thunk/alloc counters
# are deterministic per nix version, taken from the last rep.

UPDATE_FILE=""
if [[ "${1:-}" == "--update" ]]; then
  UPDATE_FILE=${2:?--update needs a file path}
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# "workload n tags" — tags: r = ratio-gated size, small/big = linearity pair (big = 4×small)
MATRIX=(
  "startup 1 none"
  "scalar 2000 small"
  "scalar 8000 r,big"
  "registry 500 small"
  "registry 2000 r,big"
  "lazyRegistry 2000 r"
  "schemaHosts 400 small"
  "schemaHosts 1600 r,big"
  "aspects 400 small"
  "aspects 1600 r,big"
)

REPS=3
CPU_RATIO_MAX=0.85
COUNTER_RATIO_MAX=0.90
GROWTH_MAX=5.5

declare -A CPU THUNKS ALLOC DIG
declare -A CR TR AR PAR
declare -A LIN_SMALL LIN_BIG LIN_TG LIN_AG
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

# ── measure ──────────────────────────────────────────────────────────────────
echo "collecting: ${#MATRIX[@]} cells × 2 stacks × $REPS reps ..." >&2
for row in "${MATRIX[@]}"; do
  read -r w n _tags <<<"$row"
  run_cell "$w" "$n" pure
  run_cell "$w" "$n" ref
done

# ── compute ratios + gate outcomes (no printing; emit_report reads these) ──────
for row in "${MATRIX[@]}"; do
  read -r w n tags <<<"$row"
  CR["$w,$n"]=$(ratio "${CPU[$w,$n,pure]}" "${CPU[$w,$n,ref]}")
  TR["$w,$n"]=$(ratio "${THUNKS[$w,$n,pure]}" "${THUNKS[$w,$n,ref]}")
  AR["$w,$n"]=$(ratio "${ALLOC[$w,$n,pure]}" "${ALLOC[$w,$n,ref]}")
  if [[ "${DIG[$w,$n,pure]}" == "${DIG[$w,$n,ref]}" && -n "${DIG[$w,$n,pure]}" ]]; then
    PAR["$w,$n"]="ok"
  else
    PAR["$w,$n"]="MISMATCH"
    FAILURES+=("parity: $w n=$n pure=${DIG[$w,$n,pure]:-<none>} ref=${DIG[$w,$n,ref]:-<none>}")
  fi
  if [[ ",$tags," == *",r,"* ]]; then
    lte "${CR[$w,$n]}" "$CPU_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref cpu ${CR[$w,$n]} > $CPU_RATIO_MAX")
    lte "${TR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref thunks ${TR[$w,$n]} > $COUNTER_RATIO_MAX")
    lte "${AR[$w,$n]}" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref alloc ${AR[$w,$n]} > $COUNTER_RATIO_MAX")
  fi
done

for w in scalar registry schemaHosts aspects; do
  small_n=""
  big_n=""
  for row in "${MATRIX[@]}"; do
    read -r rw rn tags <<<"$row"
    [[ "$rw" == "$w" && ",$tags," == *",small,"* ]] && small_n=$rn
    [[ "$rw" == "$w" && ",$tags," == *",big,"* ]] && big_n=$rn
  done
  LIN_SMALL["$w"]=$small_n
  LIN_BIG["$w"]=$big_n
  LIN_TG["$w"]=$(ratio "${THUNKS[$w,$big_n,pure]}" "${THUNKS[$w,$small_n,pure]}")
  LIN_AG["$w"]=$(ratio "${ALLOC[$w,$big_n,pure]}" "${ALLOC[$w,$small_n,pure]}")
  lte "${LIN_TG[$w]}" "$GROWTH_MAX" || FAILURES+=("linearity: $w thunks grew ${LIN_TG[$w]}× over a 4× size step")
  lte "${LIN_AG[$w]}" "$GROWTH_MAX" || FAILURES+=("linearity: $w alloc grew ${LIN_AG[$w]}× over a 4× size step")
done

# ── report (pure printing from the computed values above) ──────────────────────
emit_report() {
  echo
  echo "## gen module-system perf bench (pure vs pinned nixpkgs.lib stack)"
  echo
  echo "| workload | n | ref cpu (s) | pure cpu (s) | cpu p/r | thunks p/r | alloc p/r | parity |"
  echo "|---|---:|---:|---:|---:|---:|---:|---|"
  for row in "${MATRIX[@]}"; do
    read -r w n _tags <<<"$row"
    printf '| %s | %s | %.3f | %.3f | %s | %s | %s | %s |\n' \
      "$w" "$n" "${CPU[$w,$n,ref]}" "${CPU[$w,$n,pure]}" \
      "${CR[$w,$n]}" "${TR[$w,$n]}" "${AR[$w,$n]}" "${PAR[$w,$n]}"
  done
  echo
  echo "### linearity (pure stack, ×4 size step; linear ≈ 4.0, gate ≤ $GROWTH_MAX)"
  echo
  echo "| workload | sizes | thunk growth | alloc growth |"
  echo "|---|---|---:|---:|"
  for w in scalar registry schemaHosts aspects; do
    printf '| %s | %s → %s | %s | %s |\n' \
      "$w" "${LIN_SMALL[$w]}" "${LIN_BIG[$w]}" "${LIN_TG[$w]}" "${LIN_AG[$w]}"
  done
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
