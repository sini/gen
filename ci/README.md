# gen hub CI — validation + performance regression harness

Two permanent regression nets guard the pure-gen module system (gen-prelude → gen-types →
gen-merge → re-hosted gen-schema/gen-aspects) against the frozen nixpkgs reference stack
(original gen-schema/gen-aspects driven by pinned `github:nix-community/nixpkgs.lib`):

| Net | What it proves | Runs as |
|---|---|---|
| **Byte-parity oracle** | pure stack output == nixpkgs stack output, byte-for-byte (incl the `id_hash` SHA), over a real-den registry sample; mutation-teeth prove the oracle discriminates | `nix flake check ./ci` — `rehost-den-parity` |
| **Perf-regression bench** | pure stack stays FASTER and LIGHTER than the nixpkgs stack, and stays LINEAR in workload size | `nix run ./ci#perf-bench` |

Both sides are pinned reproducibly: the PURE side tracks the published re-host mains (a change
that breaks parity or performance fails CI); the REFERENCE side is frozen at the pre-re-host rev
plus a pinned `nixpkgs.lib`, so the bar never drifts.

**Where a frozen reference is NOT sound, and what that costs.** Freezing the bar only works while
the SUBJECT's grammar is stable. The registry/schema surface above is; the **aspect** grammar is
not — it moves by design ruling, so a frozen aspect reference diverges from the subject
monotonically and a gate built on one reds on ruled improvements rather than on defects. Two
consequences are live here, and both are unassertions rather than fixes:

- The whole-stack aspect-grammar oracle `rehost-byte-parity` was **retired** (2026-08-13, ruling
  record `den-hoag-oyib`). Its claim is recorded unasserted in [VALIDATION.md](../VALIDATION.md) §1
  with an empty command cell; carrier `den-hoag-gkkh`.
- The perf bench's two `aspects` matrix rows are **pure-only**. They keep their linearity gates and
  absolute counters and are reported in their own table, but assert **no** pure/ref digest parity
  and **no** pure/ref CPU (0.85) or counter (0.90) win-gate. Whether that workload gets a ref-free
  performance gate, and of what shape, is an open question carried by `den-hoag-gkkh`; a re-frozen
  baseline is explicitly not the answer, since it reproduces the same defect at smaller scale.

## Validation — the parity oracle

`rehost-den-parity.nix` — den's actual registry config shape (collections, computed isEntity,
parent topology, instances with `id_hash`, den's two-level nested option shape) evaluated through
BOTH gen-schema generations via a shared provider `P`; the resolved projections are deep-compared.
Gate keys are listed in `flake.nix`; any `false` fails the check derivation.

## Performance — the perf bench

`perf-bench.nix` holds the workload corpus (same provider-`P` trick, scaled to ~200× the oracle
fixtures); `perf-bench.sh` drives it through `nix-instantiate --eval` + `NIX_SHOW_STATS`, 2 stacks
× 3 reps per cell. Workloads are den shapes: `scalar` (wide flat option sets — the shape that
catches super-linear key handling), `registry`/`lazyRegistry` (attrsOf(submodule) instance
registries), `schemaHosts` (gen-schema kind + instances incl id_hash), `aspects` (gen-aspects
tree with flatten), `deepSubmodule` (n replicated fixed-depth nested-submodule chains — the
per-level engine recursion no flat-instance workload exercises), `wideFreeform` (n unknown sibling
keys absorbed by a root `freeformType` — the freeform-absorption path, a nixpkgs thunk-parity band),
`startup` (fixed cost, report-only).

`classShare` is a separate workload with its own dedicated harness section (it is NOT in the
pure/ref matrix): its two "stacks" are `pure-full` / `pure-fixed` — both the pure engine — measuring
[gen-class](https://github.com/sini/gen-class)'s tier-2 `applyCoreFixed` against gen-merge's
fixed-input kernel. `pure-full` re-merges an n-instance shared `attrsOf(submodule)` registry per
member (the no-sharing baseline); `pure-fixed` builds that core once and reconstructs each member via
the sole-def core marker, so gen-merge SKIPS the discharge/fold/verify spine for the shared loc. Both
return the same projections byte-identically. See the design spec §2.5.

`overrideWarm` is likewise a separate workload with its own dedicated section: its two "stacks" are
`cold` / `warm` — both the pure engine — measuring gen-merge's warm re-eval (memoized override, README
§"Warm re-eval"). A class of 6 cheap 1-module overrides is applied over one registry-heavy base (a
marked-pure data module + a clean force layer + a dirty config-reading module — the den-hoag emit
shape). `cold` re-merges the shared registry from scratch per override (the no-reuse baseline); `warm`
evaluates the base once and reuses it via `warmFrom`/`editedModules`, so the registry loc — outside the
1-module edit's dirty footprint — splices byte-for-byte and only the edited `nodeId` and the dirty
`summary` re-merge. Both return the same projections byte-identically.

