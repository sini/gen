# gen — Validation

This is the public inventory of every correctness proof behind the gen ecosystem. Each proof
below has an artifact you can read, a command a stranger can run, and a described failure mode —
no claim appears here without a way to reproduce it.

The load-bearing proof is the **byte-parity oracle** `rehost-den-parity`: it holds the pure-gen
module system (gen-prelude → gen-types → gen-merge → re-hosted gen-schema, all nixpkgs-lib-free)
byte-identical to the frozen nixpkgs reference stack it replaced, down to the `id_hash` SHA. It
runs as a permanent regression on `nix flake check ./ci` in this hub (`cbf3a5f`). Its retired
sibling over the **aspect** grammar, and the claim now left unasserted, are recorded in §1.
Everything else — the per-library unit suites (§2), the engine and terminal suites (§2's gen-merge /
gen-flake detail), the purity scanners (§3), the config-thunk deferral regression (§4), the migrated
demos (§5), the performance and 3-way-comparison gates (§6), and the fleet-scale regression gates
(§7) — is enumerated in the same reproducible form.

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
- **gen-flake** — the single terminal that crosses into nixpkgs: it composes purely, then injects
  the resolved config VALUES into a consumer's nixpkgs eval and builds NixOS systems.

Run the whole hub-side proof set:

```bash
nix flake check ./ci        # rehost-den-parity oracle + mkGenLibs wiring + treefmt
nix run ./ci#perf-bench     # parity + ratio + linearity performance gates
nix run ./ci#flake-compare  # the 3-way real-flake drvPath-equivalence check (15/15)
```

Test counts and revisions in this document were **measured by running the suites** (nix-unit 2.34.0,
Nix 2.34.7), not quoted from other docs: gen-merge (`fdbf140`), gen-flake (`88f639c`), gen-class
(`218c54f`), and the hub oracles/gates (`cbf3a5f`) were re-measured **2026-07-05** for this release;
the remaining per-library counts were measured **2026-07-04** at the revisions recorded in §2 (the
rev is the anchor — a reader checks out that exact rev and reproduces the count).

## The inventory at a glance

Every proof, its one command, and how it fails. The rest of this document expands each row.

| Proof                                                      | Command                                             | Fails if                                                                                                                                                    |
| ---------------------------------------------------------- | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Module system compatibility** (was `rehost-byte-parity`) | —                                                   | GATE SUSPENDED, PROMISE STANDS — rebuilt at the final rounds; carrier den-hoag-gkkh                                                                         |
| Real-den byte-parity (`rehost-den-parity`)                 | `nix flake check ./ci`                              | den's real registry shape diverges across stacks                                                                                                            |
| gen-merge engine suite (167)                               | `nix flake check ./ci` (in the gen-merge repo)      | any merge / lint / classify / warm / provenance test regresses                                                                                              |
| gen-flake terminal suite (89)                              | `nix flake check ./ci` (in the gen-flake repo)      | compose / override / diff / realize / terminal regresses                                                                                                    |
| Per-library suites (§2 table)                              | `nix flake check ./ci` (per lib repo)               | any lib's nix-unit suite fails                                                                                                                              |
| Purity — nixpkgs-lib-free cores                            | `nix-unit --flake ./ci#tests.purity` (per pure lib) | a `nixpkgs`/`lib.evalModules`/`lib.types` token appears in `lib/`                                                                                           |
| Config-thunk deferral                                      | `nix-unit --flake ./ci#tests.deferral` (gen-merge)  | a marker forces early, or diverges from nixpkgs at the terminal                                                                                             |
| Migrated demos (canaries)                                  | each demo's `nix flake check` / eval                | a re-hosted demo stops producing byte-identical output                                                                                                      |
| Performance (parity + ratio + linearity)                   | `nix run ./ci#perf-bench`                           | a cell mis-digests, a ratio erodes past a win-gate, or growth is super-linear — over 12 of the 14 matrix rows; the 2 `aspects` rows are pure-only (§1 note) |
| 3-way comparison (drvPath equivalence)                     | `nix run ./ci#flake-compare`                        | any output builds differently across flake-parts / adios / gen-flake                                                                                        |
| Fleet-scale dedup gates                                    | `nix run ./ci#fleet-gates` (hola)                   | a byte gate flips, a saving no longer equals its arithmetic, or a floor is breached                                                                         |
| Fleet-number consistency (in-repo)                         | `nix run ./ci#fleet-consistency`                    | a cited fleet number drifts from its own arithmetic (pin / re-derivation / digest tie / floor)                                                              |

