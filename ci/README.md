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

`compose-parity.nix` — the successor compose as published (`gen.lib.compose`) evaluated warm and
cold over one fixture must agree byte-for-byte on `values` AND `provenance`, at the root lock's
gen-merge and gen-memo, whose revisions the report records. Beside the two arms it carries the
comparator's own controls (the cycle cut fires, functions are nulled, each half moves under its own
seed, the function-valued blind class reads green), the admission key's refusing half, the
engineArgs collision guard per owned key, and the cycle-walk cells. One cell cannot be a gate: its
green is a stack overflow that `tryEval` does not catch, so the `checks` job reads
`lib.composeParity.overflowPin` in a separate step and requires the eval to fail on it.

`pins-compose.nix` — one check per roster member, `pins-compose-<member>`: that member's own ci
`tests` plane, at the revision the hub pins, with every roster-named input its ci declares bound to
the hub's pin of that member. Each member's CI evaluates its suite against its own ci lock; this is
the evaluation that sees the pinned set together, so a pinned revision that breaks a sibling reds
here even while the sibling's own CI is green. Non-roster inputs, and roster repositories pinned by
revision under another name as fixtures, stay at the member's own lock. A failing cell fails the
check at evaluation time, so `--keep-going` names every failing member in one run.
`pins-compose-error-<member>` is the same member's error plane at the same pins, and a green marker
for a member that declares none: its ci lock's roster-named root edges are grafted onto the hub's root lock
through gen-harness's `lib.checks.errorPlane`, and its cells run in the build sandbox under the
column's own evaluator, so a pinned revision that changes a message a sibling's cell asserts reds
here when the check is built.

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
registries), `threadedRegistry` (the same registry over nixpkgs `attrsWith` with a non-default
`placeholder`, a container outside the six gen-merge re-homes, so the pure stack folds through
gen-merge's threaded rebuild channel; its arming plant must fire on the pure arm only),
`wrappedRegistry` (the same registry under nixpkgs `coercedTo` over the stack's own `attrsOf`, a
container that adds no step, so the pure stack keys it at the option's root as the root is; a
gen-merge without that arm cannot evaluate the row), `steppedRegistry` (the registry one step down: the
instances in groups of 16 under a consumer's stepped `defineType` container, each group the stack's own
`attrsOf`, which gen-merge keys as a container node; a gen-merge without that construction cannot
evaluate the row), `schemaHosts` (gen-schema kind + instances; `id_hash` is minted and forced but kept out
of the digest — the ADR-0016 excluded axis), `inheritHosts` (the same shape with a host kind inheriting
two parents by name, on both gen-schema entry arms: the desugared parents ride every instance's module
list, so an `inherits` change is priced per instance; pure-only, since the frozen reference predates
`inherits`), `aspects` (gen-aspects tree with flatten),
`deepSubmodule` (n replicated fixed-depth nested-submodule chains — the
per-level engine recursion no flat-instance workload exercises), `wideFreeform` (n unknown sibling
keys absorbed by a root `freeformType` — the freeform-absorption path, a nixpkgs thunk-parity band),
`foreignMount` (n option roots on one stock nixpkgs `submodule`, each mounted by gen-merge's
foreign-mount path, against nixpkgs `evalModules` over the same modules — den-hoag-gijly OQ2; before
it no row reached the mount), `moduleFanIn` (n modules each declaring 17 keys, defining one and freeform-adding five at one level — the
module-count axis), `sameLocFanIn` (n modules declaring one typed option — the per-loc declaration
fold's length), `startup` (fixed cost; gated as the `startup,t|a` load rows).

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

`kindMatch` is the third dedicated workload, and the owner's landing gate on den-hoag-l0y ruling (a):
a kind is keyed by its MINTED identity, and any regression is a defect. Two kinds share one name
(`host`) but are two declarations (gen-schema's `kindEq` says so); n/2 instances sit in each registry
behind one gen-select registry-adapter context whose per-id `kindFor` returns each node's shared kind
value. Its numerator is `kind` (`sel.kind A`, the live gen-select); its denominator is `attrs-ref`,
the same context matched with `sel.attrs` through a FROZEN gen-select (`gen-select-orig`, rev-pinned
at `9285b5b` in `ci/flake.nix`, which no relock moves). The denominator is frozen because a
denominator running the code under test dilutes every cost both stacks pay in it: with the live
`sel.attrs` there, +3 thunks/node in the shared matcher passed at the bounds. The row runs two
fixtures, `migrated` (the kind's sealed map is empty) and `sealed` (`attrs-ref-sealed` /
`kind-sealed`: `addr` typed by nixpkgs `lib.types.str`, so a matching node reaches the
sealed-collision helper's non-empty arm, as den's unmigrated kinds do). A third stack, `kind-plant`,
re-derives each node's kind per call so every node forces a fresh digest: the per-node recompute the
owner's cost answer was conditional on not happening. It selects the same nodes, so only a counter
can see it, and the harness runs it as the row's arming control on every run rather than as a gated
arm.

`entityMatch` is the fourth, the row that FORCES an instance's `id_hash` (den-hoag-l0y U2).
gen-schema's stamp carries the kind's minted identity beside the key values, so two same-name
kinds that are different declarations mint different identities; `kindMatch` cannot meter that
stamp, because the registry adapter tests its presence and never forces its value. The fixture is
kindMatch's two same-name kinds, with registries A and B holding the SAME instance names (`h0`..)
at the SAME key values, so only the kind can separate the halves. Its numerator is `entity`
(`sel.entity kA hostsA.h0` through the live gen-select over live gen-schema instances, forcing all n
stamps). Its denominator, `attrs-ref`, runs NO library under test: the frozen gen-schema
(`gen-schema-orig`) on the pinned nixpkgs `lib.evalModules`, matched with `sel.attrs` through the
frozen gen-select. A denominator running the live gen-schema lowers a ratio above 1 whenever both
stacks pay a cost, so the one-sided gate would read a regression as an improvement: measured, the
identity module built per instance (+6 thunks/node) passed that way. `entity-plant` evaluates each
node's instance under a kind re-derived for that node — the per-instance recompute — and is the
row's arming control on every run. A second fixture (den-hoag-l0y (β); kindMatch's precedent),
stacks `attrs-ref-sealed` / `entity-sealed`, types `addr` by nixpkgs `lib.types.str`, so both kinds
carry a sealed component and the one matching node reaches `sel.entity`'s sealed arm (the node's kind
key, then `kindEq`); a cost confined to that arm is invisible on the migrated fixture.

`resolution` meters the one resolution calculus (den-hoag-gayc U2b, design §5.8) on the hub's own
peer shape: a complete peer relation with self-edges over n hosts, walked `peer*` from `h0`, at
n ∈ {4, 5, 6, 7, 100, 1000}. Its numerator is `resolve` (the live gen-scope `resolve`, mode
`reachable`, over the relation lifted to an evaluated scope); its denominator is `query-orig`, gen-graph
FROZEN at `0db4e737` (`gen-graph-orig` in `ci/flake.nix`, the last revision before resolution moved
into gen-scope), applied with the gen-prelude its own lock pins (`gen-prelude-orig`), so the denominator
is frozen in full; its `query { mode = "all"; }` must reach the same nodes in the same order (the byte
gate). Thunks are gated per n, exactly; allocation is reported only (its old reason, the collector's
run-to-run jitter, is gone since every cell runs with the collector off, but no alloc gate is built
on this row). A third stack, `witnesses`,
enumerates every simple path (NR-Cons) and is factorial in n: it runs at n ≤ 7 only, as the row's
arming control on every run, and must step 6 → 7 by at least ×3 and by more than `resolve` does, or
the instrument is broken and the row has no result.

The public [`BENCHMARKS.md`](../BENCHMARKS.md) trust artifact embeds this bench's live output; regenerate it with `nix run ./ci#perf-bench -- --update BENCHMARKS.md`. It rewrites only the marker-delimited section, splicing the tables in compact form (`|---|---:|`); the script never invokes a formatter itself, so the block reaches its committed padded form the same way every other table in the tree does — on the repo's format-before-commit pass through treefmt's mdformat (gfm-armed since `6e5c1d0`). Run the formatter after an `--update` and the spliced block is canonical; skip it and the block is the one part of the file out of the tree's own format.

Four gate families (bounds at the top of `perf-bench.sh`):

- **parity** — every cell's sha256 projection digest must match across stacks. Ties the perf
  corpus to the validation bar: a "fast but wrong" change cannot pass.
- **cost** (every cost row, den-hoag-r8y89) — a row gates its MARGINAL, the counter at its big size
  minus the counter at its small size (owner ruling (b), 2026-10-06), so a per-process constant
  cancels out of it. It is EXACT and TWO-SIDED against `MARG_MAX`, the reading at the anchor identity
  (`ANCHOR_*` at the top of `perf-bench.sh`). A row whose denominator is INDEPENDENT of gen (nixpkgs
  `ref`, or a rev-pinned frozen original: the matrix rows, `wideFreeform`, `foreignMount`,
  `entityMatch`, `resolution`) gates the ratio of marginals as `NUM/DEN`, compared by
  cross-multiplication; a row whose only control is gen itself (`classShare`, `overrideWarm`,
  `kindMatch`, `coordMatch`) gates the guarded arm's OWN marginal, because a shared-plane improvement
  moved a gen ÷ gen denominator and the ratio refused the optimization (c3: coordMatch 1.000 → 1.001
  with the excess a constant +398). Alloc is the evaluator-ATTRIBUTED bytes of the same stats file
  (`envs + list + sets + values + symbols`), not `gc.totalBytes`, whose 4,096 B block steps transfer
  1:1 into a difference (owner ruling OQ7, β + U0: the unattributed remainder, strings among it, is
  not gated); each of the five fields must be present and non-zero, or the cell refuses by name. There
  is no margin and no tolerance (owner ruling P1 (i), 2026-10-05): above the bound is a regression,
  below it is `ratchet:` (exit 8) until the bound is lowered in the same change. `wideFreeform`'s
  thunk marginal is a parity band rather than a win-gate, since freeform absorption rides the same
  per-key type merges nixpkgs.lib performs; its real teeth are the linearity net and the
  deterministic counters.
- **load** (den-hoag-r8y89) — the per-process constant the marginals cancel, gated apart, so it cannot
  creep in unseen. Three readings, each through the same exact gate (a rise is a regression, a fall a
  ratchet): **member** — one `load` cell per member (`perf-bench.nix` `loadOrder`) forces the top-level
  set of every member up to it, each attribute to weak head normal form, and a member's load is its
  cell minus its predecessor's, thunks and attributed bytes: n-independent and exact, so a binding
  added to any member reds that member's row whatever the landing does to a row's curvature (one
  unused binding planted at a member's top level reds exactly that member's row; a row reads the load its
  own top-level values FORCE, including calls into its predecessors' functions, so a change to a
  predecessor's function body reads on its callers' rows); **row** — each gated arm's
  small-size thunk counter, judged while the arm's own thunk marginal equals its anchored `LOADM`
  (then the counter's change is the constant's change, exactly), or on its three-size intercept
  against `LOADI` when the marginal moved and the arm is affine; otherwise `confounded`, printed and
  not judged. The row reads what a member cell cannot: work a workload's first call does once, and a
  constant number of merges. **startup** — the startup cell, absolute. A moved marginal prints its
  row's `re-arm:` assignments, so adopting it leaves the row judgeable. The `### load` table and the
  `LOAD DELTA` line print every reading. A member landing states its OWN load delta, which the anchor
  cannot show when it lags an earlier unrelocked win (gate C2): `ci/perf-bench-load-diff.py` of two
  runs at `PERF_LOAD_MID=1`, `--at <member>=rev:<parent>` and `--at <member>=rev:<landing>`; any
  `ROSE:` row without an owner reading is a defect in the landing.
- **linearity** (pure side, ×4 size step) — thunk/alloc growth ≤ 5.5× (linear ≈ 4.0×, quadratic
  ≥ 12×). A complexity-class threshold, not a cost, so it does not ratchet: removing a constant term
  moves a linear row's growth UP toward 4.0 (c3 moved registry alloc growth 3.960 → 3.961). This is the net that would have caught the 2026-07-04 O(k²) `unique` key-union bug
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

★ **Four dedicated rows are RE-BASED** (den-hoag-r8y89): `classShare`, `overrideWarm`, `kindMatch` and
`coordMatch` divide gen by gen over a shared plane (the reach census: each denominator forces live
members), so they gate the guarded arm's OWN marginal and load — `pure-fixed` thunks, `warm` thunks and
alloc, `kind` and `coord` thunks and alloc — exactly and two-sidedly. The ratio and per-size bullets
below describe the gates the marginal form replaced (their bounds, with every derivation, are at hub
`94e07ff`): those ratios are printed and gated by nothing. The byte and projection gates and linearity
are unchanged; the two arming controls compare their plant's MARGINAL against the row's marginal bound
(`kind-plant` and `entity-plant` run at both sizes).

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

The `kindMatch` section adds its own gates, per fixture:

- **byte gate** — `kind` and `attrs-ref` must select the same nodes at every size. A name key that
  conflates the two same-name kinds selects all n and reds here.
- **ratio**, thunks AND alloc — `kind`/`attrs-ref` ≤ `KINDMATCH_THUNKS_MAX[fixture,n]` /
  `KINDMATCH_ALLOC_MAX[fixture,n]` at both sizes, each the measured anchor with margin 0.000 (migrated
  0.973 / 0.991 at n=400 and 0.962 / 0.976 at n=1600; sealed 0.967 / 0.984 and 0.957 / 0.969; Nix
  2.34.8, gen-select `2cd8c5d`, frozen gen-select `9285b5b`, gen-schema `a90bc54`; the two n=400
  thunk bounds re-anchored at gen-identity `410261b`, whose per-mint refusal attribution costs the
  two kinds' mints +275 thunks, a constant; den-hoag-xvww). The thunk
  headroom under each is the distance to the next printed step — 63 / 211 migrated, 159 / 1,373
  sealed — so a per-node cost the live gen-select adds to a `sel.kind` match reds it above ~0.16
  thunk/node (migrated), including cost in the matcher every selector shares, as does a rise of more
  than ~30 thunks in either kind's mint price. The anchor is not the pre-landing cost: stock
  gen-select `9285b5b` as the numerator costs 14.5 thunks/node plus ≈5.4k less and fails the byte
  gate; the bound holds that price. The row cannot see per-node cost in the instance data plane
  (gen-merge, gen-schema), which both stacks pay through the live members and which the ratio
  therefore dilutes rather than cancels — the pure/ref rows gate that plane — nor a cheaper kind
  path.
- **arming** — the `kind-plant` stack at n=400 must breach the migrated thunk bound (measured 5.122
  against 0.972) while selecting the same nodes. Plus thunk linearity on every stack, which is kept
  for the quadratic class: the planted recompute is linear (3.99× over the 4× step), so linearity
  alone never sees it.

The `entityMatch` section adds its own:

- **projection** — `entity` selects exactly `[ "a:h0" ]` and `attrs-ref` both halves
  (`[ "a:h0" "b:h0" ]`); both digests are pinned. A stamp keyed by the kind name selects both halves
  and reds here, which is what stock gen-schema `cfec60d` does.
- **ratio**, thunks AND alloc, per fixture — `entity`/`attrs-ref` ≤
  `ENTITYMATCH_THUNKS_MAX[fixture,n]` / `ENTITYMATCH_ALLOC_MAX[fixture,n]`, the measured anchor with
  margin 0.000 (migrated 1.311 / 1.125 at n=400, 1.307 / 1.116 at n=1600; sealed 1.317 / 1.129 and
  1.312 / 1.120; Nix 2.34.8, gen-identity `410261b`, gen-merge `aea02d1`, gen-schema `c4125d5`,
  gen-select `410f517`, frozen gen-schema `2b7c2d3`, frozen gen-select `9285b5b`). The re-anchor holds
  gen-identity's per-mint price (+16 thunks per instance for the stamp's three-label mint, plus a
  constant; den-hoag-xvww); gen-merge `aea02d1` adds the last printed step of the migrated alloc
  pair. The migrated thunk headroom is 31 / 1,144, so a +1-thunk-per-mint regression in gen-identity
  reds it, as does the identity module built per instance (+6 thunks/node; 1.304 / 1.300 through
  `--at gen-schema=path:`, exit 6, measured at U2's anchor). The sealed thunk headroom is 10 / 629, so
  a gen-select that reads every node's kind before the stamp decides (+6 thunks/node) reds it (1.310 /
  1.304 through `--at gen-select=path:`), with both projections and the migrated ratios unchanged. The price the anchor holds: +24.0 thunks per instance for the
  stamp's kind component, plus the mark once per kind (≈3.3k on this row's one-option kind, and more
  on a larger declaration, since every option attribute is a component of the mark).
