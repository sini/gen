# fleet-consistency — the TRUST-SURFACE arithmetic roster for the A1 fleet numbers this hub cites.
#
# BENCHMARKS.md §"Fleet-scale results" and VALIDATION.md §7 cite the real-fleet numbers measured in the
# hola LAB (github:sini/hola — the fleet-eval measurement lab: it forces the den fleet under deterministic
# evaluator counters and freezes the results). The three baselines those sections quote are COMMITTED here
# verbatim (ci/bench/baselines/, provenance in that dir's README). This script re-asserts the pure-JSON
# arithmetic OVER those committed files — pin agreement, the arithmetic re-derivations, the byte-digest
# ties, and the two pinned floors — so the cited numbers cannot silently drift from their own arithmetic.
#
# OWNER PRINCIPLE: libraries stay unburdened by fleet metrics; metrics live in metrics homes. hola is the
# LAB (owns re-MEASUREMENT of the fleet — that is where a stranger re-runs the arms; see the baselines
# README refresh procedure). This hub is the TRUST SURFACE — its ci is already all metrics, and it cites
# these numbers, so the drift tooth belongs HERE. This is the [consistency] partition ONLY: pure jq,
# seconds, corpus-INDEPENDENT, NO eval, NO NIX_SHOW_STATS, NO fleet re-measurement. The re-measurement
# partitions ([ci-remeasure]/[parity]/[local-remeasure]) stay in the hola lab (hola ci/bench/fleet-gates.sh).
#
# GATE NAMES/LABELS are kept identical to the hola lab's roster (fleet-gates.sh:306-316) so a reader can
# cross-reference the A1 report (2026-07-05-a1-fleet-measurement-report.md) gate-for-gate.
#
# COUNTER POLICY (framing; not exercised here — nothing is re-measured). The A1 report §3 two-tier policy:
# the four deterministic evaluator counters (nrFunctionCalls, nrPrimOpCalls, nrOpUpdateValuesCopied,
# nrThunks) plus both digests are exact-pinned; gcTotalBytes/cpuTime are NEVER gated (Boehm/machine noise).
# These [consistency] gates compare numbers WITHIN one committed baseline (same preamble), so they stay
# exact on all four counters; the cross-build ±0.1% band is a RE-MEASUREMENT concern, and re-measurement is
# the lab's. The exact gates read EXPLICIT counter paths, never a `.counters` glob, so an informational key
# (gcTotalBytesInformational / realizationPlaneNativeShare.countersInformational) can never leak in.
#
# FLOORS (rationale pinned next to each; update-in-PR with a fresh run, never delete a workload to pass —
# same policy as ci/README.md): Arm-R saving >= 0.60 of the fleet composition fcalls (measured 0.667).
# Realization class-share saving >= 0.008 of reconstruct fcalls (measured ~0.0158).

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: fleet-consistency [--selftest]
  (default)    the [consistency] roster — pure JSON arithmetic over the committed baselines + pin
               agreement + the pinned floors (seconds; no eval, no re-measurement)
  --selftest   TEETH — corrupt a COPY of a baseline (a counter, then a floor) and prove the roster FAILS
               (never touches the committed baselines; the copy lives in a temp dir)
EOF
}

MODE="run"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --selftest)
    MODE="selftest"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "fleet-consistency: unknown flag '$1'" >&2
    usage
    exit 2
    ;;
  esac
done

[[ -n "${FLEET_BASELINES:-}" ]] || {
  echo "fleet-consistency: FLEET_BASELINES not set (the app wrapper bakes it)" >&2
  exit 2
}

DET=(nrFunctionCalls nrPrimOpCalls nrOpUpdateValuesCopied nrThunks)
DET_JSON="$(printf '%s\n' "${DET[@]}" | jq -R . | jq -s .)" # the deterministic key list as a JSON array
BL_SRC="$FLEET_BASELINES" # the committed baselines — selftest copies these out, never edits them
FAILURES=0