## 1. The byte-parity oracle, and the claim its retired sibling held

One check derivation in `ci/` asserts the pure stack's output equals the nixpkgs stack's output,
byte for byte. It takes the form of `mkParityCheck` (`ci/flake.nix`): it evaluates a set of result
keys and fails the build if **any** required key is not `true`. The pure side tracks the published
re-host mains; the reference side is frozen (see Pinning policy below). A future gen-merge or
re-host change that breaks parity — including the `id_hash` SHA — fails `nix flake check ./ci`.

A frozen reference holds the **bar** still; it does not hold the **subject** still. Where the
subject's grammar moves by design ruling, the reference cannot follow it and the gate reds on
improvements rather than on defects. That is why a second oracle over the **aspect** grammar was
retired rather than repaired, and its claim now sits unasserted — first subsection below. The
surviving oracle guards the registry/schema surface, whose grammar is stable.

The perf bench (§5) applies the same distinction: 12 of its 14 matrix rows keep a pure/ref digest
and win-gate; the 2 `aspects` rows are **pure-only** and keep their linearity gates and absolute
counters, but assert no pure/ref digest parity and no pure/ref CPU or counter win-gate.

### rehost-byte-parity — RETIRED as a GATE; the promise it held STANDS and is rebuilt at the final rounds

- ★★ **The governing ruling, owner, 2026-08-13, verbatim:**

  > *"I want to proceed with development towards correctness rather than burden ourselves with a
  > legacy trust oracle. The promises by the oracle stand; but they don't need to hold at every gate.
  > We can rebuild the oracle during the final rounds so we can make the same guarantees."*

  and, naming what the promises are:

  > *"they are on module system compatibility"*

  ⇒ **What is suspended is CONTINUOUS GATE ENFORCEMENT, not the commitment.** This row is not a
  withdrawn claim and must not be read as one: the promise is still owed, and the same guarantees are
  to be re-established — not renegotiated — when the oracle is rebuilt at the final rounds. A reader
  who finds this section and concludes gen no longer claims the property has read it backwards.

- **The promise, named: MODULE SYSTEM COMPATIBILITY.** Concretely — *gen's module system agrees with
  nixpkgs' on the shared grammar*, which is what anyone **migrating from nixpkgs modules** relies on.
  ★ It is a claim about an **external interface**, not about gen's internals, and that is why it
  needs an oracle with a reference at all: internal correctness is provable against gen's own suites,
  compatibility is not. **No command re-runs it today** — a statement about the instrument, never
  about the promise.

- **Command:** none — the Command cell in the inventory table above is empty, and that empty cell is
  the record. This document is an inventory of claims paired with the commands that re-run them, so a
  claim that has lost its command is kept here without one rather than deleted: a reader scanning the
  table sees the gap, where a reader scanning a shortened table would not.

- **Why it was retired:** the check compared the pure stack against a *frozen* pre-re-host
  gen-aspects/gen-schema pair. That made it silently assert a conjunction — (P1) the pure re-host
  computes what nixpkgs computes, **and** (P2) the published aspect grammar is semantically
  unchanged since the freeze. P2 is contradicted by design: the aspect grammar moves by ruling
  (`cnf.classes` → `cnf.keySemantics`, and container-relative aspect identity), and a frozen
  reference cannot follow it. The gate therefore reddened on ruled improvements while being unable
  to say which conjunct a red belonged to — the divergence grows monotonically, by construction.

- **Carrier of the successor: `den-hoag-gkkh`.** ADR-0025 item 2 rules that P1's enforcer is hola's
  harness extracted and generalized into a gen library whose reference side is a **parameter**, not
  a frozen input, and in which every assertion names the proposition it belongs to, so a deliberate
  grammar change is expressible as a named divergence rather than a red. The retired oracle's gate
  keys — `all-identical`, `both-evaluated`, `teeth-mutation-diverges`, `den-realism` — are the
  coverage the successor inherits; `both-evaluated` and the mutation teeth are **required** contract
  features, since their absence is the standard way a parity harness reads green while asserting
  nothing. The retired implementation stays readable in git history at `ci/rehost-byte-parity.nix`;
  no copy was made.

