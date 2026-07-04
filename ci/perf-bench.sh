# gen perf-regression bench — drives ci/perf-bench.nix (pure vs reference stack) through
# nix-instantiate + NIX_SHOW_STATS, checks regression gates, prints a markdown report.
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

echo "collecting: ${#MATRIX[@]} cells × 2 stacks × $REPS reps ..." >&2
for row in "${MATRIX[@]}"; do
  read -r w n _tags <<<"$row"
  run_cell "$w" "$n" pure
  run_cell "$w" "$n" ref
done

echo
echo "## gen module-system perf bench (pure vs pinned nixpkgs.lib stack)"
echo
echo "| workload | n | ref cpu (s) | pure cpu (s) | cpu p/r | thunks p/r | alloc p/r | parity |"
echo "|---|---:|---:|---:|---:|---:|---:|---|"

for row in "${MATRIX[@]}"; do
  read -r w n tags <<<"$row"
  cr=$(ratio "${CPU[$w,$n,pure]}" "${CPU[$w,$n,ref]}")
  tr=$(ratio "${THUNKS[$w,$n,pure]}" "${THUNKS[$w,$n,ref]}")
  ar=$(ratio "${ALLOC[$w,$n,pure]}" "${ALLOC[$w,$n,ref]}")
  if [[ "${DIG[$w,$n,pure]}" == "${DIG[$w,$n,ref]}" && -n "${DIG[$w,$n,pure]}" ]]; then
    par="ok"
  else
    par="MISMATCH"
    FAILURES+=("parity: $w n=$n pure=${DIG[$w,$n,pure]:-<none>} ref=${DIG[$w,$n,ref]:-<none>}")
  fi
  printf '| %s | %s | %.3f | %.3f | %s | %s | %s | %s |\n' \
    "$w" "$n" "${CPU[$w,$n,ref]}" "${CPU[$w,$n,pure]}" "$cr" "$tr" "$ar" "$par"

  if [[ ",$tags," == *",r,"* ]]; then
    lte "$cr" "$CPU_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref cpu $cr > $CPU_RATIO_MAX")
    lte "$tr" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref thunks $tr > $COUNTER_RATIO_MAX")
    lte "$ar" "$COUNTER_RATIO_MAX" || FAILURES+=("ratio: $w n=$n pure/ref alloc $ar > $COUNTER_RATIO_MAX")
  fi
done

echo
echo "### linearity (pure stack, ×4 size step; linear ≈ 4.0, gate ≤ $GROWTH_MAX)"
echo
echo "| workload | sizes | thunk growth | alloc growth |"
echo "|---|---|---:|---:|"
small_n=""
for w in scalar registry schemaHosts aspects; do
  for row in "${MATRIX[@]}"; do
    read -r rw rn tags <<<"$row"
    [[ "$rw" == "$w" && ",$tags," == *",small,"* ]] && small_n=$rn
    [[ "$rw" == "$w" && ",$tags," == *",big,"* ]] && big_n=$rn
  done
  tg=$(ratio "${THUNKS[$w,$big_n,pure]}" "${THUNKS[$w,$small_n,pure]}")
  ag=$(ratio "${ALLOC[$w,$big_n,pure]}" "${ALLOC[$w,$small_n,pure]}")
  printf '| %s | %s → %s | %s | %s |\n' "$w" "$small_n" "$big_n" "$tg" "$ag"
  lte "$tg" "$GROWTH_MAX" || FAILURES+=("linearity: $w thunks grew ${tg}× over a 4× size step")
  lte "$ag" "$GROWTH_MAX" || FAILURES+=("linearity: $w alloc grew ${ag}× over a 4× size step")
done

echo
if [[ ${#FAILURES[@]} -eq 0 ]]; then
  echo "ALL GATES PASSED (parity + ratio + linearity)"
else
  echo "PERF REGRESSION — ${#FAILURES[@]} gate(s) failed:"
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