# set_baselines DIR — point the consistency gates at a baseline set (DIR of the three JSONs). Normal runs
# use BL_SRC; --selftest points this at a corrupted temp copy.
set_baselines() {
  BL_DIR="$1"
  G6="$BL_DIR/g6-split.json"
  DEDUP="$BL_DIR/dedup-savings.json"
  CSR="$BL_DIR/class-share-realization.json"
}

# report LABEL DESC RC — print a labelled PASS/FAIL line and tally the global FAILURES on a nonzero RC.
report() {
  local label="$1" desc="$2" rc="$3"
  if [[ "$rc" -eq 0 ]]; then
    printf '  PASS  [%-16s] %s\n' "$label" "$desc"
  else
    printf '  FAIL  [%-16s] %s\n' "$label" "$desc"
    FAILURES=$((FAILURES + 1))
  fi
}

# ── [consistency] gates — pure JSON arithmetic over the baselines; jq -e is quiet + exits nonzero on false ──

# Cross-FILE pin agreement: the three baselines must name the SAME corpus/den/nixpkgs revs.
g_pins() {
  jq -e -n --slurpfile g6 "$G6" --slurpfile dd "$DEDUP" --slurpfile csr "$CSR" '
    ($g6[0].pins) as $g | ($dd[0].pins) as $d | ($csr[0].pins) as $c
    | ($g["nix-config"] == $d["nix-config"] and $d["nix-config"] == $c["nix-config"])
      and ($g.den == $d["den-baseline"] and $d["den-baseline"] == $c.den)
      and ($g["nixpkgs-master-channel"] == $d["nixpkgs-master-channel"]
           and $d["nixpkgs-master-channel"] == $c["nixpkgs-master-channel"])
      and ($g["nixpkgs-unstable-channel"] == $d["nixpkgs-unstable-channel"])
  ' >/dev/null
}