- **arming** — `entity-plant` at n=400 must breach the thunk bound (measured 6.905 against 1.300)
  while selecting the same node. Plus thunk linearity on every stack.

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
| scalar        | 8000 | thunks  |  0.883 | 0.037994 | 0.000174 |      — | **0.900** | 0.902 |
| scalar        | 8000 | alloc   |  0.754 | 0.054458 | 0.000083 |  0.000 | **0.754** | 0.756 |
| registry      | 2000 | thunks  |  0.776 | 0.108340 | 0.064314 |  0.032 | **0.808** |  0.90 |
| registry      | 2000 | alloc   |  0.631 | 0.101395 | 0.046820 |  0.023 | **0.654** |  0.90 |
| lazyRegistry  | 2000 | thunks  |  0.777 | 0.108440 | 0.064373 |  0.032 | **0.809** |  0.90 |
| lazyRegistry  | 2000 | alloc   |  0.632 | 0.101548 | 0.046891 |  0.023 | **0.655** |  0.90 |
| schemaHosts   | 1600 | thunks  |  1.157 | 0.197886 | 0.079462 |  0.000 | **1.157** | 1.146 |
| schemaHosts   | 1600 | alloc   |  0.992 | 0.187996 | 0.057494 |  0.000 | **0.992** | 0.982 |
| deepSubmodule | 1600 | thunks  |  0.583 | 0.105358 |  retired |  0.000 | **0.583** | 0.643 |
| deepSubmodule | 1600 | alloc   |  0.536 | 0.090347 |  retired |  0.000 | **0.536** | 0.595 |
| wideFreeform  | 8000 | thunks  |  1.097 | 0.000158 | 0.000215 |  0.000 | **1.097** | 1.096 |
| wideFreeform  | 8000 | alloc   |  0.806 | 0.000154 | 0.000090 |  0.000 | **0.806** |  0.90 |