- **What still holds, so this is not read as a wider hole than it is:** `rehost-den-parity` (below)
  covers gen-prelude / gen-types / gen-merge / gen-algebra / gen-schema at the same byte bar —
  including the `id_hash` SHA and the mutation teeth — and is green. What is unasserted is the
  **aspect-grammar** layer specifically: that was the retired oracle's unique contribution over
  `rehost-den-parity`, and it is exactly the layer whose reference could not follow.

- **Retired:** 2026-08-13, ruling record `den-hoag-oyib`, spec
  `den-architecture/specs/2026-08-13-rehost-byte-parity-retirement-spec.md`.

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

### Pinning policy — what a frozen bar can and cannot hold

The oracle is a pure function of flake inputs, wired in `ci/flake.nix`:

- **Pure side** (the guarded thing) tracks the **published re-host mains** — `github:sini/gen-prelude`,
  `gen-types`, `gen-merge`, `gen-algebra`, `gen-schema`. A change that breaks byte-parity fails the
  check.
- **Reference side** is **frozen**: the original nixpkgs-signature gen-schema (`gen-schema-orig`,
  pinned at `2b7c2d39ad30f8fa5165d6861c01374f7c9cf3f6`) — its last commit before the re-host changed
  the signature — driven through a **pinned** `github:nix-community/nixpkgs.lib` (at
  `db3f255737b94216eb71cce308e2912cf6bc2d7c`), never an impure `getFlake "nixpkgs"`. Because the
  reference is a fixed golden output, the parity target is immovable.

**And that is exactly the policy's limit.** An immovable target is sound only where the guarded
grammar is itself stable. The registry/schema surface above is; the **aspect** grammar is not, so the
matching `gen-aspects-orig` input (which was pinned at `87bf758169bc1d7f3336132f22e7fe38c5adf954`) has
been removed rather than rotated forward: rotating it makes the reference uncallable, and freezing it
makes the gate red on every ruled grammar change. The rev remains an immutable revision on
`github:sini/gen-aspects` and the successor may re-pin it as a *parameter*; what was removed is the
unforced flake input, not the witness.

## 2. Per-library unit suites

Every gen library ships a nix-unit suite. The counts below are the `N/N successful` figure
nix-unit prints — i.e. every listed test **executed and passed** — at the recorded revision.

| Library      | rev       |    tests | suite artifact             |
| ------------ | --------- | -------: | -------------------------- |
| gen-prelude  | `968579c` |       41 | `ci/tests/`                |
| gen-algebra  | `40147f4` |      128 | `ci/tests/`                |
| gen-types    | `3513399` |      105 | `ci/tests/`                |
| gen-merge    | `fdbf140` |      167 | `ci/tests/` (detail below) |
| gen-schema   | `05a18be` |      398 | `ci/tests/`                |
| gen-aspects  | `dda5ab2` |      110 | `ci/tests/`                |
| gen-scope    | `8599e5f` |      167 | `ci/tests/`                |
| gen-graph    | `df7c893` |      153 | `ci/tests/`                |
| gen-select   | `7b1cdae` |      104 | `ci/tests/`                |
| gen-bind     | `f08a103` |       65 | `ci/tests/`                |
| gen-dispatch | `f2956fb` |       55 | `ci/tests/`                |
| gen-resolve  | `d429eb3` |       58 | `ci/tests/`                |
| gen-flake    | `88f639c` |       89 | `ci/tests/` (detail below) |
| gen-class    | `218c54f` |       90 | `ci/tests/`                |
| gen-rebuild  | `7a87691` |      211 | `ci/tests/`                |
| gen-vars     | `56d1911` |       47 | `ci/tests/`                |
| **total**    |           | **1988** |                            |

- **Command (gate):** clone the repo, then from its root `nix flake check ./ci`.
- **Command (count):** `nix develop ./ci -c nix-unit --flake ./ci#tests` prints the `N/N successful`
  figure — this is what produced the numbers above.