The public [`BENCHMARKS.md`](../BENCHMARKS.md) trust artifact embeds this bench's live output; regenerate it with `nix run ./ci#perf-bench -- --update BENCHMARKS.md`. It rewrites only the marker-delimited section and emits the tables already in mdformat's canonical compact form (`|---|---:|`), so treefmt leaves the block untouched — the script never invokes a formatter.

Three gate families (thresholds at the top of `perf-bench.sh`):

- **parity** — every cell's sha256 projection digest must match across stacks. Ties the perf
  corpus to the validation bar: a "fast but wrong" change cannot pass.
- **ratio** (largest size per workload) — pure cpu ≤ 0.85× ref (median of 3, same-process ratio so
  host speed cancels); pure thunks/allocation ≤ 0.90× ref (deterministic evaluator counters).
  Measured headroom is wide (see baseline): a regression that erodes the speedup below ~15–35%
  margin fires the gate long before pure gets *slower* than nixpkgs. `wideFreeform` is the one
  partial exception — only its ALLOC keeps the default win-gate; its THUNK ratio rides a band
  (`WIDEFREEFORM_RATIO_MAX = 1.3`) rather than the 0.90 win-gate, because freeform absorption is
  thunk-parity with nixpkgs (the same per-key type merges), and its CPU rides a band
  (`WIDEFREEFORM_CPU_MAX = 0.95`) rather than the 0.85 win-gate, because that cell is tiny (~0.07s) and
  load-sensitive so the default gate flakes on cpu noise. Its real teeth are the linearity net + the
  thunk band + the deterministic counters (see the baseline block below for the rationale).
- **linearity** (pure side, ×4 size step) — thunk/alloc growth ≤ 5.5× (linear ≈ 4.0×, quadratic
  ≥ 12×). This is the net that would have caught the 2026-07-04 O(k²) `unique` key-union bug
  (fixed in gen-merge `976a87a`): pre-fix, scalar allocation grew ~11.5× over a 4× step.

The `classShare` section adds its own two gates (own thresholds, not the pure/ref ones):

- **byte gate** — `pure-full` and `pure-fixed` must produce byte-identical projections at every size
  (the perf-scale twin of gen-class's `gateCore`): a fixed-input skip that changed the bytes cannot pass.
- **spine reduction** (`CLASSSHARE_RATIO_MAX = 0.30`) — `pure-fixed` thunks ≤ `pure-full` thunks × 0.30
  at each size, i.e. the fixed-input path must build ≤ 30% of the full re-merge's thunk graph. Plus its
  own thunk linearity check (both stacks ≤ `GROWTH_MAX` over the 4× step).

The `overrideWarm` section adds its own gates (own threshold, not the pure/ref ones):

- **byte gate** — `cold` and `warm` must produce byte-identical projections at every size (the
  perf-scale twin of gen-merge's warm-vs-cold byte oracle, and the standing tooth against a lying
  `pureModule` marker): a warm splice that changed the bytes cannot pass.
- **warm reuse** (`OVERRIDEWARM_RATIO_MAX = 0.30`) — `warm` thunks AND alloc ≤ `cold` × 0.30 at each
  size, i.e. the warm re-eval must build ≤ 30% of the cold from-scratch class's thunk graph / allocation
  (6 overrides amortising one base merge ≈ 1/6). Plus its own thunk linearity check (both stacks ≤
  `GROWTH_MAX` over the 4× step).

### Baseline (2026-07-05, Nix 2.34.7, gen-merge `fdbf140`, gen-class `218c54f`)

Whole matrix regenerated at a single gen-merge pin (every number from `nix run ./ci#perf-bench`;
counters are deterministic per Nix version, cpu is same-process ratio context). Ratio row = the
largest size per workload:

| workload | n | ref cpu | pure cpu | cpu p/r | thunks p/r | alloc p/r |
|---|---:|---:|---:|---:|---:|---:|
| scalar | 8000 | 0.105s | 0.073s | 0.695 | 0.882 | 0.708 |
| registry | 2000 | 0.166s | 0.084s | 0.507 | 0.524 | 0.423 |
| lazyRegistry | 2000 | 0.163s | 0.079s | 0.486 | 0.524 | 0.423 |
| schemaHosts | 1600 | 0.221s | 0.139s | 0.628 | 0.650 | 0.545 |
| aspects | 1600 | 0.350s | 0.133s | 0.380 | 0.386 | 0.310 |
| wideFreeform | 8000 | 0.086s | 0.070s | 0.812 | 1.099 | 0.821 |
| deepSubmodule | 1600 | 1.474s | 0.231s | 0.157 | 0.314 | 0.255 |

Linearity (pure side, ×4 size step) is 3.98–4.00× on every workload — exactly linear, the O(n²) net:
wideFreeform 3.988×/3.985×, deepSubmodule 3.998×/3.996×.

The `fdbf140` pin's pure-side counter ratios sit slightly above the pre-warm `018bafa` baseline (e.g.
scalar thunks 0.844 → 0.882, registry 0.493 → 0.524) — still comfortably inside every win-gate. The
shift isolates ~99.9% to the always-on lazy **provenance channel** landed in gen-merge `11b39d7` (which
forces declared-record defs to WHNF, an extra pure-side cost the nixpkgs ref does not pay); it is NOT
the warm-path `classifyModule`, which is allocated lazily and never forced on the cold path (a flat,
n-independent +40 thunks across the whole pin). `018bafa`'s numbers are the immediately-prior baseline
in git history.