**The four `scalar` / `schemaHosts` rows are RATCHETED** (the lock-currency relock onto gen-merge
`d84ba687`): each bound is the figure read at that pin, at margin 0.000, and WAS is the bound it
replaces. `scalar` moves down from the pre-channel figure 0.912 / 0.756 to 0.902 / 0.754, and
`schemaHosts` from its 1.210 / 1.023 band to 1.207 / 1.018. A bound moving down is a tightening and
needs no licence (below). ① and ② on those rows are the 7516886 measurements and are not re-derived;
the other eight rows are unchanged.

★ **`deepSubmodule` is RE-DERIVED for the Unit 2 engine and RATCHETED** (den-hoag-n6dh7; owner
ruling 2026-09-28, ADR-0032 ruling 5). Unit 2 makes every nested tree an `nta` child of one
`scope.eval`, so ② (a `scope.eval` per nested tree) is no longer paid on this row and the margin is
0.000; ① is the 7516886 measurement, not re-derived. The anchor is read at gen-merge `0c49041`
(arm (B), L5c, den-hoag-9d80v and den-hoag-1n12c, on the relock-38 mains). The loosening's licence is the reader-API spike
(`den-ag-design/reports/den-hoag-n6dh7-reader-api-spike-v0.md`: no lever reaches 0.618 / 0.495) and
the owner's reading. **The ratchet is mechanical** (since den-hoag-r8y89 every cost row is a ratchet row and `ROW_RATCHET`
is gone)**:** `ROW_RATCHET` made a reading BELOW the bound
refuse as `ratchet:` until the bound is lowered to it in the same change, so the bound follows every
reduction down and never moves up without a fresh owner reading. The gen-merge nesting-side rebuild
(den-hoag-i4c0n, gen-merge `0010eb7` + `fa73591`: one discharge per nesting option, no freeform group without a
declared freeform type) moved it from 0.643 / 0.595 to **0.583 / 0.536**, the thunk half back under
the pre-Unit-2 0.618.

