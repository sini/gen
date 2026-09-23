# gen hub CI — validation + performance regression harness

Two permanent regression nets guard the pure-gen module system (gen-prelude → gen-types →
gen-merge → re-hosted gen-schema/gen-aspects) against the frozen nixpkgs reference stack
(original gen-schema/gen-aspects driven by pinned `github:nix-community/nixpkgs.lib`):

| Net                       | What it proves                                                                                                                                                                                                                                                                                             | Runs as                                      |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| **Byte-parity oracle**    | pure stack output == nixpkgs stack output, byte-for-byte over the instance key sets and every non-identity field, on a real-den registry sample; mutation-teeth prove the oracle discriminates, and a teeth arm on the pure engine holds the `id_hash` that ADR-0016 put beyond the frozen witness's reach | `nix flake check ./ci` — `rehost-den-parity` |
| **Perf-regression bench** | pure stack stays FASTER and LIGHTER than the nixpkgs stack, and stays LINEAR in workload size                                                                                                                                                                                                              | `nix run ./ci#perf-bench`                    |

Both sides are pinned reproducibly: the PURE side tracks the published re-host mains (a change
that breaks parity or performance fails CI); the REFERENCE side is frozen at the pre-re-host rev
plus a pinned `nixpkgs.lib`, so the bar never drifts.

**Where a frozen reference is NOT sound, and what that costs.** Freezing the bar only works while
the SUBJECT's grammar is stable. The registry/schema surface above is; the **aspect** grammar is
not — it moves by design ruling, so a frozen aspect reference diverges from the subject
monotonically and a gate built on one reds on ruled improvements rather than on defects. Two
consequences are live here, and both are unassertions rather than fixes:

- The whole-stack aspect-grammar oracle `rehost-byte-parity` was **retired** by owner ruling on
  2026-08-13. Its claim is recorded unasserted in [VALIDATION.md](../VALIDATION.md) §1 with an empty
  command cell, and that section also carries the successor's terms under ADR-0025 item 2.
- The perf bench's two `aspects` matrix rows are **pure-only**. They keep their linearity gates and
  absolute counters and are reported in their own table, but assert **no** pure/ref digest parity
  and **no** pure/ref counter win-gate. Whether that workload gets a ref-free
  performance gate, and of what shape, is an **open question** — it rides with the rest of the
  successor's terms in [VALIDATION.md](../VALIDATION.md) §1; a re-frozen baseline is explicitly not
  the answer, since it reproduces the same defect at smaller scale.

## Validation — the parity oracle

`rehost-den-parity.nix` — den's actual registry config shape (collections, computed isEntity,
parent topology, instances with `id_hash`, den's two-level nested option shape) evaluated through
BOTH gen-schema generations via a shared provider `P`; the resolved projections are deep-compared
on every axis but identity — `id_hash` is minted and forced on both engines, and compared by
`teeth-mutation-pure` on the pure side rather than against the frozen witness (ADR-0016).
Gate keys are listed in `flake.nix`; any `false` fails the check derivation.

## Architecture — the direction-of-dependence lint

`direction-of-dependence.nix` — ADR-0015's enforcement half. No roster member may declare a root
flake input on a HIGHER stratum than its own, under the chain
`substrate < modules < aspects < framework`. The observable is the **declared input NAME**, never a
revision: the lock resolves names to revisions and the ADR forbids buying enforcement with pin
separation, so a pin bump that changes no declared name changes no result here. Like
`mkgenlibs-eval.nix` it governs the hub's **pinned** revisions — the surface consumers get.

The failure it guards is silent: a substrate library that acquires an aspects input just evaluates.
So the check carries its own arming in tree — seeded upward edges at two rank gaps, an inverted
rank, a seeded missing layer, a seeded off-roster input and three malformed exception sets — and a
seeded arm that STOPS firing is as red as an upward edge, because a guard that can no longer refuse
is not a passing guard.