- **Failure looks like:** nix-unit prints the failing `suite.test-name` with `got` vs `expected`
  and exits non-zero; `nix flake check ./ci` fails the same way through the shared CI module.

> gen-schema's 398-test suite (and gen-merge's 167 through the standalone CLI) can exhaust the
> default evaluator stack when run through standalone nix-unit in a single strict pass; run those
> with `ulimit -s unlimited`, or use `nix flake check ./ci`, which is unaffected.

### gen-merge — the engine (167 tests, `fdbf140`)

gen-merge is the `lib.evalModules` / `lib.types` replacement — the byte-mode merge half of the
module system — so its suite is the densest correctness surface in the ecosystem. Measured per suite:

| suite         |   tests | proves                                                                                                                                                             |
| ------------- | ------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| oracle        |      22 | byte-identity vs the nixpkgs merge over the shared parity corpus, its mutation teeth, and the freeform-absorption trio                                             |
| merge         |      15 | the core `(loc, defs)` merge, priority discharge, `mkIf`/`mkMerge`/`mkDefault`/`mkForce`                                                                           |
| combinators   |       7 | `listOf` / `nullOr` / `oneOf` / `either` type combinators                                                                                                          |
| checking      |       2 | leaf-type verification through gen-types                                                                                                                           |
| introspection |       3 | the options-introspection surface (sub-options, defaults)                                                                                                          |
| freeform      |       2 | `freeformType` absorption of unknown keys                                                                                                                          |
| deferred      |       1 | `deferredModule`                                                                                                                                                   |
| moduleArgs    |       1 | `_module.args` threading                                                                                                                                           |
| deferral      |      12 | config-thunk carry through compose → route → terminal (see §4)                                                                                                     |
| compat        |      12 | compat mode — nixpkgs `lib.types` drive the engine byte-identically at leaf types; the structural boundary is proven, not asserted                                 |
| core-kernel   |      12 | the fixed-input kernel (`evalModuleTree { coreShortCircuit }` + `mkCoreValue`) — default-off, byte-identical where it fires, deterministic firing                  |
| lint          |      34 | the portable-subset lint — accepts every parity-corpus module, rejects one fixture per unsupported construct, and inherits the engine's forcing profile (totality) |
| classify      |      12 | source-class threading + the `pureModule` marker + the `configOf` strip                                                                                            |
| warm          |      22 | warm re-eval byte oracles, incl. the adversarial **lying-marker** and the **group-splice hazard** teeth                                                            |
| provenance    |       9 | provenance records (winners / priority / defaulted) + the **values-untouched** tooth                                                                               |
| purity        |       1 | the nixpkgs-lib-free source scan (see §3)                                                                                                                          |
| **total**     | **167** |                                                                                                                                                                    |

- **The teeth that matter:** `warm.test-adversarial-lying-marker-diverges-visibly` (a data module
  that lies about being pure stale-splices and is caught at the byte oracle),
  `warm.test-group-splice-hazard` (an edited group does not wrongly reuse a stale sibling splice),
  `provenance.test-provenance-does-not-disturb-values` (the always-on provenance channel forces only
  its own records, never the config values), and the lint reject fixtures for the four out-of-subset
  constructs (`order` pass, options-introspection, `typeMerge`, `functionTo`).
- **Boundary notes (honest limits):** the lint checks the *byte-mode surface* — the exact set of
  constructs proven byte-identical — and flags what falls outside it; it is not a general nixpkgs-module
  linter. Compat mode is byte-identical at **leaf** types only; a structural shim (`submodule`) drags
  `lib.evalModules` back into every subtree and gives the win back (proven by
  `compat.test-structural-*`). Warm re-eval fires only when the edit's static dirty footprint leaves a
  loc untouched and no edited module carries a lying `pureModule` marker — any dirty contributor or a
  `config`-reading module re-merges (the standing byte oracle is the tooth). The full byte-mode
  boundary list lives in the gen-merge README.
- **Command:** from the gen-merge repo, `nix flake check ./ci`, or
  `ulimit -s unlimited; nix develop ./ci -c nix-unit --flake ./ci#tests` for the count (the CLI may
  need the raised stack; `nix flake check` does not). A single suite: e.g.
  `nix develop ./ci -c nix-unit --flake ./ci#tests.warm`.