★ **`scalar` thunks is RESTORED to the original 0.90.** gen-merge `63ae058` forces the declaration
spine with a path-free walk instead of materialising every leaf path, and the row reads **0.883** at
gen-merge `d37deb6`; the bound returns to the promise rather than to anchor plus margin, so its
margin column is empty.

★ **`schemaHosts` is RE-ANCHORED at gen-identity `410261b`** (den-hoag-xvww): the row reads
1.132 / 0.969 at the pre-relock pins and **1.146 / 0.982** at the relock that carries it. gen-identity
alone reads 1.146 / 0.981: its mint names the kind and label in every refusal at +4 thunks per
encoder instance, labels + 1 instances per mint, and nothing per value node; gen-merge `aea02d1`
adds +24,112 B on the pure arm, the last printed alloc step. The bound moves to the landed figure at
margin 0.000, a tightening. A +1-thunk-per-mint plant in gen-identity does not red this row (1.146 /
0.982); it reds four `entityMatch` gates, which are the per-mint guard.

★ **`schemaHosts`, `entityMatch` (all eight) and three `kindMatch` n=1600 gates are RE-ANCHORED at
the den-hoag-bfc0k / den-hoag-5xio7 relock** (gen-merge `50250c1`, gen-schema `4b4244a`,
gen-aspects `25c6f86`), margin 0.000, under owner sitting item R8's default (a correctness fix's
stated price; defaulted, reversible). Bisected by root-lock arm on hub `cb6953a`, host and
Determinate agreeing: gen-merge `e332998`/`0943b2a` alone (5xio7's `callD` operand swap and
`slotsDiffer`) reds the four `entityMatch` alloc gates by +0.001 each, so the 5xio7 spec's "nil"
price for that swap is false; adding gen-schema `fa26749` (`constructionRelation`, the relation every
per-construction schema type now states) takes `schemaHosts` to 1.155 / 0.990, `kindMatch` migrated
n=1600 thunks to 0.963 and `entityMatch` thunks up about +0.012; the full landing reads
`schemaHosts` 1.157 / 0.991 locally and 1.157 / 0.992 on the CI runner (the bound takes 0.992), `kindMatch` migrated n=1600 0.963 / 0.977 and sealed n=1600 thunks
0.958, `entityMatch` migrated 1.326 / 1.137 (n=400) and 1.321 / 1.128 (n=1600), sealed 1.331 / 1.142
and 1.326 / 1.133. Every other bound is unchanged. ① and ② in the table are not re-derived.

