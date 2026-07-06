# Fleet baselines — the cited A1 numbers, pinned in the trust surface

These three JSON files are the real-fleet measurements that
[`BENCHMARKS.md`](../../../BENCHMARKS.md) §"Fleet-scale results" and
[`VALIDATION.md`](../../../VALIDATION.md) §7 quote. They are **copied verbatim** from the hola
measurement lab — no number here is produced in this repo. [`../../fleet-consistency.sh`](../../fleet-consistency.sh)
re-asserts the pure-JSON arithmetic over them (`nix run ./ci#fleet-consistency`) so the cited
numbers cannot silently drift from their own arithmetic.

## Provenance

- **Source:** [`github:sini/hola`](https://github.com/sini/hola) `@4bab613`,
  `ci/bench/baselines/{g6-split,dedup-savings,class-share-realization}.json` — byte-identical
  copies (verify with `sha256sum`). hola is the **LAB**: it owns re-MEASUREMENT of the fleet.
- **The formal write-up:** the A1 fleet-measurement report
  (`~/Documents/papers/den-architecture/gen-specs/gen-class/2026-07-05-a1-fleet-measurement-report.md`)
  — the protocol, results, prior reconciliation, threats to validity, and the two-tier counter
  policy these files' framing refers to. hola's `ci/bench/MEASUREMENT.md` +
  `ci/bench/baselines/README.md` carry the full lab-side detail (measurement harness, arm
  definitions, the reproduce/refresh recipes).
- **Owner principle:** libraries (gen-class, gen-rebuild, …) stay UNBURDENED by fleet metrics —
  metrics live in metrics homes. hola is the lab; this hub is the **trust surface** (its ci is
  already all metrics, and it cites these numbers), so the drift tooth lives here.

## What each file pins

- **`g6-split.json`** — the composition-vs-terminal cost matrix for the fleet
  (bitstream/blade/cortex), per host and fleet-total. The two arms are two non-nested projections
  of the same eval: `baseline-composition` (a derivation-free walk of the merged option tree,
  digest = sha256 of the top-level option-name list) and `baseline-toplevel` (forces
  `system.build.toplevel.drvPath`, digest = that drvPath). Exact-pinned = the four deterministic
  evaluator counters + both digests, per host×arm; `gcTotalBytesInformational` is recorded, never
  gated.
- **`dedup-savings.json`** — the Task-7 dedup arms, both byte-gated. **Arm R** (`rebuild-dedup`,
  gen-rebuild): a localized single-host edit recomputes only that host's cone; the saving is Σ of
  the *skipped* hosts' `baseline-composition` counters (floor `>= 0.60` of fleet composition
  fcalls, measured 0.667). **Arm C** (`class-share`, den s2): the composition digest AND terminal
  drvPath stay byte-identical under s2 — a resolution-only optimization recorded as a `+4.6%`
  overhead (`compositionWitness`) and a terminal-plane overhead (`terminalPessimal`), never floored
  as a win.
- **`class-share-realization.json`** — the Task-7b realization-plane class-share: inject a class
  archetype's byte-identical shared `systemd.units` core into a member (fixed-input config-merge),
  paying only the member's delta. The 212-unit shared core injects byte-identically
  (`injectedDigest == realDigest`) and saves the per-added-member `reconstruct − inject` (floor
  `>= 0.008` of reconstruct fcalls, measured ~0.0158).

## Two-tier counter policy (framing)

Per the A1 report §3: the four deterministic evaluator counters (`nrFunctionCalls`,
`nrPrimOpCalls`, `nrOpUpdateValuesCopied`, `nrThunks`) plus both digests are exact-pinned;
`gcTotalBytes` and `cpuTime` are NEVER gated (Boehm/machine noise). Digests are exact on every
evaluator (they are determined by the pinned inputs, not the Nix build); the four counters are
exact same-evaluator-build and ride a ±0.1% relative band cross-build (a version *string* does not
identify an evaluator *build*). That band is a RE-MEASUREMENT concern — and re-measurement is the
lab's. `fleet-consistency.sh` here compares numbers WITHIN one committed baseline (same preamble),
so it stays exact on all four counters and never needs the band. Its exact gates read EXPLICIT
counter paths, never a `.counters` glob, so an informational key
(`gcTotalBytesInformational` / `realizationPlaneNativeShare.countersInformational`) can never leak
into a comparison.

## How to refresh

These files are a copy of the lab's output; refresh is **re-measure in the lab, then copy
verbatim** — the lab is the only place a stranger re-runs the arms.

1. Re-measure in hola. Follow hola's `ci/bench/baselines/README.md` refresh procedure (the
   full-fleet `nix run ./ci#fleet-stats` runs, the `class-share-realization.sh` driver, and the
   `jq` regenerators). Do NOT reproduce that recipe here — it needs the fleet, the pinned
   nix-config corpus, the den s1/s2 worktree branches, and a deep-eval stack limit; it is the
   lab's, and duplicating it would be a second source of truth.
1. Copy the regenerated JSONs verbatim into this directory (`cp` from hola; then `sha256sum` both
   sides to confirm byte-identity) and update the `@<rev>` in "Provenance" above to the hola rev
   they came from.
1. Re-run the trust-surface roster: `nix run ./ci#fleet-consistency` (all 9 gates PASS) and
   `nix run ./ci#fleet-consistency -- --selftest` (the teeth fire). If a legitimate lab re-measure
   shifts a baseline, re-pin these files and update the cited numbers in `BENCHMARKS.md` /
   `VALIDATION.md` in the SAME PR citing the new run — never lower a floor or delete a workload to
   make a gate pass (the update-in-PR policy in [`../../README.md`](../../README.md)).