### gen-flake — the terminal (89 tests, `88f639c`)

gen-flake is the one nixpkgs boundary (compose purely → inject resolved VALUES → build NixOS
systems) and the home of the observability surfaces (provenance / diff / decision trace). Measured
per suite:

| suite                 |  tests | proves                                                                                                           |
| --------------------- | -----: | ---------------------------------------------------------------------------------------------------------------- |
| compose               |      6 | the v1 pure compose over a gen tree (gen-merge engine, no nixpkgs)                                               |
| compose-empty         |      3 | empty / edge-case composes                                                                                       |
| compose-engine-args   |      4 | the `engineArgs` guard                                                                                           |
| compose-select-hosts  |      5 | the `selectHosts` guard                                                                                          |
| compose-override      |     19 | the **standing override tooth** — warm ≡ cold on values + provenance digests — plus chained `.override` variants |
| diff-added-removed    |      4 | the diff surface (options added / removed between two composes)                                                  |
| diff-changed          |      4 | diff of changed options (winner / priority)                                                                      |
| diff-provenance-shape |      2 | the diff provenance record shape                                                                                 |
| diff-lazy             |      4 | diff laziness pins (unforced thunks stay unforced)                                                               |
| realize-shape         |      4 | the realize output shape                                                                                         |
| realize-nodes         |      2 | per-node realization                                                                                             |
| realize-bindings      |      3 | binding injection through gen-bind                                                                               |
| realize-osconfig      |      2 | `osConfig` threading                                                                                             |
| realize-multi-class   |      2 | multi-class realize                                                                                              |
| terminal-inject       |      3 | value-injection into a consumer's nixpkgs eval via `_module.args`                                                |
| terminal-nixos        |      5 | the `nixosSystem` terminal (realizes only NixOS hosts)                                                           |
| flake-module          |     16 | the `flakeModule` v1 surface                                                                                     |
| purity                |      1 | the pure half is nixpkgs-lib-free                                                                                |
| **total**             | **89** |                                                                                                                  |

- **The tooth that matters:** `compose-override`'s warm-vs-cold check — a warm (memoized) override
  must produce values AND provenance digests byte-identical to a cold re-eval. This is the A4
  correctness contract; the perf side of the same claim is the `overrideWarm` gate in §6.
- **Command:** from the gen-flake repo, `nix flake check ./ci`, or
  `nix develop ./ci -c nix-unit --flake ./ci#tests` for the count.

## 3. Purity invariants

The pure plane's core promise is that its libraries never touch `nixpkgs.lib` — gen-merge is the
`lib.evalModules`/`lib.types` **replacement**, so it must not call them. This is enforced, not
asserted in prose.

- **The token-scanner (21 libraries).** Each of gen-algebra, gen-aspects, gen-bind, gen-class,
  gen-dispatch, gen-edge, gen-flake, gen-graph, gen-link, gen-lsp, gen-memo, gen-merge, gen-pipe,
  gen-product, gen-rebuild, gen-resolve, gen-schema, gen-scope, gen-select and gen-settings carries
  `ci/tests/purity.nix`, and gen-types carries the same scanner as
  `ci/tests/types-purity.nix` — 21 in all. **The count is the output of a command, not a tally kept
  by hand** — re-run it rather than trusting the number above:

  ```sh
  for d in gen-*; do
    git -C "$d" ls-files | grep -E '^ci/tests/(purity|types-purity)\.nix$' | sed "s|^|$d/|"
  done
  ```

  The pattern is **anchored and alternated deliberately**. The looser `ci/tests/.*purity.*\.nix$` returns
  the same 21 today — the two forms were compared and agree exactly — but it would also match a
  hypothetical `impurity.nix`, and would then over-count silently. A substring predicate that happens to
  be right today is still the wrong instrument for a figure meant to be re-run.

  It reported 21 files across 21 repositories when this section was last measured. The thirteen
  originally listed here are all still present and correct; eight libraries (gen-class, gen-edge,
  gen-link, gen-lsp, gen-memo, gen-pipe, gen-product, gen-settings) gained scanners afterwards and
  the figure was never restated, which is the failure mode a hand-kept count has and a command does
  not. ★ The instrument's scope, stated because it bounds the claim: it reads the sibling **working
  clones**, not this hub's locked inputs, so it measures the ecosystem as checked out rather than as
  pinned. The test reads
  every `lib/**.nix` (plus the root `flake.nix` / `default.nix`), strips comments, and asserts zero
  occurrences of the nixpkgs tether tokens — `nixpkgs`, `lib.types`, `lib.mkOption`, `lib.mkMerge`,
  `lib.evalModules`, `evalModules`, `{ lib }`, `{ lib,`. The library's own API names
  (`mkOption`, `mkMerge`, …) are deliberately **not** forbidden — only the nixpkgs tether is.

  - **Claim → artifact → command → failure:** `lib/` is nixpkgs-lib-free →
    `ci/tests/purity.nix` (test `test-library-source-is-nixpkgs-free`, `expr = violations; expected = [ ]`) → `nix develop ./ci -c nix-unit --flake ./ci#tests.purity` → a stray token
    makes `violations` a non-empty list of `file: 'token'` entries and the test fails. gen-types
    additionally ships a teeth test (`test-detector-catches-injected-violation`) proving the
    scanner actually fires on an injected violation.