★ **The two INTERIM bounds are retired (2026-09-27).** `schemaHosts` thunks and alloc (**1.207** /
**1.018** when marked, **1.163** / **0.992** at the last interim reading) were what remained of the three
that loosened; `scalar` thunks returned to **0.90** at `ab05306`. They encoded an accepted, carried
regression, a ceiling rather than a target, and `den-hoag-restore-perf-promises-xzchx` owed their
restoration. gen-schema `ffdf8ec` holds `_identity` as one `lazyAttrsOf (listOf str)` leaf closed to
`keys` by its `apply`, where it had been a submodule evaluating a nested module per instance, with its
own `declarationGuard` walk and `driveKnot`, to hold one list. The row reads **0.892** / **0.789** (Nix
2.34.8), and both bounds are the **0.90** promise again. ADR-0033 and ADR-0006 hold: a module-shaped
`_identity` definition refuses by name at the leaf's domain, and no evaluator is added. The prior anchors
stay in the 2026-07-05 `fdbf140` block below. `den-hoag-fvphc` §4 Q1 carries the engine's own `564ad1c`
cost, which this does not touch. **This is a separate debt from the stale publication**:
`BENCHMARKS.md`'s 2026-07-04 composition-plane table is also wrong, for reasons this isolation does not
account for, and restoring the perf promises did not repair it.

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

