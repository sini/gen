# gen hub CI — validation + performance regression harness

Two permanent regression nets guard the pure-gen module system (gen-prelude → gen-types →
gen-merge → re-hosted gen-schema/gen-aspects) against the frozen nixpkgs reference stack
(original gen-schema/gen-aspects driven by pinned `github:nix-community/nixpkgs.lib`):

| Net | What it proves | Runs as |
|---|---|---|
| **Byte-parity oracles** | pure stack output == nixpkgs stack output, byte-for-byte (incl the `id_hash` SHA), over whole-stack fixtures + a real-den registry sample; mutation-teeth prove the oracle discriminates | `nix flake check ./ci` — `rehost-byte-parity`, `rehost-den-parity` |
| **Perf-regression bench** | pure stack stays FASTER and LIGHTER than the nixpkgs stack, and stays LINEAR in workload size | `nix run ./ci#perf-bench` |

Both sides are pinned reproducibly: the PURE side tracks the published re-host mains (a change
that breaks parity or performance fails CI); the REFERENCE side is frozen at the pre-re-host revs
plus a pinned `nixpkgs.lib`, so the bar never drifts.

## Validation — the parity oracles

`rehost-byte-parity.nix` — whole-stack fixtures (schema kinds + instances + id_hash; aspect trees
with class content/includes/guards; schema-declared options threaded into aspect instances)
evaluated through BOTH stacks via a shared provider `P`; the resolved projections are deep-compared.
`rehost-den-parity.nix` — den's actual registry config shape (collections, computed isEntity,
parent topology) through both gen-schema generations. Gate keys are listed in `flake.nix`; any
`false` fails the check derivation.

## Performance — the perf bench

`perf-bench.nix` holds the workload corpus (same provider-`P` trick, scaled to ~200× the oracle
fixtures); `perf-bench.sh` drives it through `nix-instantiate --eval` + `NIX_SHOW_STATS`, 2 stacks
× 3 reps per cell. Workloads are den shapes: `scalar` (wide flat option sets — the shape that
catches super-linear key handling), `registry`/`lazyRegistry` (attrsOf(submodule) instance
registries), `schemaHosts` (gen-schema kind + instances incl id_hash), `aspects` (gen-aspects
tree with flatten), `startup` (fixed cost, report-only).

Three gate families (thresholds at the top of `perf-bench.sh`):

- **parity** — every cell's sha256 projection digest must match across stacks. Ties the perf
  corpus to the validation bar: a "fast but wrong" change cannot pass.
- **ratio** (largest size per workload) — pure cpu ≤ 0.85× ref (median of 3, same-process ratio so
  host speed cancels); pure thunks/allocation ≤ 0.90× ref (deterministic evaluator counters).
  Measured headroom is wide (see baseline): a regression that erodes the speedup below ~15–35%
  margin fires the gate long before pure gets *slower* than nixpkgs.
- **linearity** (pure side, ×4 size step) — thunk/alloc growth ≤ 5.5× (linear ≈ 4.0×, quadratic
  ≥ 12×). This is the net that would have caught the 2026-07-04 O(k²) `unique` key-union bug
  (fixed in gen-merge `976a87a`): pre-fix, scalar allocation grew ~11.5× over a 4× step.

### Baseline (2026-07-04, Nix 2.34.7, gen-merge 976a87a)

| workload | n | ref cpu | pure cpu | cpu p/r | thunks p/r | alloc p/r |
|---|---:|---:|---:|---:|---:|---:|
| scalar | 8000 | 0.111s | 0.072s | 0.65 | 0.79 | 0.66 |
| registry | 2000 | 0.158s | 0.077s | 0.49 | 0.45 | 0.38 |
| lazyRegistry | 2000 | 0.167s | 0.076s | 0.46 | 0.46 | 0.38 |
| schemaHosts | 1600 | 0.226s | 0.127s | 0.56 | 0.57 | 0.49 |
| aspects | 1600 | 0.345s | 0.121s | 0.35 | 0.33 | 0.28 |

Linearity at baseline: 3.98–3.99× on every workload (exactly linear).

Full methodology, the pre-fix quadratic data, and the interpretation against the hola/zen priors:
`den-architecture/gen-specs/gen-merge/2026-07-04-module-system-benchmarks.md` (papers archive).

### Updating thresholds / workloads

Counters are deterministic per Nix version; cpu gates are ratios, so CI host speed does not
matter. If a legitimate engine change shifts a ratio past a gate, update the threshold in
`perf-bench.sh` **in the same PR**, citing the new baseline table from the run output — never
delete a workload to make a gate pass. New den shapes (wide freeform trees, deep submodule
nesting) should be added to `perf-bench.nix` as they become hot in den-hoag.