- **The `pureModule` contract (gen-merge).** The warm-override path reads an author-supplied
  `pureModule` marker to decide a data module can be spliced without re-merging. That marker is a
  *contract*, and it has teeth: `classify.test-pure-module-is-marked-pure` /
  `test-marked-wrapper-with-imports-is-marked-pure` pin what counts as pure,
  `classify.test-configof-strips-marker-key` proves the marker never leaks into the merged value, and
  `warm.test-adversarial-lying-marker-diverges-visibly` proves a *lying* marker is caught at the byte
  oracle rather than silently corrupting output — so the contract is verified, not trusted.

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

## 5. Demos as regression canaries

Three libraries ship demos that were **migrated onto the pure engine and byte-checked against their
pre-migration output** — small consumers that break loudly if a re-host or engine change silently
shifts a byte. They are the ecosystem's canaries: not synthetic fixtures but real usage.

- **gen-schema / gen-aspects demos.** The migrated demos assert their resolved projection is
  byte-identical to the nixpkgs-driven original. The gen-aspects cascade demo's digest has now
  survived **two engine bumps** unchanged (the classify + warm landings and the provenance channel),
  which is exactly the property a canary should have — an unrelated engine change must not perturb a
  settled consumer's bytes.
- **gen-vars demo.** The `examples/multi-target` demo evaluates standalone (no den, no overrides) and
  is the pinned reference for gen-vars' pure `pure/` tier.