★ **Scope, stated because the headline is one-sided** (as of 2026-09-21; since den-hoag-r8y89 every
cost gate is two-sided, so a candidate whose counters go DOWN is refused as `ratchet:` until its bound
falls with it — what the paragraph says about property suites still holds)**: every ratio gate in
`perf-bench.sh` is an UPPER bound, and this re-baseline is a tightening on UPWARD moves only.** Nothing in this file
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

**`moduleFanIn`** — n modules, each declaring one option plus 16 `wide` options nobody defines,
defining the first under `mkIf`, adding one key to a shared `attrsOf` and five undeclared keys; one more
module redeclares every `o<i>` option, declares the bag and sets `freeformType`. It is the only row whose level holds n MODULES, so it is the one that sees a per-key
lookup answered by a scan of the module list (O(n²); den-hoag-hk4ed): every other row's levels hold a
few modules. The `wide` options make the declaration fold's accumulator grow by 17 keys per module, so a fold
that copies it per module (a binary `foldl'` over `mergeOptionDecls`, a `//` accumulation) pays bytes
quadratic in the product: reverting that fold alone reads 10.4× alloc per ×4 step against the 5.5×
bound, where one declared key per module read 4.3× and passed. Gated on parity and linearity only: its
claim is order, not a constant against nixpkgs (pure/ref reads about 0.94 thunks and 0.94 alloc at
n=1600).