**`deepSubmodule`** — `depth = 8` (fixed) per instance; `n` scales the chain count. Deep enough that
per-level fixpoint re-entry dominates an instance's cost, shallow enough to keep the eval-stack
recursion bounded so the bench runs under a plain `nix run` (no raised stack limit); the recursion
stays linear in the instance count.

**`wideFreeform`** — n unknown sibling keys absorbed by a root `freeformType` (`lazyAttrsOf str`)
alongside declared options, with mkDefault/mkForce/mkIf layers driving priority discharge through the
absorption path. Its **thunk** ratio sits in a parity band rather than below the 0.90 win-gate:
freeform absorption rides the SAME per-key type merges nixpkgs.lib performs (the engine's thunk win is
on DECLARED option paths), so thunk-parity is the honest contract on that counter (band-gated at
`WIDEFREEFORM_RATIO_MAX = 1.3`, deterministic 1.099 + ~18% headroom). Its **cpu** also rides a band
(`WIDEFREEFORM_CPU_MAX = 0.95`) rather than the 0.85 win-gate: absorption cpu IS genuinely sub-parity,
but this cell is tiny (~0.07s at n=8000) so the ratio is load-sensitive — measured spread **0.776–0.888**
across load conditions (quiet median ~0.80; an authoritative run under load hit 0.867), which flakes the
default 0.85 win-gate on cpu noise, not a regression. The `0.95` ceiling sits above the load tail as a
gross-regression cap. Only **alloc** keeps a default win-gate (deterministic 0.821). The band's real
teeth are LINEARITY, which catches the O(n²) freeform-absorption blowup this workload was built to
expose (pre-fix, n=8000 pure thunks were 468× ref; gen-merge `976a87a`→`018bafa` coalesces the per-key
unmatched defs per originating module, restoring linear absorption). Full pre-fix quadratic data:
`den-architecture/parked/wideFreeform-b4/NOTES.md`.

Full methodology, the pre-fix quadratic data, and the interpretation against the hola/zen priors:
`den-architecture/gen-specs/gen-merge/2026-07-04-module-system-benchmarks.md` (papers archive).

### classShare baseline (2026-07-05, Nix 2.34.7, gen-merge `fdbf140`, gen-class `218c54f`)

Fixed-input (`pure-fixed`) vs full re-merge (`pure-full`), 6-member class, ratios = fixed ÷ full:

| n | full thunks | fixed thunks | thunks f/f | alloc f/f | cpu f/f | byte gate |
|---|---:|---:|---:|---:|---:|---|
| 400 | 1,345,768 | 230,621 | 0.171 | 0.187 | 0.260 | ok |
| 1600 | 5,375,368 | 915,221 | 0.170 | 0.215 | 0.240 | ok |

Thunk linearity (400 → 1600, ×4 step): pure-full 3.99×, pure-fixed 3.97×.

**Threshold rationale (`CLASSSHARE_RATIO_MAX = 0.30`).** The gate is on `nrThunks` — the deterministic
count of the thunk graph the fixed-input kernel skips building (alloc and cpu are reported for context,
not gated: cpu is non-deterministic; alloc runs >4× growth by design — once the spine is skipped, the
fixed path's remaining allocation is dominated by the harness's own digest/serialization of the
projection (paid by both stacks for the byte gate), not per-member spine work; the thunk count is the
canonical spine indicator, cf. the
linearity net). Measured fixed/full thunk ratio ≈ 0.17 (a ~5.8× spine reduction, stable across both
sizes). The floor 0.30 = measured + ~75% relative headroom, and enforces ≥ 3.33× — comfortably past the
A1 **fixed-input reference of 2.48×** (ratio 0.403), the upper end of the 1.89×→2.48× spine-tax band
(design spec §2.5). So an erosion of the spine reduction below the A1 band fires the gate long before it
approaches "no reduction" — "any reduction" is explicitly not a pass. Per the update-in-PR policy below,
a legitimate engine change that shifts this ratio updates the constant in the same PR citing a fresh run;
the workload is never deleted to make it pass.

