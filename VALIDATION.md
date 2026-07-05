# gen — Validation

This is the public inventory of every correctness proof behind the gen ecosystem. Each proof
below has an artifact you can read, a command a stranger can run, and a described failure mode —
no claim appears here without a way to reproduce it.

The two load-bearing proofs are the **byte-parity oracles**: they hold the pure-gen module system
(gen-prelude → gen-types → gen-merge → re-hosted gen-schema/gen-aspects, all nixpkgs-lib-free)
byte-identical to the frozen nixpkgs reference stack it replaced, down to the `id_hash` SHA. They
run as permanent regressions on `nix flake check ./ci` in this hub. Everything else — the
per-library unit suites (counted in the §2 table), the purity scanners, the config-thunk deferral
regression, the performance gates, and the fleet-scale regression gates (§6) — is enumerated in the
same reproducible form.

A few terms used throughout, for readers new to the ecosystem:

- **den** — the primary consumer, a NixOS / nix-darwin / home-manager configuration framework
  ([github:denful/den](https://github.com/denful/den)); its real registry and aspect shapes are the
  realism bar these oracles measure against.
- **re-host** — the change that ported gen-schema and gen-aspects off `nixpkgs.lib` onto gen-merge +
  gen-types, so they no longer call `lib.evalModules` / `lib.types` — byte-identically to the old
  nixpkgs-driven versions. "The re-host" throughout refers to that migration.
- **byte-mode** — gen-merge's merge engine (`evalModuleTree`) reproduces the nixpkgs module-merge
  **output** byte-for-byte over the surface den exercises, without `nixpkgs.lib`
  ([gen-merge README](https://github.com/sini/gen-merge)).
- **quirk** — a den pipe/effect that can carry a value depending on the final rendered config; §4
  proves such values ride the engine unforced.

Run the whole hub-side proof set:

```bash
nix flake check ./ci        # rehost-byte-parity + rehost-den-parity oracles
nix run ./ci#perf-bench     # parity + ratio + linearity performance gates
```

All test counts and revisions in this document were **measured on 2026-07-04** by running the
suites (nix-unit 2.34.0, Nix 2.34.7), not quoted from other docs.

## 1. The byte-parity oracles

Two check derivations in `ci/` assert the pure stack's output equals the nixpkgs stack's output,
byte for byte. Both take the form of `mkParityCheck` (`ci/flake.nix`): they evaluate a set of
result keys and fail the build if **any** required key is not `true`. The pure side tracks the
published re-host mains; the reference side is frozen (see Pinning policy below), so the bar never
drifts. A future gen-merge or re-host change that breaks parity — including the `id_hash` SHA —
fails `nix flake check ./ci`.

### rehost-byte-parity — the whole-stack integration proof

- **Claim:** the pure stack (gen-prelude + gen-types + gen-merge `evalModuleTree` + re-hosted
  gen-schema + re-hosted gen-aspects) is byte-identical to the nixpkgs stack (`lib.evalModules` +
  original gen-schema + original gen-aspects) over realistic den-shaped fixtures: a schema `host`
  kind with instances **including the `id_hash` SHA**, aspect trees with class content / includes /
  raw guard functions / nesting, and schema-declared options threaded into aspect instances — plus
  a read-only sample of a real den aspect tree run through both grammars.

- **Artifact:** `ci/rehost-byte-parity.nix` (fixtures parameterized by a shared provider `P` so
  both stacks run the identical source; the resolved projections are deep-compared).

- **Gate keys** (from `byteParityKeys` in `ci/flake.nix`, all must be `true`):

  ```nix
  byteParityKeys = [
    "all-identical"
    "both-evaluated"
    "teeth-mutation-diverges"
    "den-realism"
  ];
  ```

  `all-identical` — every fixture's pure projection equals its reference projection.
  `both-evaluated` — both stacks genuinely evaluated (not vacuously equal through a shared throw).
  `teeth-mutation-diverges` — the mutation teeth (below) fired.
  `den-realism` — a real den-shaped aspect tree flattens byte-identically through both grammars.

- **The `id_hash` claim:** the `schemaFleet` fixture projects each instance's `id_hash` and
  deep-compares it across stacks; the mutation teeth then perturb a host `addr` and assert the
  resulting `id_hash` **diverges** from the reference — so the SHA is inside the compared surface,
  not merely alongside it.

- **Mutation teeth:** `teeth-mutation-diverges` changes one `addr` and requires the `id_hash` to
  change. Without teeth, "identical" could hold vacuously (e.g. both stacks throwing the same
  error); the teeth prove the oracle discriminates content.

- **Command:** `nix flake check ./ci` (builds the `rehost-byte-parity` check). Raw result for
  eyeballing: `nix eval ./ci#lib.parity.byte --json | jq`.

- **Failure looks like:** the check derivation prints
  `PARITY REGRESSION — re-host is no longer byte-identical to the nixpkgs stack` on stderr and
  exits 1; the JSON `results` block shows which key went `false`.

### rehost-den-parity — the real-den acceptance gate

- **Claim:** den's **actual** registry shape is byte-identical through the re-hosted (pure)
  gen-schema and the original nixpkgs gen-schema. The fixture is lifted verbatim from
  `den/modules/options.nix`: the four collections (including the OR-merge `isEntity` / `isolated`),
  the `computed` `isEntity` derivation, the parent topology (`user`/`home` → `host`), the `conf`
  kind imports, den-shaped instance registries **with `id_hash`**, and den's real two-level nested
  option shape (`options.den.schema` / `options.den.hosts`).

- **Artifact:** `ci/rehost-den-parity.nix`.

- **Gate keys** (from `denParityKeys` in `ci/flake.nix`, all must be `true`):

  ```nix
  denParityKeys = [
    "parity-schema"
    "parity-instances"
    "both-evaluated"
    "teeth-mutation"
    "teeth-parity"
    "parity-nested"
  ];
  ```

  `parity-schema` — den's registry topology / collections / computed fields match across stacks.
  `parity-instances` — den-shaped instances match **including the `id_hash` SHA**.
  `both-evaluated` — both stacks genuinely evaluated.
  `teeth-mutation` — a mutated instance `addr` changes the `id_hash` on the reference side.
  `teeth-parity` — pure and reference agree on the mutated `id_hash`.
  `parity-nested` — den's real two-level option shape resolves identically through both engines.

- **Command:** `nix flake check ./ci` (builds the `rehost-den-parity` check). Raw result:
  `nix eval ./ci#lib.parity.den --json | jq`.

- **Failure looks like:** same `mkParityCheck` failure as above — the regression message on stderr,
  exit 1, and the `false` key visible in the JSON `results`.

### Pinning policy — why the bar can't drift

Both oracles are pure functions of flake inputs, wired in `ci/flake.nix`:

- **Pure side** (the guarded thing) tracks the **published re-host mains** — `github:sini/gen-prelude`,
  `gen-types`, `gen-merge`, `gen-algebra`, `gen-schema`, `gen-aspects`. A change that breaks
  byte-parity fails the check.
- **Reference side** is **frozen**: the original nixpkgs-signature gen-schema
  (`gen-schema-orig`, pinned at `2b7c2d39ad30f8fa5165d6861c01374f7c9cf3f6`) and gen-aspects
  (`gen-aspects-orig`, pinned at `87bf758169bc1d7f3336132f22e7fe38c5adf954`) — their last commits
  before the re-host changed the signature — driven through a **pinned**
  `github:nix-community/nixpkgs.lib` (at `db3f255737b94216eb71cce308e2912cf6bc2d7c`), never an
  impure `getFlake "nixpkgs"`. Because the reference is a fixed golden output, the parity target is
  immovable.

## 2. Per-library unit suites

Every gen library ships a nix-unit suite. The counts below are the `N/N successful` figure
nix-unit prints — i.e. every listed test **executed and passed** — measured 2026-07-04 at the
recorded revision.

| Library | rev | tests | suite artifact |
|---|---|---:|---|
| gen-prelude | `968579c` | 41 | `ci/tests/` |
| gen-algebra | `40147f4` | 128 | `ci/tests/` |
| gen-types | `3513399` | 105 | `ci/tests/` |
| gen-merge | `469dcf3` | 75 | `ci/tests/` |
| gen-schema | `05a18be` | 398 | `ci/tests/` |
| gen-aspects | `dda5ab2` | 110 | `ci/tests/` |
| gen-scope | `8599e5f` | 167 | `ci/tests/` |
| gen-graph | `df7c893` | 153 | `ci/tests/` |
| gen-select | `7b1cdae` | 104 | `ci/tests/` |
| gen-bind | `f08a103` | 65 | `ci/tests/` |
| gen-dispatch | `f2956fb` | 55 | `ci/tests/` |
| gen-resolve | `d429eb3` | 58 | `ci/tests/` |
| gen-flake | `df3192c` | 28 | `ci/tests/` |
| gen-rebuild | `7a87691` | 211 | `ci/tests/` |
| gen-vars | `56d1911` | 47 | `ci/tests/` |
| **total** | | **1745** | |

- **Command (gate):** clone the repo, then from its root `nix flake check ./ci`.
- **Command (count):** `nix develop ./ci -c nix-unit --flake ./ci#tests` prints the `N/N successful`
  figure — this is what produced the numbers above.
- **Failure looks like:** nix-unit prints the failing `suite.test-name` with `got` vs `expected`
  and exits non-zero; `nix flake check ./ci` fails the same way through the shared CI module.

> gen-schema's 398-test suite exhausts the default evaluator stack when run through standalone
> nix-unit in a single strict pass; run it with `ulimit -s unlimited` (as the count above was), or
> use `nix flake check ./ci`, which is unaffected.

## 3. Purity invariants

The pure plane's core promise is that its libraries never touch `nixpkgs.lib` — gen-merge is the
`lib.evalModules`/`lib.types` **replacement**, so it must not call them. This is enforced, not
asserted in prose.

- **The token-scanner (13 libraries).** Each of gen-merge, gen-schema, gen-aspects, gen-algebra,
  gen-graph, gen-scope, gen-select, gen-bind, gen-dispatch, gen-resolve, gen-rebuild, and gen-flake
  carries `ci/tests/purity.nix`, and gen-types carries the same scanner as
  `ci/tests/types-purity.nix` — 13 in all. The test reads
  every `lib/**.nix` (plus the root `flake.nix` / `default.nix`), strips comments, and asserts zero
  occurrences of the nixpkgs tether tokens — `nixpkgs`, `lib.types`, `lib.mkOption`, `lib.mkMerge`,
  `lib.evalModules`, `evalModules`, `{ lib }`, `{ lib,`. The library's own API names
  (`mkOption`, `mkMerge`, …) are deliberately **not** forbidden — only the nixpkgs tether is.
  - **Claim → artifact → command → failure:** `lib/` is nixpkgs-lib-free →
    `ci/tests/purity.nix` (test `test-library-source-is-nixpkgs-free`, `expr = violations; expected = [ ]`) → `nix develop ./ci -c nix-unit --flake ./ci#tests.purity` → a stray token
    makes `violations` a non-empty list of `file: 'token'` entries and the test fails. gen-types
    additionally ships a teeth test (`test-detector-catches-injected-violation`) proving the
    scanner actually fires on an injected violation.
- **Pure by construction (gen-prelude).** gen-prelude has **no flake inputs**, so nothing
  transitive — no nixpkgs — can enter its lock. There is nothing to scan for; the flake structure
  itself is the proof.
- **The documented exception (gen-vars).** gen-vars is deliberately **nixpkgs-lib-tethered**: it
  builds on `lib.toposort` and the NixOS module system. Only its bottom `pure/` tier is `lib`-free
  by construction. It is not part of the pure plane and carries no purity scanner by design.

**The nixpkgs.lib ecosystem policy** (stated in `ci/flake.nix`): where only `lib.*` is needed,
pull the pinned `github:nix-community/nixpkgs.lib` (auto-generated per nixpkgs release), **not**
full nixpkgs. Full nixpkgs enters at exactly two roles: the **runner** (the nix-unit harness,
treefmt, `runCommand` check derivations) and the **terminal** (gen-flake, which injects resolved
values into a consumer's nixpkgs eval and builds NixOS systems). The libraries themselves never
pull it.

## 4. The config-thunk deferral regression

- **Claim:** den's `__configThunk` markers — quirk values that depend on the final rendered
  `config`/`osConfig`, unknowable until the terminal fixpoint — ride the byte-mode engine as
  **opaque, unforced** data through both the composition merge and a mid-pipeline route/forward
  re-eval, and force **byte-identically** at the terminal (which reads the fixpoint `config` and
  the owner `osConfig`) to what den's nixpkgs `lib.evalModules` produces. This is a prerequisite
  for den-hoag, den's next-generation internals.
- **Artifact:** `gen-merge` `ci/tests/deferral.nix` (12 tests). It models den's marker
  (`{ __configThunk; __fn; }`) with a `probe = throw "forced too early"` poison payload, carries it
  through a three-stage pipeline (compose → route → terminal), and runs the identical scenario
  through nixpkgs `lib.evalModules` as the reference.
- **Teeth (anti-vacuity):** forcing the poison `probe` throws (proving the marker was carried, not
  reconstructed); forcing a thunk **early** against the composition config (`host.port = 0` → `1`)
  diverges from the deferred terminal value (`host.port = 8080` → `8081`), so the deferral changes
  the answer and is load-bearing; the `osConfig` thunk genuinely cannot resolve mid-pipeline. The
  reference (nixpkgs) side carries the identical teeth.
- **Command:** `nix develop ./ci -c nix-unit --flake ./ci#tests.deferral` in the gen-merge repo
  (12/12), or the whole `nix flake check ./ci`.
- **Failure looks like:** a premature force surfaces as a `forced too early` throw; a divergence
  from the nixpkgs reference fails `test-terminal-resolves-byte-identical` with `got` vs `expected`.

## 5. Performance gates

The performance twin of the parity oracles. `nix run ./ci#perf-bench` drives `ci/perf-bench.nix`
(the pure stack vs the pinned-nixpkgs stack, scaled ~200× over the oracle fixtures) through
`nix-instantiate --eval` + `NIX_SHOW_STATS` and gates on three families:

- **parity** — every cell's sha256 projection digest must match across stacks, so a "fast but
  wrong" change cannot pass; this ties the perf corpus to the same validation bar as §1.
- **ratio** — the pure stack must stay faster and lighter than the nixpkgs stack (cpu plus thunk
  and allocation counters, compared as machine-independent same-process ratios) at the largest
  workload size.
- **linearity** — the pure stack's counters must grow no worse than linearly across a ×4 size
  step; this is the net that caught the 2026-07-04 O(k²) `unique` key-union bug.

A gate breach exits non-zero with the offending table. The exact thresholds — retuned in lockstep
with engine changes, so kept in one place — and the full baseline numbers live in
[BENCHMARKS.md](BENCHMARKS.md); the harness rationale and the threshold-update policy are in
[`ci/README.md`](ci/README.md).

## 6. Fleet-scale regression gates

The proofs above measure the engine on isolated den shapes inside this hub. The fleet-scale
gates measure the **same engine on a real, heterogeneous fleet**, and they live in a separate
public repo — the measurement lab. A few terms for readers new to this half:

- **hola** ([github:sini/hola](https://github.com/sini/hola)) — the fleet-eval measurement lab.
  It forces den's real fleet under deterministic evaluator counters and freezes the results as
  gates. gen cites it; the audit path is **gen → hola → nix-config**.
- **fleet** — the three real hosts pinned by
  [nix-config](https://github.com/sini/nix-config) (`8f84aa6`): bitstream (nixpkgs-unstable),
  blade and cortex (nixpkgs-master).
- **A1 report** — the formal write-up of the protocol, results, prior reconciliation, and
  threats to validity that these gates enforce.

The campaign made two claims and turned both into a failing check (`ci/bench/fleet-gates.sh`,
wired as the `fleet-gates` app and a GitHub job). All rows below were **green at hola `d643a8d`,
CI run `28727988245`** (`check` + `fleet-gates`).

### fleet parity — the headline claim

- **Claim:** the den fleet builds **byte-identically** on the vendored engine — the vanilla
  build's `system.build.toplevel.drvPath` equals the vendored-engine build's, on all three hosts
  — and the vendored engine body byte-matches its nixpkgs source (`channel-modules-identity`).
- **Artifact:** `ci/tests/den-fleet-parity.nix` + the `[parity]` partition of `fleet-gates.sh`.
- **Command:** from the hola repo, `nix run ./ci#fleet-gates` (the `[parity]` line), or directly
  `nix eval --impure ./ci#tests.den-fleet-parity.<host>.expr` per host (expects `true`).
- **Failure looks like:** the `[parity]` gate prints a localizing block naming the host and
  `expected=true actual=<drv>` (vanilla ≠ vendored-engine drvPath), and the run exits non-zero.

### savings don't erode — the dedup byte gates and floors

- **Claim:** the three dedup findings stay sound and un-eroded — (a) **Arm R** (gen-rebuild
  incremental rebuild): a localized single-host edit is byte-identical to a full rebuild
  (`resultEqualsFullRebuild`) and skips **≥ 60%** of the fleet composition (measured 66.7%);
  (b) **Arm C** (den s2 class-share): the composition digest *and* terminal drvPath stay
  byte-identical under s2 on all three hosts — a resolution-only optimization, recorded as a
  +4.6% overhead, never floored as a win; (c) **Task 7b** (realization-plane class-share): the
  injected `systemd.units` core reassembles the member byte-identically
  (`injectedDigest == realDigest`) and saves **≥ 0.8%** of reconstruct fcalls (measured ~1.6%).
- **Artifact:** the three committed baselines
  (`ci/bench/baselines/{g6-split.json, dedup-savings.json, class-share-realization.json}`) plus
  the `[consistency]` partition of `fleet-gates.sh` (pure JSON arithmetic over them + the pinned
  floors); the full protocol is hola's `MEASUREMENT.md` and the A1 report.
- **Command:** from the hola repo, `nix run ./ci#fleet-gates -- --quick` (the seconds-long
  `[consistency]` sweep + floors); `nix run ./ci#fleet-gates -- --selftest` proves the gates have
  teeth (it corrupts a copy of a baseline — a counter, then a floor — and asserts each fails).
- **Failure looks like:** a `[consistency]` FAIL line names the broken invariant (a saving that no
  longer equals the sum of skipped-host composition, a byte gate flipped to `false`, or a floor
  breached); the run exits non-zero. A floor is never lowered and a workload never deleted to pass
  — a legitimate baseline shift is re-pinned in the same PR citing the new run.

### the counter gates — exact where sound, banded where honest

- **Claim:** the four deterministic evaluator counters
  (`nrFunctionCalls`/`nrPrimOpCalls`/`nrOpUpdateValuesCopied`/`nrThunks`) are re-measured and
  compared in two tiers — **exact** on the baseline evaluator, and within a **±0.1% relative
  band** on any other build. The band exists because a version *string* does not identify an
  evaluator *build*: CI's Determinate Nix and the baselines' upstream CppNix both print
  `nix (Nix) 2.34.7`, yet Determinate measured `nrPrimOpCalls` −8 on the deep evals (~4e-7
  relative; every digest identical). Digests and byte gates are exact on *every* evaluator (they
  are determined by the pinned inputs, not the Nix build); `gc.totalBytes` and `cpuTime` never
  enter any gate.
- **Artifact:** the `[ci-remeasure]` partition of `fleet-gates.sh` (re-runs the public-pinned
  arms — `baseline-*`, `rebuild-dedup`, and the Task-7b driver — and diffs digests always,
  counters per tier).
- **Command:** from the hola repo, `nix run ./ci#fleet-gates` (default: `[consistency]` +
  `[ci-remeasure]` + `[parity]`, ~12–18 min; `HOLA_STRICT_COUNTERS=1` forces the exact tier on the
  baseline evaluator).
- **Failure looks like:** the re-measure gate prints a verbose per-counter table
  (`cell counter: expected / actual / delta / tol`) for any cell outside its tier's tolerance, or
  names a mismatched digest; the run exits non-zero.
- **Caveat — the local-only partition.** The Arm-C `class-share` s2 arm needs den's local worktree
  branches (`git+file://`, campaign impure-local by design), which a CI runner cannot fetch. It is
  a documented **pre-push local gate** (`nix run ./ci#fleet-gates -- --local`), deliberately
  skipped in CI; the `[ci-remeasure]` and `[parity]` partitions run the public-pinned arms that CI
  can reproduce.

## 7. Re-run everything

From this hub's root:

```bash
# the two byte-parity oracles (permanent regressions) + treefmt
nix flake check ./ci

# raw oracle results for eyeballing
nix eval ./ci#lib.parity.byte --json | jq
nix eval ./ci#lib.parity.den  --json | jq

# performance gates (parity + ratio + linearity)
nix run ./ci#perf-bench
```

Per library — clone the repo (e.g. `github:sini/gen-schema`) and from its root:

```bash
nix flake check ./ci                                  # the suite + purity as a gate
nix develop ./ci -c nix-unit --flake ./ci#tests       # the N/N count, running every test
```

Or run a single sub-proof directly:

```bash
# purity scanner (any pure lib; gen-types uses .types-purity)
nix develop ./ci -c nix-unit --flake ./ci#tests.purity
# the config-thunk deferral regression (in the gen-merge repo)
nix develop ./ci -c nix-unit --flake ./ci#tests.deferral
```

The full library set — each with its revision and test count — is the table in
[§2](#2-per-library-unit-suites).