- **Claim → command → failure:** each demo is a check in its own repo; `nix flake check` (or the
  demo's eval) reproduces it, and a byte shift fails the demo's own equality assertion with `got` vs
  `expected`. These sit alongside the §1 oracles: the oracles prove the *engine* byte-identical on
  den-shaped fixtures; the demos prove *whole small consumers* keep producing identical output across
  engine changes.

## 6. Performance gates

The performance twin of the parity oracles. `nix run ./ci#perf-bench` drives `ci/perf-bench.nix`
(the pure stack vs the pinned-nixpkgs stack, scaled ~200× over the oracle fixtures) through
`nix-instantiate --eval` + `NIX_SHOW_STATS` and gates on three families:

- **parity** — every cell's sha256 projection digest must match across stacks, so a "fast but
  wrong" change cannot pass; this ties the perf corpus to the same validation bar as §1.
- **ratio** — the pure stack must stay lighter than the nixpkgs stack on the deterministic
  evaluator counters (thunks and allocation) at the largest workload size. cpu is measured and
  reported beside them but gated by nothing: a counter is a function of the evaluated expression
  alone, whereas cpu is a function of that expression and the host's frequency state together.
- **linearity** — the pure stack's counters must grow no worse than linearly across a ×4 size
  step; this is the net that caught the 2026-07-04 O(k²) `unique` key-union bug.

Two dedicated workloads run their own byte + reuse gates (both "stacks" are the pure engine):
**`classShare`** (gen-class tier-2 `applyCoreFixed` vs the full re-merge — the fixed-input path
must build ≤ 0.30× the full thunk graph, byte-identical) and **`overrideWarm`** (gen-merge warm
re-eval vs cold — the warm path must build ≤ 0.30× the cold thunks *and* allocation, byte-identical;
the perf twin of gen-flake's standing override tooth in §2).

The **3-way comparison** (`nix run ./ci#flake-compare`) is a separate hub gate: one representative
flake expressed in gen-flake vs flake-parts vs adios-flake, run under adios's `NIX_SHOW_STATS`
methodology, with a first-class **drvPath-equivalence** check — all **5 outputs × 3 systems = 15**
must build byte-identically across the three frameworks (they do; gen-flake carries the lowest
evaluator counters). This is the correctness oracle behind the 3-way counter tables in BENCHMARKS.

A gate breach exits non-zero with the offending table. The exact thresholds — retuned in lockstep
with engine changes, so kept in one place — and the full baseline numbers live in
[BENCHMARKS.md](BENCHMARKS.md); the harness rationale and the threshold-update policy are in
[`ci/README.md`](ci/README.md).

## 7. Fleet-scale regression gates

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
CI run `28727988245`** (`check` + `fleet-gates`). The three baselines those gates freeze are also
committed **in this repo** (`ci/bench/baselines/`), and this hub carries an in-repo arithmetic tooth
over them — the next subsection — so the numbers it cites cannot drift from their own arithmetic
without re-measuring in the lab.

### fleet-number consistency — the in-repo trust-surface roster

- **Claim:** every real-fleet number this repo cites (§"Fleet-scale results" in `BENCHMARKS.md`)
  still agrees with its own arithmetic — the three baselines name the same corpus/den/nixpkgs revs
  (pin agreement), each saving equals the sum/difference it is derived from, each byte gate is
  `true`, each recorded digest ties across files, and both floors hold (Arm-R `>= 0.60`, Task-7b
  `>= 0.008`). This is the **trust-surface** half of the owner principle: libraries stay unburdened
  by fleet metrics, and the hub — which already carries all the other gates and cites these
  numbers — carries the drift tooth.
- **Artifact:** the three baselines committed verbatim from the hola lab (`@4bab613`) under
  [`ci/bench/baselines/`](ci/bench/baselines/) (provenance + refresh in that dir's README), plus
  the nine-gate `[consistency]` roster in `ci/fleet-consistency.sh` — pure JSON arithmetic over the
  committed files, corpus-independent, seconds, **no fleet eval / re-measurement** (re-measurement
  is the lab's, above). The gate names match the lab's roster (labels too, except the adapted
  `g_dualsite`) so a reader can cross-reference the A1 report gate-for-gate.
- **Command:** `nix run ./ci#fleet-consistency` (all 9 gates PASS; also a GitHub `fleet-consistency`
  job); `nix run ./ci#fleet-consistency -- --selftest` proves the roster has teeth (it corrupts a
  copy of a baseline — a counter, then a floor — and asserts each fails, never touching the
  committed files).
- **Failure looks like:** a `[consistency]` FAIL line names the broken invariant (a pin
  disagreement, a saving that no longer equals its arithmetic, a byte gate flipped to `false`, or a
  floor breached) and the run exits non-zero. A legitimate lab re-measure that shifts a baseline is
  re-pinned here and its cited numbers updated in the same PR — a floor is never lowered nor a
  workload deleted to pass.

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

## 8. Re-run everything

From this hub's root:

```bash
# the byte-parity oracle (permanent regression) + mkGenLibs wiring + treefmt
nix flake check ./ci

# raw oracle results for eyeballing
nix eval ./ci#lib.parity.den --json | jq

# performance gates (parity + ratio + linearity) + the 3-way drvPath-equivalence check
nix run ./ci#perf-bench
nix run ./ci#flake-compare

# the cited fleet numbers still agree with their own arithmetic (9 gates + teeth, seconds)
nix run ./ci#fleet-consistency
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
# the warm re-eval byte oracles (in the gen-merge repo)
nix develop ./ci -c nix-unit --flake ./ci#tests.warm
```

The full library set — each with its revision and test count — is the table in
[§2](#2-per-library-unit-suites).