### overrideWarm baseline (2026-07-05, Nix 2.34.7, gen-merge `fdbf140`)

Warm re-eval (`warm`) vs cold from-scratch (`cold`), 6-override class, ratios = warm ÷ cold:

| n | cold thunks | warm thunks | thunks w/c | alloc w/c | cpu w/c | byte gate |
|---|---:|---:|---:|---:|---:|---|
| 400 | 1,368,412 | 232,030 | 0.170 | 0.174 | 0.298 | ok |
| 1600 | 5,464,012 | 916,630 | 0.168 | 0.172 | 0.213 | ok |

Thunk linearity (400 → 1600, ×4 step): cold 3.99×, warm 3.95×.

**Threshold rationale (`OVERRIDEWARM_RATIO_MAX = 0.30`).** The warm path pays the registry merge ONCE
(in the shared `prev`) instead of once per override, so a class of 6 overrides collapses to ≈ 1/6 of the
cold cost on the reused registry mass — measured warm/cold ≈ 0.17 on BOTH thunks and alloc (a ~5.9×
reduction, stable across sizes). Unlike classShare — where the digest serialization dominates alloc and
only thunks are gated — the whole warm stack allocates less, so both counters are gated (both are
deterministic per Nix version). The ceiling 0.30 = measured + ~75% relative headroom, enforcing ≥ 3.33×:
an erosion of the reuse (a footprint that wrongly pulls the registry into the re-merge, or a lost splice)
fires the gate well before warm stops beating cold. The two adversarial teeth are shared with gen-merge's
own warm suite — a lying `pureModule` marker on the data module would stale-splice and diverge at the
byte gate; a dirty module reading `config` is re-merged, never stale-reused. Per the update-in-PR policy
below, a legitimate engine change that shifts this ratio updates the constant in the same PR citing a
fresh run; the workload is never deleted to make it pass.

### Updating thresholds / workloads

Counters are deterministic per Nix version; cpu gates are ratios, so CI host speed does not
matter. If a legitimate engine change shifts a ratio past a gate, update the threshold in
`perf-bench.sh` **in the same PR**, citing the new baseline table from the run output — never
delete a workload to make a gate pass. New den shapes should be added to `perf-bench.nix` as they
become hot in den-hoag (deep submodule nesting landed as `deepSubmodule`, wide freeform trees as
`wideFreeform`).

## Fleet consistency — the trust-surface roster

`nix run ./ci#fleet-consistency` guards the **real-fleet numbers this repo cites** (`BENCHMARKS.md`
§"Fleet-scale results", `VALIDATION.md` §7). Those numbers are measured in the
[hola](https://github.com/sini/hola) lab against a real three-host fleet; their baselines are
committed here verbatim under [`bench/baselines/`](bench/baselines/) (provenance + refresh in that
dir's README). The roster is the nine-gate `[consistency]` partition ported from hola's
`fleet-gates.sh` — pin agreement across the three files, the arithmetic re-derivations (each saving
= the sum/difference it comes from), the byte-digest ties, and the two floors (Arm-R `>= 0.60`,
Task-7b `>= 0.008`) — so a cited number cannot silently drift from its own arithmetic.
`-- --selftest` corrupts a copy of a baseline (a counter, then a floor) and asserts the roster
fails, proving it has teeth. Gate names match the lab's roster (labels too, except the adapted
`g_dualsite`) so a reader can cross-reference the A1 report gate-for-gate.

What it deliberately does **not** do: it never re-measures the fleet (no `nix` eval, no
`NIX_SHOW_STATS`, no fleet build) — that is pure JSON arithmetic over the committed files, seconds,
corpus-independent. **Re-measurement is the hola lab's documented procedure.** This is the owner
principle: libraries (gen-class, gen-rebuild, …) stay unburdened by fleet metrics; metrics live in
metrics homes — hola is the lab, and this hub is the trust surface (its CI is already all metrics,
and it cites these numbers), so the drift tooth lives here. The two-tier counter policy (exact
same-build, ±0.1% relative cross-build; `gc`/`cpu` never gated) is a re-measurement concern and so
is the lab's; this roster compares within one committed baseline and stays exact. Same
update-in-PR policy as above: a legitimate lab re-measure that shifts a baseline is re-pinned here
with its cited numbers updated in the same PR — never lower a floor or delete a workload to pass.
