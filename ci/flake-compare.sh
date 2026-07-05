# flake-compare — 3-way real-flake evaluation bench: gen-flake vs flake-parts vs adios-flake.
#
# One representative flake (three trivial packages, one devShell, one formatter, × 3 systems)
# expressed THREE ways under ci/flake-compare/{flake-parts,adios,gen-flake}/. This driver replicates
# adios-flake/BENCHMARKS.md's methodology so the numbers are directly comparable with adios's
# published figures:
#
#   * 5 `nix eval` runs per (benchmark, variant), NIX_SHOW_STATS counters, flake eval-cache DISABLED
#     (`--option eval-cache false` — the equivalent of adios "eval cache cleared between runs"), so
#     every run re-evaluates the framework machinery from scratch;
#   * cpu = MEDIAN of the 5 runs (evaluator CPU, machine-dependent — comparisons are within one host);
#   * counters (function calls / prim ops / thunks / attr lookups / attrset updates / //-copies /
#     GC bytes) are DETERMINISTIC per nix version, taken from the last rep;
#   * the SAME nixpkgs is pinned across all three variants (bare `import nixpkgs { inherit system; }`),
#     so the pkgs closure is a shared constant and the measured delta is pure framework assembly.
#
# EQUIVALENCE (first-class, report-only): per output × system, the drvPath must be identical across
# all three variants — where a framework genuinely builds the same derivation, it must produce the
# same store path. A divergence is surfaced, never silently tolerated.
#
# Report-only: NO regression gates. These frameworks' code moves independently; we pin revs but do
# not gate the hub's CI on their perf. Every number is regenerable by re-running this script.
#
# Injected by the flake app wrapper (or falls back to the script's own dir for a direct run):
#   FLAKE_COMPARE_DIR — directory holding the three variant flakes.

set -uo pipefail

DIR="${FLAKE_COMPARE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/flake-compare" && pwd)}"

VARIANTS=(flake-parts adios gen-flake)
SYSTEMS=(x86_64-linux aarch64-linux x86_64-darwin)
REPS=5

# benchmark label|attr — mirrors adios BENCHMARKS.md (one single-system, two 3-system targets)
BENCHMARKS=(
  "packages.x86_64-linux (1 system)|packages.x86_64-linux"
  "formatter (3 systems)|formatter"
  "devShells (3 systems)|devShells"
)

# per-system outputs whose drvPath must agree across variants
OUTPUTS=(packages.SYS.greeter packages.SYS.farewell packages.SYS.notes devShells.SYS.default formatter.SYS)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

declare -A CPU FCALLS PRIMOPS THUNKS LOOKUPS UPDATES COPIES GCBYTES
declare -A EQ

med5() { printf '%s\n' "$@" | sort -g | sed -n 3p; }
mib() { awk "BEGIN{printf \"%.1f\", ($1)/1048576}"; }