One closed exception is ruled (2026-08-18), keyed by **edge** and not by member, and it is printed
entry by entry with its cause and its retirement carrier on every run, including runs where it
refuses nothing. Each entry must name both fields or it is refused, and the set's width is asserted
against the ruling in **both** directions — widening it is a new ruling, and narrowing it on a
landed retirement is the ruling admitting fewer than it did. Edges with a `retiring` endpoint carry
no layer, so they are unrankable: they are named and counted, and they do not take the run red.

## Performance — the perf bench

`perf-bench.nix` holds the workload corpus (same provider-`P` trick, scaled to ~200× the oracle
fixtures); `perf-bench.sh` drives it through `nix-instantiate --eval` + `NIX_SHOW_STATS`, 2 stacks
× 3 reps per cell. Workloads are den shapes: `scalar` (wide flat option sets — the shape that
catches super-linear key handling), `registry`/`lazyRegistry` (attrsOf(submodule) instance
registries), `schemaHosts` (gen-schema kind + instances; `id_hash` is minted and forced but kept out
of the digest — the ADR-0016 excluded axis), `aspects` (gen-aspects tree with flatten),
`deepSubmodule` (n replicated fixed-depth nested-submodule chains — the
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

The public [`BENCHMARKS.md`](../BENCHMARKS.md) trust artifact embeds this bench's live output; regenerate it with `nix run ./ci#perf-bench -- --update BENCHMARKS.md`. It rewrites only the marker-delimited section, splicing the tables in compact form (`|---|---:|`); the script never invokes a formatter itself, so the block reaches its committed padded form the same way every other table in the tree does — on the repo's format-before-commit pass through treefmt's mdformat (gfm-armed since `6e5c1d0`). Run the formatter after an `--update` and the spliced block is canonical; skip it and the block is the one part of the file out of the tree's own format.

Three gate families (thresholds at the top of `perf-bench.sh`):

- **parity** — every cell's sha256 projection digest must match across stacks. Ties the perf
  corpus to the validation bar: a "fast but wrong" change cannot pass.
- **ratio** (largest size per workload) — pure thunks/allocation ≤ **that row's own derived bound**
  (deterministic evaluator counters). Each bound is its measured anchor plus a margin smaller than
  the cheaper of the two constructions the one-engine consolidation introduced on that row and
  counter; the derivation sits beside each constant in `perf-bench.sh` (`ROW_THUNKS_MAX` /
  `ROW_ALLOC_MAX`) and the record is the 2026-09-21 baseline block below. `COUNTER_RATIO_MAX = 0.90`
  survives only as the default for a workload nobody has derived yet, which is the "new den shapes"
  path; no matrix row reads it. Headroom is deliberately NARROW — that is the point of the
  derivation: a bound sitting well above its anchor absorbs a pure-side regression silently, and
  four of the twelve bounds sit exactly AT their anchor, so any move of 0.001 is reported.
  `wideFreeform` keeps its own named constant for THUNKS because its claim is different — a parity
  band (`WIDEFREEFORM_RATIO_MAX`) rather than a win-gate, since freeform absorption rides the same
  per-key type merges nixpkgs.lib performs. Its real teeth are the linearity net, the thunk band,
  and the deterministic counters (see the baseline block below for the rationale).
- **linearity** (pure side, ×4 size step) — thunk/alloc growth ≤ 5.5× (linear ≈ 4.0×, quadratic
  ≥ 12×). This is the net that would have caught the 2026-07-04 O(k²) `unique` key-union bug
  (fixed in gen-merge `976a87a`): pre-fix, scalar allocation grew ~11.5× over a 4× step.

**cpu is measured, reported, and gated by nothing.** Each of the three families above reads a
quantity that is a function of the evaluated expression alone; `cpuTime` is a function of the
expression *and* the machine's state, so putting it through the same threshold comparison types a
non-deterministic quantity as deterministic — a defect no constant and no rep count repairs. It was
measured here, not assumed: this workstation evaluates one tree at two stable frequency regimes
~2.2× apart (auto-cpufreq scaling 800 MHz–2.2 GHz) — a raw whole-cell ratio rather than a
net-of-floor one, the distinction mattering because the startup floor is itself bimodal, so
subtracting it removes a term that shrank along with the mode — and the pure/ref cpu ratio moved
0.734–1.873 across runs of byte-identical trees while every counter stayed byte-identical. The
fabrication runs in both directions: a false red *and* a false green, the second being the dangerous
one. That noise exceeded the detection margin of five of the six cells the old cpu gate covered, so
the gate could not distinguish a regression from a frequency transition; the only cpu-gate firing in
this repo's record was itself a false positive, while the one real regression the bench has caught
was caught by a thunk counter. Report-only cpu was already this harness's convention for
`classShare` and `overrideWarm`, and it is already the *stated* rule of this repo's other
measurement instruments: `ci/bench/baselines/README.md` and `ci/fleet-consistency.sh` both say in
terms that `gcTotalBytes` and `cpuTime` are NEVER gated, and the three baseline JSONs record
`cpuTime` as informational or omit it. perf-bench was the outlier; this brings it into line. To keep
the reported figures as honest as an ungated figure can be, a row's arms are sampled
**round-robin** — one rep of each arm in turn — rather than as separate blocks, so the two arms of a
ratio see the same machine.

What this leaves unguarded, stated: a regression that costs real time without costing counters —
work moving into C++ builtins — since counters are a lower bound by construction. That class is not
this bench's to catch. A change that *claims* a wall-clock win is accepted under the interleaved,
NULL-parity P1–P5 protocol (den-architecture, canreach-split spec §W), which is where wall-clock
evidence is admissible. The split is deliberate: perf-bench does counter-based regression
*detection*; §W does per-remedy wall-clock *acceptance*.

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

### Baseline (2026-09-21, Nix 2.34.8, gen-merge `7516886`) — the live anchor

The one-engine consolidation (ADR-0008 §1, gen-merge `564ad1c`) moved every pure/ref row, and three
assertions crossed the shared `COUNTER_RATIO_MAX = 0.90`. This block is the derivation record for
the re-baseline that replaced that one constant with a bound per row and per counter
(`den-hoag-perfbench-564ad1c-jvkvp`, owner ruling of 2026-09-21). **The 2026-07-05 `fdbf140` block
below is retained, not overwritten**: the anchors are a dated walk, and a walk is what makes
cumulative drift — N landings each inside its margin — readable rather than arguable.

The anchor rev is the one this hub PINS (`flake.lock`, root and `ci/`). gen-merge `main` is one
relock commit ahead at `275953b`; that commit moves lock files only and its `lib/modules.nix` blob
is byte-identical, so the two revs are the same anchor for this instrument.

Whole matrix at one pin, both sizes (`nix run ./ci#perf-bench`; counters are deterministic per Nix
version, the cpu columns are ungated context valid only for the host and the moment that produced
them):

| workload      |    n | ref cpu | pure cpu | thunks p/r | alloc p/r |
| ------------- | ---: | ------: | -------: | ---------: | --------: |
| startup       |    1 |  0.009s |   0.119s |      0.971 |     1.563 |
| scalar        | 2000 |  0.027s |   0.133s |      0.912 |     0.761 |
| scalar        | 8000 |  0.091s |   0.181s |  **0.912** | **0.756** |
| registry      |  500 |  0.049s |   0.146s |      0.777 |     0.633 |
| registry      | 2000 |  0.166s |   0.240s |  **0.776** | **0.631** |
| lazyRegistry  | 2000 |  0.163s |   0.233s |  **0.777** | **0.632** |
| schemaHosts   |  400 |  0.067s |   0.184s |      1.170 |     0.995 |
| schemaHosts   | 1600 |  0.219s |   0.363s |  **1.171** | **0.995** |
| wideFreeform  | 2000 |  0.028s |   0.135s |      1.095 |     0.810 |
| wideFreeform  | 8000 |  0.087s |   0.182s |  **1.096** | **0.806** |
| deepSubmodule |  400 |  0.198s |   0.225s |      0.576 |     0.463 |
| deepSubmodule | 1600 |  1.555s |   0.533s |  **0.575** | **0.463** |

Linearity is 3.95–4.00× on every workload and both counters (gate ≤ 5.5), parity `ok` on every cell, and the
`classShare` / `overrideWarm` sections are unmoved (0.170–0.171 and 0.238–0.241 against their 0.30
ceilings). Bold = the gated size, i.e. the twelve assertions the bounds below govern.

**The bounds, and where each one comes from.** ANCHOR is the measured ratio at this pin, read at
the precision the gate compares at — `ratio()` prints `%.3f` before `lte()`, so a bound of `1.210`
admits a printed `1.210` and refuses `1.211`. ① is `declarationGuard` and ② is `driveKnot`, each
re-measured **on this row** by neutralising it in a throwaway gen-merge tree at this pin and
re-running the cell; the figure is that construction's share of the row's ratio. MARGIN is half the
smaller of the two, truncated down to three places.

| row           |    n | counter | anchor |        ① |        ② | margin |     bound |   was |
| ------------- | ---: | ------- | -----: | -------: | -------: | -----: | --------: | ----: |
| scalar        | 8000 | thunks  |  0.902 | 0.037994 | 0.000174 |  0.000 | **0.902** | 0.912 |
| scalar        | 8000 | alloc   |  0.754 | 0.054458 | 0.000083 |  0.000 | **0.754** | 0.756 |
| registry      | 2000 | thunks  |  0.776 | 0.108340 | 0.064314 |  0.032 | **0.808** |  0.90 |
| registry      | 2000 | alloc   |  0.631 | 0.101395 | 0.046820 |  0.023 | **0.654** |  0.90 |
| lazyRegistry  | 2000 | thunks  |  0.777 | 0.108440 | 0.064373 |  0.032 | **0.809** |  0.90 |
| lazyRegistry  | 2000 | alloc   |  0.632 | 0.101548 | 0.046891 |  0.023 | **0.655** |  0.90 |
| schemaHosts   | 1600 | thunks  |  1.207 | 0.197886 | 0.079462 |  0.000 | **1.207** | 1.210 |
| schemaHosts   | 1600 | alloc   |  1.018 | 0.187996 | 0.057494 |  0.000 | **1.018** | 1.023 |
| deepSubmodule | 1600 | thunks  |  0.575 | 0.105358 | 0.087229 |  0.043 | **0.618** |  0.90 |
| deepSubmodule | 1600 | alloc   |  0.463 | 0.090347 | 0.065271 |  0.032 | **0.495** |  0.90 |
| wideFreeform  | 8000 | thunks  |  1.096 | 0.000158 | 0.000215 |  0.000 | **1.096** |   1.3 |
| wideFreeform  | 8000 | alloc   |  0.806 | 0.000154 | 0.000090 |  0.000 | **0.806** |  0.90 |

**The four `scalar` / `schemaHosts` rows are RATCHETED** (the lock-currency relock onto gen-merge
`d84ba687`): each bound is the figure read at that pin, at margin 0.000, and WAS is the bound it
replaces. `scalar` moves down from the pre-channel figure 0.912 / 0.756 to 0.902 / 0.754, and
`schemaHosts` from its 1.210 / 1.023 band to 1.207 / 1.018. A bound moving down is a tightening and
needs no licence (below). ① and ② on those rows are the 7516886 measurements and are not re-derived;
the other eight rows are unchanged.

★ **Three of the twelve bounds are INTERIM, and this states what ends them.** `scalar` thunks
**0.902**, `schemaHosts` thunks **1.207** and `schemaHosts` alloc **1.018** are the three that
loosened; they encode an **accepted, carried regression**, and they are the ceiling this project has
agreed not to exceed **while the `564ad1c` cost stands** — not a target it is aiming at. The prior
anchors are preserved in the 2026-07-05 `fdbf140` block below, retained rather than overwritten, for
exactly this purpose. **The marking ends when those three gated counters return toward the `fdbf140`
anchors and these three bounds are tightened back**; `den-hoag-restore-perf-promises-xzchx` owes that
restoration and `den-hoag-fvphc` §4 Q1 carries the unrepaired cost itself. The other nine bounds
TIGHTEN and are not interim. **This is a separate debt from the stale publication**: `BENCHMARKS.md`'s
2026-07-04 composition-plane table is also wrong, for reasons this isolation does not account for, and
restoring the perf promises would not repair it.

**What every bound still catches, as one claim:** a regression costing half of the cheaper of the
two constructions this engine change is calibrated on, on that row and that counter. Half rather
than all of it is not decoration — it is what keeps the gate's own RED state testable, and the
acceptance cell that shipped with this landing seeds a cost strictly between the margin and ②'s
delta on `schemaHosts` and reads the refusal. There is no noise term in any of this: the gated
counters are byte-identical across reps and across arms on this instrument, so a margin buys one
thing only — how much unattributed drift the project absorbs before it hears about it.

**Four of the twelve margins are 0.000**, because ② is ~free on that row: `driveKnot` costs 147
thunks on `scalar` n=8000 (0.0002 of ratio) and neither construction touches `wideFreeform`, which
rides the per-key type merges rather than the declaration spine. A 0.000 margin is admissible on a
deterministic counter and it is the tightest honest reading — the row holds AT its anchor and any
move of 0.001 is reported.

**Nine of the twelve TIGHTEN, three loosen, and the three are the attributed ones.** What the old
shared 0.90 was absorbing in silence, measured live at this pin rather than from the committed
table: `deepSubmodule` +57%, `registry` +16%, `lazyRegistry` +16%, `wideFreeform` thunks +19%
against its 1.3 band — and `scalar` and `schemaHosts` had no absorption left at all, which is why
they are the rows that reddened. That silent capacity is the defect this re-baseline removes.

★ **Scope, stated because the headline is one-sided: every ratio gate in `perf-bench.sh` is an
UPPER bound, and this re-baseline is a tightening on UPWARD moves only.** Nothing in this file
refuses a candidate whose gated counters go DOWN — and a candidate that deletes a ruled property
the perf corpus never evaluates gets *cheaper*, so it reads greener here, not redder. Raising
`schemaHosts`' bound to 1.210 means such a candidate now also clears this gate, where the 0.90
bound refused it by accident. **The thing that refuses it is the member's own property suite, which
is why the run below is a precondition rather than a citation** (item 5 under "Updating thresholds
/ workloads").

**Why the loosening was licensed — the five items, in full.**

1. **Isolation.** The move is attributed to gen-merge `564ad1c` by a two-arm measurement carrying a
   complement arm: the arm holding the other eight members at tip reads byte-identical to the
   all-green anchor. *(Carrier row `den-hoag-perfbench-564ad1c-jvkvp`, isolation block.)*

2. **A named construction.** `declarationGuard` and `driveKnot`, both bound in
   `gen-merge:lib/modules.nix` and both re-measured per row above — not "the release".

3. **A cited ruled property.** `declarationGuard` buys **ADR-0033**'s refusal-by-name;
   `driveKnot` buys **ADR-0006**'s one evaluator.

4. **Measured irreducibility.** The two are 97.6% of the gate's entire headroom — deleting *both*
   clears the binding gate by only 2.40%. Two independent passes refuted the one property-preserving
   optimisation proposed for ①, so verified property-preserving headroom is **zero**.

5. **The member's property runs, by rev — BOTH suites, because they reach different axes.**
   gen-merge at `7516886`, exits read unpiped:
   `nix-unit --flake ./ci#tests` ⇒ **482/482, rc 0**; `nix-unit --flake ./ci#testsError` ⇒
   **89/89, rc 0**. Driven RED in the same run by the archetypal property-deleting patch (force the
   declaration stratum's `declEntries` spine only): `./ci#tests` ⇒ 481/482, rc 1, ☢️ on
   `one-evaluator.test-the-declaration-stratum-admits-value-reads-and-refuses-declaration-reads`,
   and `./ci#testsError` ⇒ 88/89, rc 1, ❌ on
   `one-evaluator.test-a-config-dependent-option-key-set-refuses-at-the-fold`.

   ★ **The two suites are not redundant, and running only the first is a test on one axis.**
   `./ci#tests` reaches **containment**: a refusal that escapes `tryEval` takes the evaluation down,
   so the cell aborts and nix-unit reports ☢️ — an escape is not invisible there, it is maximally
   visible, which is exactly how the red arm above fires. It does **not** reach refusal **TYPE**,
   and it does not carry the input that breaks: measured at this pin, `ci/tests/one-evaluator.nix`
   has `expectedError` ⇒ **0 LINES** (live control `expr` ⇒ 6 LINES) and `misdeclare` ⇒ **0 LINES**
   (live control `mkOption` ⇒ 16 LINES), while `ci/tests-error.nix` has `expectedError` ⇒ **65
   LINES** and `misdeclare` ⇒ **6 LINES** (control ⇒ 46 LINES). ⇒ **a candidate not run against
   `./ci#testsError` has not been tested on the TYPE axis at all.** gen-merge's own CI says the
   same in its own words: `.github/workflows/ci.yml` carries a dedicated
   `nix develop --command nix-unit --flake .#testsError` step because *"`nix flake check` covers
   the `tests` output ONLY … the error-assertion cells live on `testsError`, so without this step
   they never run here."*

**The 2026-08-13 sitting declined this same arm**, with the reason *"it records the regression as
the new normal"* (`den-hoag-gtma`, `den-hoag-erls`). The 2026-09-21 ruling supersedes it, and what
answers the older reason is items 4 and 5 together: the cost is irreducible at zero verified
property-preserving headroom, and the property it buys is asserted by a run cited by rev rather
than by this file's own say-so. A bound that could not produce all five does not move and the
change does not land.

### Baseline (2026-07-05, Nix 2.34.7, gen-merge `fdbf140`, gen-class `218c54f`)

Whole matrix regenerated at a single gen-merge pin (every number from `nix run ./ci#perf-bench`;
counters are deterministic per Nix version; the cpu columns are ungated context, valid only for the
host and the moment that produced them). Ratio row = the
largest size per workload:

| workload      |    n | ref cpu | pure cpu | cpu p/r | thunks p/r | alloc p/r |
| ------------- | ---: | ------: | -------: | ------: | ---------: | --------: |
| scalar        | 8000 |  0.105s |   0.073s |   0.695 |      0.882 |     0.708 |
| registry      | 2000 |  0.166s |   0.084s |   0.507 |      0.524 |     0.423 |
| lazyRegistry  | 2000 |  0.163s |   0.079s |   0.486 |      0.524 |     0.423 |
| schemaHosts   | 1600 |  0.221s |   0.139s |   0.628 |      0.650 |     0.545 |
| aspects       | 1600 |  0.350s |   0.133s |   0.380 |      0.386 |     0.310 |
| wideFreeform  | 8000 |  0.086s |   0.070s |   0.812 |      1.099 |     0.821 |
| deepSubmodule | 1600 |  1.474s |   0.231s |   0.157 |      0.314 |     0.255 |

Linearity (pure side, ×4 size step) is 3.98–4.00× on every workload — exactly linear, the O(n²) net:
wideFreeform 3.988×/3.985×, deepSubmodule 3.998×/3.996×.

**`schemaHosts` changed SHAPE on 2026-09-18 and its gated counters did not move** (`den-hoag-b5qrc`).
The cell used to seed its registry from `eval.config.schema.host` — a read out of the fixpoint the
same `P.eval` pass was still building, the crossing the gen-schema relocation retires — and now
freezes the kind in a prior pass (`hostSchema` / `frozenHost`), symmetrically on both stacks. Because
a counter cell's acceptance is its counters and not only its parity digest, the delta was measured
rather than assumed, both runs on one machine minutes apart, the tree otherwise untouched:

|                             |        thunks p/r |         alloc p/r | thunk linearity | alloc linearity |
| --------------------------- | ----------------: | ----------------: | --------------: | --------------: |
| n=400, one-pass → two-pass  |     0.890 → 0.889 |     0.747 → 0.746 |               — |               — |
| n=1600, one-pass → two-pass | 0.891 → **0.891** | 0.747 → **0.747** |   3.990 → 3.989 |   3.987 → 3.986 |

Parity `ok` at both sizes in both runs, `ALL GATES PASSED` in both, and every other workload's gated
counters are byte-identical across the pair (only the ungated cpu columns moved). **No threshold in
`perf-bench.sh` moves**, which is the whole of the re-baseline this shape change owed under
"Updating thresholds / workloads" below. Note that the ratio row above is the LIVE reading at
gen-merge `3aa6dacc`, not this block's `fdbf140` figures (0.650 / 0.545): the table is dated and
pinned, and the gap between the two is engine drift since 2026-07-05, not this change.

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
absorption path. Its **thunk** ratio sits in a parity band rather than below a win-gate:
freeform absorption rides the SAME per-key type merges nixpkgs.lib performs (the engine's thunk win is
on DECLARED option paths), so thunk-parity is the honest contract on that counter (band-gated at
`WIDEFREEFORM_RATIO_MAX`, re-derived 2026-09-21 to the anchor itself — deterministic 1.096, margin
0.000, because both constructions of the one-engine consolidation are ~free on this shape; the former
1.3 was 1.099 + ~18% headroom and was absorbing a +19% pure-side move in silence). Its **cpu** used to ride a band
of its own (`0.95`, against the 0.85 win-gate) on the ground that the cell is tiny (~0.07s at n=8000)
and therefore load-sensitive. That band is retired with the rest of the cpu gating, and its
justification is worth recording as a lesson rather than a threshold: the spread it was fitted to
(**0.776–0.888**) was produced by the blocked A-then-B protocol this harness no longer runs, and a
figure a blocked protocol produced on a bimodal host is not evidence about its subject. Widening the
band had already been tried on exactly this cell and it still flaked — the last shipped measurement
put it at 0.914 against the 0.95 ceiling, 3.9% of headroom on an instrument whose noise floor is a
~2.2× raw regime step. Only **alloc** keeps a default win-gate (deterministic 0.821). The band's real
teeth are LINEARITY, which catches the O(n²) freeform-absorption blowup this workload was built to
expose (pre-fix, n=8000 pure thunks were 468× ref; gen-merge `976a87a`→`018bafa` coalesces the per-key
unmatched defs per originating module, restoring linear absorption). The full pre-fix quadratic
series was recorded outside this repository and nothing here reproduces it; what IS reproducible is
the gate that replaced it — the linearity arm, re-run with `nix run ./ci#perf-bench`, whose growth
ceiling is what now catches the blowup.

The full methodology, the pre-fix quadratic data and the interpretation against the hola/zen priors
were written up outside this repository. What this repository carries is the reproducible half, and
it is enough to re-derive every gate above: the workload definitions (`ci/perf-bench.nix`), the
driver and its thresholds (`ci/flake.nix`'s `perf-bench` app and `ci/perf-bench.sh`), the rationale
for each gate (this file), and the committed baselines under `ci/bench/baselines/`.

### classShare baseline (2026-07-05, Nix 2.34.7, gen-merge `fdbf140`, gen-class `218c54f`)

Fixed-input (`pure-fixed`) vs full re-merge (`pure-full`), 6-member class, ratios = fixed ÷ full:

| n    | full thunks | fixed thunks | thunks f/f | alloc f/f | cpu f/f | byte gate |
| ---- | ----------: | -----------: | ---------: | --------: | ------: | --------- |
| 400  |   1,345,768 |      230,621 |      0.171 |     0.187 |   0.260 | ok        |
| 1600 |   5,375,368 |      915,221 |      0.170 |     0.215 |   0.240 | ok        |

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

| n    | cold thunks | warm thunks | thunks w/c | alloc w/c | cpu w/c | byte gate |
| ---- | ----------: | ----------: | ---------: | --------: | ------: | --------- |
| 400  |   1,368,412 |     232,030 |      0.170 |     0.174 |   0.298 | ok        |
| 1600 |   5,464,012 |     916,630 |      0.168 |     0.172 |   0.213 | ok        |

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

Counters are deterministic per Nix version; the gates are ratios, so CI host speed does not
matter. If a legitimate engine change shifts a ratio past a gate, update that row's bound in
`perf-bench.sh` **in the same PR**, citing the new baseline table from the run output — never
delete a workload to make a gate pass. New den shapes should be added to `perf-bench.nix` as they
become hot in den-hoag (deep submodule nesting landed as `deepSubmodule`, wide freeform trees as
`wideFreeform`); a new workload starts on the default `COUNTER_RATIO_MAX` and earns a derived bound
of its own the first time someone measures what its cost is made of.

**"Legitimate" is the load-bearing word, and it is defined here** (2026-09-21,
`den-hoag-perfbench-564ad1c-jvkvp`). A ratio bound may be **loosened** only against **all five**:

1. **Isolation** — the move is attributed to a commit or a member by a two-arm measurement carrying
   a **complement arm**, never by elimination over an incomplete population.
2. **A named construction** — the cost points at a binding in the source, cited by name, not at
   "the release".
3. **A cited ruled property** — that construction buys something an ADR rules, by number.
4. **Measured irreducibility** — a partial optimisation cannot reach the standing bound, with the
   shortfall stated as a figure.
5. **The member's property runs, cited by rev — BOTH of its suites, named with the axis each
   reaches.** Run at the rev this hub pins, quoted with their unpiped exits, and shown RED in the
   same run on a patch that deletes the property. **`#tests` reaches CONTAINMENT** — an uncontained
   refusal takes the evaluation down, so the cell aborts and is reported. **Only `#testsError`
   reaches refusal TYPE**, because only that file carries `expectedError` and the misdeclared input
   that provokes one (measured per row in the 2026-09-21 block above, with live controls). ⇒ **one
   command is a test on one axis**; a candidate run against `#tests` alone has not been tested on
   the other. This item exists at all because **nothing in `perf-bench` can stand in for either**:
   the bench gates a digest of SUCCESSFUL evaluations plus deterministic counters, so a patch that
   deletes a refusal on inputs the corpus never evaluates moves neither — it moves the counters
   *down*, and every gate here is an upper bound. Items 1–4 are reports about a cost; **item 5 is
   the only one of the five that can refuse.** The oracle is a person today, and deliberately: a
   landing in THIS repository runs neither of the member's suites and neither of its hooks, so the
   deferred mechanisation of the cross-repository conjunction leaves **two** unmechanised arms, not
   one.

**The rule is one-sided on purpose.** It licenses a bound to move UP; a bound moving DOWN is a
tightening and needs no licence. Note what that does and does not cover: it governs the BOUND, not
the CANDIDATE, and a candidate whose gated counters fall is not refused by anything in this file.

Where the five cannot be produced, **the bound does not move and the change does not land**
*(defaulted, reversible)*. Where they can, the loosening takes the recommendation and is banked for
the owner's weekly sitting: the gate detects automatically and a person decides — ADR-0032's arming
shape, transposed. What this section practises is that ADR's **ruling 5** — *the number is derived
at implementation from the measured cost curve, recorded with its derivation, and re-derived when
the engine changes*. Its rulings 2 and 4 do **not** transfer: their subject is what the engine may
refuse a USER's program, while this gate refuses a commit in this repository, so the gate keeps
REFUSING rather than warning. A warning would not have stopped the consolidation publishing
silently, which is the behaviour that worked.

**What triggers a re-derivation is a gated counter moving against the recorded anchor** — which the
harness already computes and prints on every run — not a relock. A relock is a candidate, not a
trigger: on this instrument the complement arm showed eight members contributing literally zero
thunks. The worked example of all of it, with its figures, is the 2026-09-21 baseline block above;
the 2026-09-18 `schemaHosts` shape change is the worked NULL case, where no threshold moved.

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