**`sameLocFanIn`** — n modules each declaring ONE option loc `p` with a type, and one module defining
it. `moduleFanIn` declares each loc twice, so it never reaches the length of the per-loc declaration
fold; this row does: a typed redeclaration step that answers "am I the last typed declaration" by
scanning the loc's sites is O(n) per step, so the loc costs O(n²) (den-hoag-bem8u; reverting that alone
reads 12.3× thunks / 13.0× alloc per ×4 step against the 5.5× bound). Gated on linearity only, not on
the pure/ref ratio and not on parity of a constant: pure/ref reads about 2.0 thunks and 2.3 alloc at
n=1600, and that constant against nixpkgs comes from the checked pair merge each declaration pays, not
from the per-loc fold, so a ratio gate would red it for a cause this row does not measure.

**`wideFreeform`** — n unknown sibling keys absorbed by a root `freeformType` (`lazyAttrsOf str`)
alongside declared options, with mkDefault/mkForce/mkIf layers driving priority discharge through the
absorption path. Its **thunk** ratio sits in a parity band rather than below a win-gate:
freeform absorption rides the SAME per-key type merges nixpkgs.lib performs (the engine's thunk win is
on DECLARED option paths), so thunk-parity is the honest contract on that counter (band-gated at
`WIDEFREEFORM_RATIO_MAX`, re-derived 2026-09-21 to the anchor itself — deterministic 1.096, margin
0.000, because both constructions of the one-engine consolidation are ~free on this shape; re-anchored
at 1.097 by the owner's ruling of 2026-09-28 as the price of gen-scope's argument grammar, a constant
+182 pure thunks per evaluation with linearity and alloc unchanged, which the owner confirmed on
2026-09-30 is a one-time construction cost per gen-scope library instance (207 thunks once per process
at the measured pair, 0 per crossing, identical on all three evaluators); the former
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

Counters are deterministic per evaluator identity — `nrThunks` always, the attributed bytes and
`gc.totalBytes` because every cell runs with the collector off and every source sits at a `<hash>-source` store path of one length
(`perf-bench.sh` header, with the measurements) — so CI host speed does not matter. Across hosts,
`gc.totalBytes` also needs the host's nix-path kept out: the evaluator stores it on the heap at
startup, and both its value and the channel it arrives by move later allocations: the CI runner's
Determinate `extra-nix-path` entry against a workstation's
`nixpkgs=flake:nixpkgs` moved 4 alloc gates by up to 4,096 B with every thunk equal. Every evaluation
runs through `nixi`, which passes `--option nix-path ''` (`NIX_PIN`) and so overrides nix.conf and
`NIX_PATH` alike, and the identity block refuses by name (exit 4, `HOST NIX-PATH REACHES THE EVALUATOR`) a run in which `builtins.nixPath` is not `[]`: a lost `NIX_PIN` definition reds by name.
An evaluation that calls `nix-instantiate` directly, bypassing `nixi`, is not caught and reds as an
unnamed alloc drift. Pinned, CI and a workstation read the same byte on every cell. Every cost gate
is EXACT and TWO-SIDED, so every run ends in one of four states, each with its own exit code:

- **0** — every cost reading EQUALS its bound.
- **1** (6 for a `--at` candidate) — a regression: some reading is above its bound, or a parity,
  linearity or arming gate failed. Raising a bound needs the five items below AND an owner reading
  (owner ruling P1 (i), 2026-10-05: no per-row tolerance; the coordMatch +398 "constant overhead" is
  the existing baseline, and any NEW growth, constant or not, fails).
- **8** — RATCHET OWED: no regression, and at least one reading fell BELOW its bound, or a moved
  marginal re-arms its load row. Each `ratchet:` line names the assignment that lowers it, and each
  `re-arm:` line the `LOADM` / `LOADI` / `LOAD_MAX` assignment that keeps the row judgeable;
  `python3 ci/perf-bench-bounds.py <report>` applies exactly those lines. **The change that ADOPTS the improvement
  carries the lowering** — for a member optimization that is the hub commit that moves the member's
  pin (a relock commit), never a later, unrelated landing; `relock-all` reads 8 as "stop at the hub
  and lower", not as a red of its dependents (den-hoag-2ffmc).
- **7 / 9** — the evaluator, its allocator or a reference pin differs from `ANCHOR_*`, so NO cost
  gate is judged (owner ruling P5 (i): the environment moved, not gen). At 7 the members are
  `ANCHOR_MEMBERS` and the printed readings are recorded as the new bounds together with the new
  identity — the one licensed raise of a bound without an owner reading
  (`ci/perf-bench-bounds.py <report>` writes the bounds; the identity lines are written by hand). At 9 the members moved
  too, so recording would launder a member move into the baseline: re-run with `--at K=rev:<rev>`
  at `ANCHOR_MEMBERS` first, record, and let the member move be gated against the new anchor.

Every change that writes a bound (a lowering, an owner-read raise, a re-anchor) writes
`ANCHOR_MEMBERS` to the members it read at. **An edit to `perf-bench.nix` is an instrument change**:
every cell's counters can move with it (adding one workload binding added one thunk to every cell),
so its landing re-reads every bound and says so: plant `ANCHOR_EVALUATOR`, run, and record with
`ci/perf-bench-bounds.py --instrument <report>`, which writes `ANCHOR_MEMBERS` to the members it read
at. Never
delete a workload to make a gate pass. New den shapes should be added to `perf-bench.nix` as they
become hot in den-hoag (deep submodule nesting landed as `deepSubmodule`, wide freeform trees as
`wideFreeform`, the foreign mount as `foreignMount`); a row with no recorded bound is refused as
UNMEASURED, so a new workload's landing records its reading as its bound.

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

**The licence is one-sided on purpose.** It licenses a bound to move UP; a bound moving DOWN is a
tightening and needs no licence. The GATE is two-sided: a candidate whose gated counters fall is
refused as `ratchet:` until the bound falls with it, on every cost row, so a hard-won optimization is
preserved by the bound it lowered (owner sitting den-hoag-rwuqw, ruling 10 arm A). What a lowered
bound cannot preserve, stated: on a re-based row (`classShare`, `overrideWarm`, `kindMatch`,
`coordMatch`) a shared-plane gain landing together with a smaller arm-specific loss reads as one net
fall and is ratcheted in; only the printed ratio shows the loss.

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