# ── measure: 5 reps × NIX_SHOW_STATS per (benchmark, variant) ──────────────────
echo "collecting: ${#BENCHMARKS[@]} benchmarks × ${#VARIANTS[@]} variants × $REPS reps ..." >&2
for row in "${BENCHMARKS[@]}"; do
  attr=${row#*|}
  for v in "${VARIANTS[@]}"; do
    cpus=()
    statf=""
    for rep in $(seq 1 "$REPS"); do
      statf="$tmp/$v-${attr}-$rep.json"
      rm -f "$statf"
      NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$statf" \
        nix eval --option eval-cache false "path:$DIR/$v#$attr" >/dev/null 2>"$tmp/err" || true
      if [[ ! -s "$statf" ]]; then
        echo "EVAL FAILED: $v#$attr" >&2
        tail -3 "$tmp/err" >&2
        exit 1
      fi
      cpus+=("$(jq -r .cpuTime "$statf")")
    done
    key="$v,$attr"
    CPU["$key"]=$(med5 "${cpus[@]}")
    FCALLS["$key"]=$(jq -r .nrFunctionCalls "$statf")
    PRIMOPS["$key"]=$(jq -r .nrPrimOpCalls "$statf")
    THUNKS["$key"]=$(jq -r .nrThunks "$statf")
    LOOKUPS["$key"]=$(jq -r .nrLookups "$statf")
    UPDATES["$key"]=$(jq -r .nrOpUpdates "$statf")
    COPIES["$key"]=$(jq -r .nrOpUpdateValuesCopied "$statf")
    # gc.totalBytes (bytes allocated during eval) — reported as adios's "GC heap"; chosen over
    # gc.heapSize because it is deterministic (arena-independent, required for the counter claim). Same
    # field perf-bench.sh labels "alloc".
    GCBYTES["$key"]=$(jq -r '.gc.totalBytes // 0' "$statf")
  done
done

# ── equivalence: drvPath of each output × system, across all three variants ────
echo "checking equivalence: ${#OUTPUTS[@]} outputs × ${#SYSTEMS[@]} systems ..." >&2
EQ_FAILURES=()
for out in "${OUTPUTS[@]}"; do
  for sys in "${SYSTEMS[@]}"; do
    attr=${out/SYS/$sys}
    paths=()
    for v in "${VARIANTS[@]}"; do
      p=$(nix eval --raw "path:$DIR/$v#$attr.drvPath" 2>/dev/null) || p=""
      paths+=("$p")
    done
    if [[ -n "${paths[0]}" && "${paths[0]}" == "${paths[1]}" && "${paths[1]}" == "${paths[2]}" ]]; then
      EQ["$out,$sys"]="ok"
    else
      EQ["$out,$sys"]="DIVERGE"
      EQ_FAILURES+=("$attr: flake-parts=${paths[0]:-<none>} adios=${paths[1]:-<none>} gen-flake=${paths[2]:-<none>}")
    fi
  done
done

# ── report (adios BENCHMARKS.md table shape, three variant columns) ────────────
echo
echo "## flake-compare — 3-way real-flake eval bench (gen-flake vs flake-parts vs adios-flake)"
echo
echo "5 \`nix eval\` runs per cell, \`NIX_SHOW_STATS\`, flake eval-cache disabled; same nixpkgs pinned across all three variants. cpu = median of 5 (evaluator CPU, same-host); counters are deterministic per nix version. Regenerate: \`nix run ./ci#flake-compare\`."
echo
echo "### Summary — median CPU time"
echo
echo "| Benchmark | flake-parts | adios-flake | gen-flake |"
echo "|:---|---:|---:|---:|"
for row in "${BENCHMARKS[@]}"; do
  label=${row%|*}
  attr=${row#*|}
  printf '| %s |' "$label"
  for v in "${VARIANTS[@]}"; do printf ' %.3fs |' "${CPU[$v,$attr]}"; done
  printf '\n'
done
echo

for row in "${BENCHMARKS[@]}"; do
  label=${row%|*}
  ATTR=${row#*|}
  echo "### $label"
  echo
  echo "| Metric | flake-parts | adios-flake | gen-flake |"
  echo "|:---|---:|---:|---:|"
  printf '| CPU time |'; for v in "${VARIANTS[@]}"; do printf ' %.3fs |' "${CPU[$v,$ATTR]}"; done; printf '\n'
  printf '| Function calls |'; for v in "${VARIANTS[@]}"; do printf " %'d |" "${FCALLS[$v,$ATTR]}"; done; printf '\n'
  printf '| Prim op calls |'; for v in "${VARIANTS[@]}"; do printf " %'d |" "${PRIMOPS[$v,$ATTR]}"; done; printf '\n'
  printf '| Thunks created |'; for v in "${VARIANTS[@]}"; do printf " %'d |" "${THUNKS[$v,$ATTR]}"; done; printf '\n'
  printf '| Attr lookups |'; for v in "${VARIANTS[@]}"; do printf " %'d |" "${LOOKUPS[$v,$ATTR]}"; done; printf '\n'
  printf '| Attrset updates |'; for v in "${VARIANTS[@]}"; do printf " %'d |" "${UPDATES[$v,$ATTR]}"; done; printf '\n'
  printf '| Values copied (//) |'; for v in "${VARIANTS[@]}"; do printf " %'d |" "${COPIES[$v,$ATTR]}"; done; printf '\n'
  printf '| GC heap |'; for v in "${VARIANTS[@]}"; do printf ' %s MiB |' "$(mib "${GCBYTES[$v,$ATTR]}")"; done; printf '\n'
  echo
done

echo "### Derivation equivalence (drvPath across all three variants)"
echo
echo "| output | x86_64-linux | aarch64-linux | x86_64-darwin |"
echo "|:---|:---:|:---:|:---:|"
for out in "${OUTPUTS[@]}"; do
  printf '| %s |' "${out//SYS/<sys>}"
  for sys in "${SYSTEMS[@]}"; do
    if [[ "${EQ[$out,$sys]}" == "ok" ]]; then printf ' identical |'; else printf ' DIVERGE |'; fi
  done
  printf '\n'
done
echo
if [[ ${#EQ_FAILURES[@]} -eq 0 ]]; then
  echo "All ${#OUTPUTS[@]} outputs × ${#SYSTEMS[@]} systems produce byte-identical drvPaths across flake-parts / adios-flake / gen-flake — no structural exceptions."
else
  echo "EQUIVALENCE DIVERGENCE — ${#EQ_FAILURES[@]} output(s) differ across variants:"
  printf '  - %s\n' "${EQ_FAILURES[@]}"
fi