# Dual-SITE rev pins. In the hola LAB this gate cross-checks the gen-rebuild + den-s2 revs pinned in
# dedup-savings.json against the LIVE arm exprs (arms.json) AND ci/flake.nix's gen-rebuild input —
# "bump BOTH sites or NEITHER" (fleet-gates.sh:188). The hub carries NO arm exprs and NO gen-rebuild input:
# it copies the baselines verbatim from the lab, so there is no second site to drift against here, and the
# [consistency] partition is pure jq over the committed files by design (no live-source coupling). The
# hub's residual invariant is that the two rev pins are PRESENT and well-formed 40-hex commit shas — a
# hand-edit that blanked or truncated a pin is caught. The live cross-site check stays the lab's.
g_dualsite() {
  jq -e -n --slurpfile dd "$DEDUP" '
    ($dd[0].pins) as $p
    | (($p["gen-rebuild"] // "") | test("^[0-9a-f]{40}$"))
      and (($p["den-s2"] // "") | test("^[0-9a-f]{40}$"))
  ' >/dev/null
}

# Arm-R: savedRecompute == Σ over the SKIPPED hosts of their baseline-composition counters (g6-split);
# savedFractionOfFleetComposition == savedRecompute / fleet baseline-composition; and dedup's per-host
# `pinned` composition counters match g6-split. EXPLICIT counter paths — never gcTotalBytesInformational.
g_armR_consistency() {
  jq -e -n --slurpfile g6 "$G6" --slurpfile dd "$DEDUP" --argjson C "$DET_JSON" '
    ($g6[0]) as $g | ($dd[0]) as $d
    | ($d["rebuild-dedup"].singleHostEdit) as $she
    | ([ $she.untouchedNodes[] | select(. as $n | $g.hosts | has($n)) ]) as $skipped
    | ($C | all(. as $c
        | ($skipped | map($g.hosts[.]["baseline-composition"].counters[$c]) | add)
          == $she.savedRecompute.counters[$c]))
      and ($C | all(. as $c
        | (($she.savedRecompute.counters[$c] / $g.fleet["baseline-composition"].counters[$c])
           - $she.savedFractionOfFleetComposition[$c] | fabs) < 1e-9))
      and ($g.hosts | keys | all(. as $h | $C | all(. as $c
        | $d["class-share"].compositionWitness.perHost[$h].pinned[$c]
          == $g.hosts[$h]["baseline-composition"].counters[$c])))
  ' >/dev/null
}

# Arm-R FLOOR: saving >= 0.60 of the fleet composition fcalls (measured 0.667). Pinned; rationale in header.
g_armR_floor() {
  jq -e -n --slurpfile dd "$DEDUP" '
    ($dd[0]["rebuild-dedup"].singleHostEdit.savedFractionOfFleetComposition.nrFunctionCalls) >= 0.60
  ' >/dev/null
}

# Arm-C byte gates: composition-digest AND terminal-drvPath byte-identical under s2, per host, and the
# recorded baseline/s2 digests match g6-split. A class-share arm that moved either digest is a BUG.
g_armC_bytegate() {
  jq -e -n --slurpfile g6 "$G6" --slurpfile dd "$DEDUP" '
    ($g6[0]) as $g | ($dd[0]["class-share"].byteGate) as $bg
    | ($bg.compositionDigest.identical == true) and ($bg.toplevelDrvPath.identical == true)
      and ($g.hosts | keys | all(. as $h
        | $bg.compositionDigest.perHost[$h].baseline == $g.hosts[$h]["baseline-composition"].digest
          and $bg.compositionDigest.perHost[$h].s2 == $g.hosts[$h]["baseline-composition"].digest
          and $bg.toplevelDrvPath.perHost[$h].baseline == $g.hosts[$h]["baseline-toplevel"].digest
          and $bg.toplevelDrvPath.perHost[$h].s2 == $g.hosts[$h]["baseline-toplevel"].digest))
  ' >/dev/null
}

# Arm-C delta == s2 − pinned per counter (an OVERHEAD record — NO floor, never treated as a win; the
# gate only re-asserts the arithmetic, so a silently-flipped or hand-edited delta is caught).
g_armC_delta() {
  jq -e -n --slurpfile dd "$DEDUP" --argjson C "$DET_JSON" '
    ($dd[0]["class-share"].compositionWitness) as $cw
    | ($cw.perHost | keys | all(. as $h | $C | all(. as $c
        | $cw.perHost[$h].delta[$c] == ($cw.perHost[$h].s2[$c] - $cw.perHost[$h].pinned[$c]))))
      and ($C | all(. as $c | $cw.fleet.delta[$c] == ($cw.fleet.s2[$c] - $cw.fleet.pinned[$c])))
  ' >/dev/null
}

# Arm-C TERMINAL-pessimal: den@s2's machinery cost at the TERMINAL (toplevel) plane — also an OVERHEAD
# record, NO floor (the terminal is derivation-storm-dominated; s2's per-host overhead is paid in full,
# no sharing manifests). Re-assert the block's internal arithmetic (delta == s2 − pinned per host + fleet,
# the fleet == Σ per-host, the fcall fraction) AND the byte tie: each terminalDrvPath == the recorded s2
# terminal drvPath == the g6-split baseline-toplevel digest — the pessimal delta is measured on a
# byte-identical terminal, else it is a BUG not an overhead. EXPLICIT counter paths (never a .counters glob).
g_armC_terminal_pessimal() {
  jq -e -n --slurpfile g6 "$G6" --slurpfile dd "$DEDUP" --argjson C "$DET_JSON" '
    ($g6[0]) as $g | ($dd[0]["class-share"]) as $cs | ($cs.terminalPessimal) as $tp
    | ($tp.perHost | keys) as $hk
    | ($hk | all(. as $h | $C | all(. as $c
        | $tp.perHost[$h].delta[$c] == ($tp.perHost[$h].s2[$c] - $tp.perHost[$h].pinned[$c]))))
      and ($hk | all(. as $h
        | (($tp.perHost[$h].delta.nrFunctionCalls / $tp.perHost[$h].pinned.nrFunctionCalls)
           - $tp.perHost[$h].deltaFractionFcalls | fabs) < 1e-9))
      and ($C | all(. as $c
        | $tp.fleet.pinned[$c] == ([ $hk[] | $tp.perHost[.].pinned[$c] ] | add)
          and $tp.fleet.s2[$c] == ([ $hk[] | $tp.perHost[.].s2[$c] ] | add)
          and $tp.fleet.delta[$c] == ($tp.fleet.s2[$c] - $tp.fleet.pinned[$c])))
      and ($hk | all(. as $h
        | $tp.perHost[$h].terminalDrvPath == $cs.byteGate.toplevelDrvPath.perHost[$h].s2
          and $tp.perHost[$h].terminalDrvPath == $g.hosts[$h]["baseline-toplevel"].digest))
  ' >/dev/null
}

# Task-7b realization class-share: perAddedMemberSaving == reconstruct − inject; fractionOfReconstruct ==
# saving/reconstruct; the pattern's byte gate (injectedDigest == realDigest == the reconstruct digest);
# and the shared-core counts are sane. EXPLICIT paths — never realizationPlaneNativeShare.countersInformational.
g_csr_consistency() {
  jq -e -n --slurpfile csr "$CSR" --argjson C "$DET_JSON" '
    ($csr[0]) as $c | ($c.measurement) as $m
    | ($C | all(. as $k | $m.perAddedMemberSaving.counters[$k]
        == ($m.reconstruct.counters[$k] - $m.inject.counters[$k])))
      and ($C | all(. as $k
        | (($m.perAddedMemberSaving.counters[$k] / $m.reconstruct.counters[$k])
           - $m.perAddedMemberSaving.fractionOfReconstruct[$k] | fabs) < 1e-9))
      and ($c.byteGate.injectedDigest == $c.byteGate.realDigest)
      and ($c.byteGate.realDigest == $m.reconstruct.digest)
      and ($c.byteGate.injectedEqualsReal == true)
      and ($c.byteGate.coreCount == $c.class.sharedCore.byteIdenticalShared)
      and ($c.class.sharedCore.byteIdenticalShared <= $c.class.sharedCore.memberUnits)
  ' >/dev/null
}

# Task-7b FLOOR: realization saving >= 0.008 of reconstruct fcalls (measured ~0.0158). Pinned; header.
g_csr_floor() {
  jq -e -n --slurpfile csr "$CSR" '
    ($csr[0].measurement.perAddedMemberSaving.fractionOfReconstruct.nrFunctionCalls) >= 0.008
  ' >/dev/null
}

# The [consistency] gate roster — ONE "gate_fn|description" list. Both the normal sweep and the --selftest
# failure count iterate it, so adding a gate is a single entry (no two hand-synced lists). The gate fns are
# invoked indirectly by name here (SC2329 excluded for this app in ci/flake.nix — they ARE all invoked,
# just through this roster).
CONSISTENCY_GATES=(
  "g_pins|cross-file pin agreement (nix-config / den / nixpkgs)"
  "g_dualsite|dual-site rev pins (gen-rebuild + den-s2 present + well-formed; live cross-site is the lab's)"
  "g_armR_consistency|Arm-R saving = sum of skipped baseline-composition (byte-exact)"
  "g_armR_floor|Arm-R FLOOR: saving >= 0.60 of fleet composition fcalls"
  "g_armC_bytegate|Arm-C byte gates (composition digest + terminal drvPath)"
  "g_armC_delta|Arm-C delta = s2 - pinned (overhead record, no floor)"
  "g_armC_terminal_pessimal|Arm-C terminal-pessimal delta = s2 - pinned + drvPath byte tie (overhead record, no floor)"
  "g_csr_consistency|Task-7b saving arithmetic + byte gate (injected == real)"
  "g_csr_floor|Task-7b FLOOR: saving >= 0.008 of reconstruct fcalls"
)

# The normal [consistency] sweep: labelled PASS/FAIL to stdout, tally into the global FAILURES.
run_consistency() {
  set_baselines "$1"
  local entry fn desc rc
  for entry in "${CONSISTENCY_GATES[@]}"; do
    fn="${entry%%|*}"
    desc="${entry#*|}"
    "$fn" && rc=0 || rc=1
    report consistency "$desc" "$rc"
  done
}

# Silent [consistency] failure count against a (possibly corrupted) baseline set — used only by --selftest.
# A LOCAL counter (no global FAILURES, no subshell variable sharing), echoed to stdout.
count_consistency_failures() {
  set_baselines "$1"
  local entry fn n=0
  for entry in "${CONSISTENCY_GATES[@]}"; do
    fn="${entry%%|*}"
    "$fn" || n=$((n + 1))
  done
  printf '%s' "$n"
}

# corrupt_copy FILE JQ — a FRESH temp dir with the three baselines copied and made writable (the committed
# baselines are read-only 0444 store files when the app runs from /nix/store), then JQ applied to FILE in
# place. Echoes the dir. Each teeth case gets its OWN dir — no cross-teeth state, no re-copy over 0444, no
# set-e landmine.
corrupt_copy() {
  local file="$1" jqexpr="$2" d
  d="$(mktemp -d)"
  cp "$BL_SRC"/*.json "$d/"
  chmod -R u+w "$d"
  jq "$jqexpr" "$d/$file" >"$d/.corrupt" && mv "$d/.corrupt" "$d/$file"
  printf '%s' "$d"
}

# ── [teeth] — prove a corrupted counter AND a corrupted floor each FAIL the [consistency] sweep ──
g_selftest() {
  local d1 d2 failed_counter failed_floor
  # teeth #1: corrupt a deterministic COUNTER the Arm-R arithmetic depends on (blade composition fcalls).
  d1="$(corrupt_copy g6-split.json '.hosts.blade["baseline-composition"].counters.nrFunctionCalls += 1')"
  failed_counter="$(count_consistency_failures "$d1")"
  # teeth #2: corrupt the Arm-R FLOOR value below its pin (0.667 -> 0.10 < 0.60).
  d2="$(corrupt_copy dedup-savings.json '.["rebuild-dedup"].singleHostEdit.savedFractionOfFleetComposition.nrFunctionCalls = 0.10')"
  failed_floor="$(count_consistency_failures "$d2")"

  echo "  teeth #1 (corrupt a pinned counter): $failed_counter consistency gate(s) failed (expect >= 1)" >&2
  echo "  teeth #2 (corrupt a pinned floor):   $failed_floor consistency gate(s) failed (expect >= 1)" >&2
  [[ "$failed_counter" -ge 1 && "$failed_floor" -ge 1 ]]
}

# ── dispatch ──────────────────────────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "selftest" ]]; then
  echo "== [teeth] selftest — corrupting a copy of the baselines must FAIL the roster ==" >&2
  if g_selftest; then
    echo >&2
    echo "TEETH OK: both a corrupted counter and a corrupted floor failed the consistency sweep." >&2
    exit 0
  else
    echo >&2
    echo "TEETH BROKEN: a corrupted baseline did NOT fail the roster — the gates have no teeth." >&2
    exit 1
  fi
fi

echo "== [consistency] pure JSON arithmetic + pin agreement + floors (the A1 fleet numbers this hub cites) ==" >&2
echo >&2
run_consistency "$BL_SRC"

echo >&2
if [[ "$FAILURES" -eq 0 ]]; then
  echo "ALL GATES PASSED — the cited fleet numbers still agree with their own arithmetic (9/9 [consistency])."
  echo "(re-measurement of the fleet is the hola lab's documented procedure — ci/bench/baselines/README.md.)"
  exit 0
else
  echo "GATES FAILED: $FAILURES gate(s). See the FAIL lines above."
  exit 1
fi
