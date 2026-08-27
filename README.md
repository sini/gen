# gen — A Framework-Building Toolkit for Nix

[![CI](https://github.com/sini/gen/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

An ecosystem of small, independently versioned Nix libraries for building demand-driven,
graph-structured configuration frameworks.

## Table of Contents

- [What gen is](#what-gen-is)
- [What it provides](#what-it-provides)
- [Using it](#using-it)
- [What it promises](#what-it-promises)
- [How it's architected](#how-its-architected)
- [Core ideas](#core-ideas)
- [Theoretical foundations](#theoretical-foundations)
- [Documentation](#documentation)

## What gen is

Each gen library owns exactly one concern — type checking, module merging, scope-graph evaluation,
graph queries, selection, binding, dispatch, dataflow — names it after the literature it comes from,
and ships its own test suite and CI gate. They talk to each other through accessor functions and plain
attrsets rather than deep coupling, so you can take gen-graph for graph queries without gen-scope, or
gen-schema for typed registries without knowing what an aspect is. This repository is the hub: it owns
no concern of its own, and publishes the roster (`mkGenLibs`) and one flake-parts module. The CI
wrapper the ecosystem builds on lives in
[gen-harness](https://github.com/sini/gen-harness), which pins no gen library and so cannot close the
harness↔aggregator cycle the hub's copy carried. This hub no longer ships an `mkCi` of its own — the
extraction is complete, and even this repository's own gate is built from the harness's.

The primary consumer is [den](https://github.com/denful/den), a NixOS / nix-darwin / home-manager
configuration framework. The libraries themselves are generic — none of them knows what NixOS is.

## What it provides

The hub roster (`mkGenLibs`) is the membership authority — the tables below mirror it at this
revision and are corrected when it moves, never the other way around. Standalone libraries are
consumed directly and hold no roster key; retired libraries are archived for reference, wired to
nothing.
Each library's `flake.nix` `description` and its `AGENTS.md`
capability sheet are the authority on its scope — the sheet also records what the library explicitly
does *not* own, and which sibling does.

### Foundation

| Library                                              | What it owns                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [gen-prelude](https://github.com/sini/gen-prelude)   | The zero-dependency utility base: `builtins` re-exports plus the pure list / attrset / string helpers the substrate needs, vendored behaviour-identically from `nixpkgs.lib` so every other library can drop nixpkgs from its closure                                                                                                                                                                                                                                                                                              |
| [gen-algebra](https://github.com/sini/gen-algebra)   | Pure primitives: a Palmer §3 search monad, Leijen/Bracha record algebra with scoped labels and layer folding, Either combinators, and intensional-function constructors as encoders over an injected mint (`conservativeEq`'s regime discipline; Palmer's conservative equality) — `builtins` only, zero flake inputs as a stated contract                                                                                                                                                                                         |
| [gen-identity](https://github.com/sini/gen-identity) | The ecosystem's single minting authority: `hashIdentity`, a kind-tagged canonical hash over typed, bounded preimages, so structurally equal values mint one identity (equality follows Nix `==` in both directions; what cannot be encoded totally is refused by name rather than hashed partially). Dependency-free (`builtins` only) precisely so any library can take it without a cycle. Relocated whole from gen-schema; gen-schema retains identity-key reflection (`lib/id-hash.nix`) and constructs with the mint injected |

### Module system

| Library                                            | What it owns                                                                                                                                                                                                                                                                                                                              |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [gen-types](https://github.com/sini/gen-types)     | The checking half: every constructor returns a record whose `verify` maps a value to `null` (it inhabits the type) or an error string. No merging, no priorities, no fixpoint                                                                                                                                                             |
| [gen-merge](https://github.com/sini/gen-merge)     | The merge half: `evalModuleTree` collects a module tree, ties one `config` fixpoint, resolves definitions by priority, dispatches structural types, routes undeclared keys through a `freeformType`, and verifies leaves through injected gen-types checkers — reproducing `lib.evalModules` + `lib.types` merge output with zero nixpkgs |
| [gen-schema](https://github.com/sini/gen-schema)   | Typed record registries: **kinds** (deferred modules carrying collections, ref fields, a parent topology), **instances** (submodules with a content-addressed `id_hash`), and the registry option that binds them                                                                                                                         |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect-oriented composition types: one flat `aspectType` that dispatches by value shape in merge, giving every aspect a path-derived identity, one declared-key classification surface, a defunctionalized guard vocabulary, and a flat registry for downstream queries                                                                   |

### Graph and evaluation

| Library                                            | What it owns                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [gen-scope](https://github.com/sini/gen-scope)     | The higher-order attribute grammar (HOAG) evaluator: you supply root descriptors and attribute definitions, and `eval` returns an accessor record whose attributes compute lazily and memoize on an `_eval` cache co-located on each node                                                                                                                                                |
| [gen-graph](https://github.com/sini/gen-graph)     | Accessor-based graph queries: the caller supplies `edges` / `nodes` / `parent` / `nodeData` as plain functions, and gen-graph answers reachability, SCC condensation, phase order, edge-map algebra, pre-order folds and label-regex queries over them — it never stores the graph                                                                                                       |
| [gen-select](https://github.com/sini/gen-select)   | Selector algebra over attributed graph positions: `{ __sel = tag; … }` predicate values evaluated against a caller-supplied five-accessor context. Identity-bearing selectors match by `id_hash` or kind, never by `"kind:name"` strings                                                                                                                                                 |
| [gen-resolve](https://github.com/sini/gen-resolve) | The reference attribute grammar (RAG) evaluator and the convergence loop: folds semantic equations into a sealed `ResolveCtx` through `gen-scope.eval`, owning only the static attribute-dependency schedule and the cold/warm fold                                                                                                                                                      |
| [gen-product](https://github.com/sini/gen-product) | Graph products as first-class operations over accessor-graphs — Cartesian, tensor, strong, lexicographic — plus cells, slices, fibers, projections, quotients, sparse restriction and containment chains. Lazy in, lazy out                                                                                                                                                              |
| [gen-memo](https://github.com/sini/gen-memo)       | The incremental plane over the sole evaluator: a decision layer that never evaluates, only decides reuse. Inherits gen-resolve's warm fold plus override cone and gen-rebuild's dirty-cone propagation; its theory is Mokhov 2018 / RTD, and its DEFINITION is the byte-parity oracle against a cold evaluation — a plane output must be byte-identical to what the cold engine produces |

### Composition and wiring

| Library                                              | What it owns                                                                                                                                                                                                                                                                   |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [gen-bind](https://github.com/sini/gen-bind)         | Partial application of external bindings into module functions: inspects a module's formals, injects the matching bindings, and re-advertises the residual interface in the `__functionArgs` / `_file` convention                                                              |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch as one guard→effect **step**: walks a caller-supplied `groupOrder`, matches conditions against a threaded context, resolves conflicts, and buckets the opaque actions by group. It never sorts groups and never loops                                 |
| [gen-settings](https://github.com/sini/gen-settings) | *Experimental — subject to replacement.* Stratified settings resolution: folds a static `{ default; merge }` schema against an ordered layer list into `{ value; provenance; }`, adding refs-as-data and the graduated injection construct                                     |
| [gen-class](https://github.com/sini/gen-class)       | The class-share mechanism: groups nodes into classes by a caller-supplied key, computes each class's byte-identical shared **core** over a named projection, applies it back onto a member, and authorises every reuse claim by sha256 over canonical `toJSON`                 |
| [gen-link](https://github.com/sini/gen-link)         | Cross-flake aspect federation: normalizes each source aspect registry into an origin-free includes-graph, stamps every node with a federation origin, disjoint-unions the subgraphs, binds facet holes into instantiation identity, and returns a diffable resolution manifest |

### Standalone (off-roster)

| Library                                              | What it owns                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [gen-flake](https://github.com/sini/gen-flake)       | *Orphaned as reference (ADR-0031 F3) — dissolution complete.* It was the single nixpkgs / flake-parts boundary: `compose` resolved a gen module tree through gen-merge into values, a flat aspect registry, a per-host class projection and the provenance channel, plus `injectArgs`, `realize`, `diff` and the terminals. Every surface landed at a successor: the compose S2 core at this hub's `lib.compose` / interim `flakeModules.default`, warm/override/trace in [gen-memo](https://github.com/sini/gen-memo), the projection and `realize` in [gen-delivery](https://github.com/sini/gen-delivery), inject/terminals at the crossing's Adapter set. `diff.nix` stays in the orphaned repo as reference (a named input to gen-memo's failure-attribution spec). Off the roster and no longer a hub input, orphaned rather than deleted so its record stays readable — **take no new dependency on it** |
| [gen-rebuild](https://github.com/sini/gen-rebuild)   | *Retired — archived for reference.* The rebuilder dimension (Mokhov 2018) as a pure-Nix library: a flat relocatable result store, a per-key verifying trace, node-reuse decisions, and change propagation over a caller-supplied `recompute`. The library shell is retired with its content, which moved onto the incremental plane — [gen-memo](https://github.com/sini/gen-memo), a roster member in the `substrate` stratum. Off the roster and never a hub input, orphaned rather than deleted so its record stays readable — **take no new dependency on it.**                                                                                                                                                                                                                                                                                                                                             |
| [gen-vars](https://github.com/sini/gen-vars)         | *Experimental — subject to replacement.* Target-agnostic vars/secrets: normalizes generator declarations, toposorts them into a backend-agnostic plan, and fans one resolution-free file handle out to many consumer targets in one evaluation, emitting a generate script it never runs. Off-roster and deliberately `nixpkgs.lib`-tethered outside its bottom `pure/` tier                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| [gen-demand](https://github.com/sini/gen-demand)     | *Retired — archived for reference.* The typed demand cascade: registered **kinds** resolved demand values into resources, wiring and sub-demands, and a stratified fold over a registration-time kind DAG resolved the whole multiset with a provenance trace — termination a theorem, not a convergence loop. Retired as a library; the cascade re-expresses over gen-scope, the sole engine, as `lib/cascade.nix` + `lib/folds.nix` under claim vocabulary. Off the roster and no longer a hub input, orphaned rather than deleted so its record stays readable — **take no new dependency on it.** Its `adapters` export retires with its construct and moves nowhere                                                                                                                                                                                                                                        |
| [gen-edge](https://github.com/sini/gen-edge)         | *Retired — archived for reference.* The content-movement contract: every move of content between positions was one edge `(S,T,P,M)` — source, target, attrpath, mode — with edge-set derivation, Kahn-ordered materialization, and a frozen hashable edge trace that served as the cross-repo parity oracle. ADR-0010 §3 retires it into the movement vocabulary; twelve exports name destination constructs in [gen-view](https://github.com/sini/gen-view), the fourth destination §3 gained on 2026-08-20. The edge trace was the instrument that validated the spec retiring it, so the oracle cluster retired last, after movement AC-7 ran. Off the roster and no longer a hub input, orphaned rather than deleted so its record stays readable — **take no new dependency on it**                                                                                                                        |
| [gen-pipe](https://github.com/sini/gen-pipe)         | *Retired — archived for reference.* Scoped channels and a dataflow algebra over them: a channel's value at a position was a left fold over the contributions visible there under a pinned traversal, with `map` / `filter` / `fold` / `scan` / `route` / `join` / `tee` wiring channels into a DAG that `compose` validated and `run` evaluated demand-driven. ADR-0010 §3 retires it alongside gen-edge; the channel and dataflow constructs re-express in [gen-view](https://github.com/sini/gen-view), `sel` re-exported gen-select and consumers bind that directly, and B5's determinism and provenance laws are restated as properties of the query construction rather than dropped. Off the roster and no longer a hub input, orphaned rather than deleted so its record stays readable — **take no new dependency on it**                                                                              |
| [gen-lsp](https://github.com/sini/gen-lsp)           | Language-server surface over the gen graph. Off-roster: it consumes gen rather than composing into it, so it is a CONSUMER of the ecosystem and not a member of it — no `mkGenLibs` key, and nothing in the roster may take it as an input                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| [gen-harness](https://github.com/sini/gen-harness)   | The shared CI surface every library's `ci/flake.nix` is built from (`gen-harness.lib.mkCi`). Off-roster BY CONSTRUCTION: it pins no gen library, which is what lets every gen library pin IT without a cycle. Vendors the one prelude function it needs rather than taking the dependency                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| [gen-program](https://github.com/sini/gen-program)   | The policy library: turns policy declarations into a logic program and drives gen-scope's solver — well-founded semantics with `undefined` a named third value (Van Gelder, Ross & Schlipf 1991), stable-model coherence (Gelfond & Lifschitz 1988) adjudicated under a stated budget and carried as a required field on every result, and prior-pass verdicts entering as an interpretation, never as re-encoded rules. Off-roster by design: adjacent to the assembly layer, driving the evaluator the toolkit itself never calls                                                                                                                                                                                                                                                                                                                                                                             |
| [gen-assemble](https://github.com/sini/gen-assemble) | *Scaffold — no content yet.* The shared framework toolkit: the contribution protocol and its union point, the id convention, and the evaluator-demanded structural boilerplate that every assembling framework would otherwise write itself. `framework` stratum. Off-roster while empty — the roster entry lands with the first content migration, which three substrate preconditions gate                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

## Using it

Take only the libraries you need. Every library exports exactly one `.lib`, and each resolves its own
dependencies, so there is nothing to wire:

```nix
{
  inputs.gen-graph.url = "github:sini/gen-graph";

  outputs =
    { gen-graph, ... }:
    let
      genGraph = gen-graph.lib;
    in
    {
      # … use genGraph.query / genGraph.phaseOrder / … directly
    };
}
```

The full compose→realize route — a gen module tree resolved to values and built into
`nixosConfigurations` — enters through this hub's `flakeModules.default` (the INTERIM entry
surface rehomed under ADR-0031; the true framework surface arrives with the ADR-0027 interface):

```nix
{
  imports = [ inputs.gen.flakeModules.default ];

  gen.tree = ./gen-modules;                     # a directory of gen definition modules
  gen.extraModules.myhost = [ ./hardware.nix ]; # per-host platform/base NixOS modules
}
```

A consumer's ordinary nixpkgs modules then read the resolved values as one module argument
(`genValues`, injected by the flakeModule):

```nix
{ genValues, ... }:
{
  networking.hostName = genValues.hosts.igloo.name;
  # A gen type rides along as inert data — readable here, never in the options tree:
  #   genValues.schema.host.options.addr.type.name
}
```

The hub is optional. `mkGenLibs` gives you the whole roster under short keys (`genLibs.graph`,
`genLibs.merge`, …) when you want it, and `gen.lib.substrate` / `gen.lib.modules` /
`gen.lib.aspects` / `gen.lib.framework` give you one layer of it at a time — but a consumer reading `inputs.gen-X.lib` directly never needs
this repository at all.

## What it promises

Each promise below names the mechanism that enforces it. Where the enforcer is a person rather than a
command, that is said outright. The full inventory — every proof, the command that re-runs it, and how
it fails — is [TRUST.md](TRUST.md).

**Every roster library is nixpkgs-lib-free.** Enforced per repo by a source scanner,
`ci/tests/purity.nix` (gen-types carries it as `ci/tests/types-purity.nix`), run by
`nix develop ./ci -c nix-unit --flake ./ci#tests.purity`. Twenty-one of the twenty-two roster
libraries carry it. gen-prelude needs none — it declares no flake inputs at all, so nothing transitive can enter
its lock, and the flake structure is the proof. gen-vars is the documented exception, and is off-roster
for this reason. Retired gen-demand never gained a scanner and now never will: its Class-B claim rested
on its input list rather than on a check, and it leaves the roster with that gap open — the content
that moved acquired an enforcer at the move, because gen-scope's scanner is total over `lib/**.nix`.

**Full nixpkgs enters at the terminals alone.** No roster library consumes it: the nixpkgs contact
lives in the terminals a realization is handed, and the sanctioned default (`nixpkgs.lib.nixosSystem`)
is supplied by this hub's interim `flakeModules.default` — a consumer may override or suppress it.
Historically the boundary was gen-flake's `lib/terminals.nix`, the single file its purity scanner
excluded; that library is dissolved and its repo orphaned as reference (ADR-0031). Everywhere the
ecosystem needs `lib.*` alone it pulls the pinned `github:nix-community/nixpkgs.lib` rather than full
nixpkgs — policy stated in `ci/flake.nix` and visible in every `ci/` lock file.

**One `.lib` export per library.** Structurally enforced: `mkGenLibs` reads `genInputs.gen-<name>.lib`
for twenty of the twenty-two roster members — gen-class and gen-assemble are the exceptions (both
hub-injected via `import "${genInputs.gen-<name>}/lib" { … }` rather than a direct `.lib` read), and
their flakes export `.lib` too — so a library that renames, wraps or drops that output fails hub
evaluation at its first consumer. All twenty-two library flakes declare it today.

**Every library gates on its own CI.** All twenty-two library repos build their `ci/flake.nix` on
`gen-harness.lib.mkCi`, which `import-tree`s the whole `ci/tests/` directory — a new test file becomes
a gate the moment it lands, with no registration step. `nix flake check ./ci` from any repo root runs
the suite, and every roster library carries a GitHub Actions workflow that runs it on push and pull
request. This hub is not among them: it exposes flake `checks` and a perf `app` rather than a
nix-unit `tests` output, so it consumes the harness's check builders directly instead of its module —
the repository that ships a gate is gated by it.

**The pure module system is byte-identical to the nixpkgs one it replaced, on every axis but identity.**
The parity oracle in this hub's `ci/` — `rehost-den-parity` over den's actual registry shape — compares
resolved projections over the instance key sets and every non-identity field, and carries mutation
teeth. `id_hash` is the ADR-0016 excluded axis: the re-minted encoding is beyond any forward golden
pin's reach, so it is held by a teeth arm on the pure engine with its own seeded control, and forced on
both engines so a missing mint still fails loudly. `nix flake check ./ci`, wired as the `checks`
job. The reference side is pinned at a frozen pre-re-host revision, so the bar cannot drift. The
sibling oracle over the **aspect** grammar was retired, because a frozen reference cannot follow a
grammar that moves by design ruling; that claim is recorded unasserted in
[VALIDATION.md](VALIDATION.md) §1 rather than dropped.

**Performance claims are parity-gated.** `nix run ./ci#perf-bench` measures every cell and gates on
parity, ratio and linearity together: a parity mismatch fails the run whatever the timings say, so a
fast-but-wrong change cannot pass — over 12 of the 14 matrix rows; the 2 `aspects` rows are pure-only
for the reason above and keep linearity and absolute counters only. Wired as its own CI job, alongside
`fleet-consistency`, which re-derives every cited fleet number from committed baselines.

**Every library states what it does not own.** All twenty-three repositories (the hub included) carry
an `AGENTS.md` capability sheet whose "Not this library's job" table names the owning sibling for each
adjacent concern and quotes that sibling's own `flake.nix` description verbatim, most rows backed by a
grep that localizes the seam. This is a convention with a uniform artifact, not a CI gate.

**Names answer to the literature.** [TERMINOLOGY.md](TERMINOLOGY.md) carries a per-term provenance
column and a reference table of thirty-odd papers, and library sources cite their papers inline at the
point of use — `gen-scope/lib/resolve.nix` alone cites Neron, van Antwerpen and Sloane by section. This
promise is enforced by review against TERMINOLOGY.md, not by a check; no CI job verifies a citation.

## How it's architected

### Two planes, one crossing

The *composition plane* is pure and nixpkgs-lib-free: the module-system substrate
(`gen-types → gen-merge → { gen-schema, gen-aspects }`) resolves gen module trees to values without
ever touching `lib.evalModules`. The *terminal plane* is nixpkgs: gen-delivery's `realize` folds the
composed per-host projection through per-class terminals — `realize` is itself pure, and the nixpkgs
contact lives in the terminals it is handed (the hub's interim `flakeModules.default` supplies the
default `nixos` terminal; a consumer may supply its own). The
invariant across the crossing is that **gen types never leave the pure eval; only values cross** — a
gen type may ride along as inert data a consumer can read, but it never enters the consumer's options
tree, so nixpkgs never type-walks it. This is value-injection rather than type-driving, the same
one-way trade [adios](https://github.com/adisbladis/adios) takes: a pure engine cannot be driven by
foreign nixpkgs-module libraries.

### Two-stage instantiation, self-wired members

`mkGenLibs` (`lib/mkGenLibs.nix`) is a two-stage function. Stage one captures `genInputs` — the gen
flake inputs — and binds the roster. Stage two hands back that same value. Every member flake is
**self-wiring**: its `.lib` output resolves its own dependencies internally (gen-schema owns its
gen-algebra input, gen-settings its gen-algebra, gen-bind and gen-graph), so the hub does nothing but re-export
`genInputs.gen-X.lib`. The second argument is vestigial and kept only for call compatibility.

The roster is bound once rather than per application, so every route to it — a bucket, the
flakeModule, a direct call — holds one value rather than several evaluations of the same source.
Every member but `class` is shared that way anyway by input memoization; `class` is not, because it is
an `import` the hub applies itself, and a per-application binding re-allocated it.

**gen-class is the one exception.** Its flake `.lib` leaves the merge engine as `null` — every tier-1
export works without it — so the hub re-imports gen-class's `./lib` with the gen-merge kernel injected
as a value. That is what makes `mkGenLibs.class` carry the tier-2 `applyCoreFixed` path. gen-merge is
injected rather than declared as a flake input precisely so gen-class stays a single-input Class B
library.

### Three strata, one declaration

The roster carries a `strata` key declaring, for every member, which layer of the stack it belongs
to. The declaration is **total and explicit**: a member with no entry is a build error rather than a
member of an implicit residue bucket, because a defaulted stratum would let a new library join the
roster and land silently in whatever bucket the default happened to name. Adding a member is two
lines in one commit — the binding and its stratum — and `ci/mkgenlibs-eval.nix` fails the gate
otherwise.

The declaration is **enforced in one direction as well as in totality**. Packaging separation does
not do it: the ecosystem is already maximally separated at 23 repositories, and that did not stop a
substrate library taking a modules-stratum input. So `ci/direction-of-dependence.nix` reads each
member's declared root-flake input NAMES at the hub's pins and refuses, by name, any edge that runs
UP the chain `substrate < modules < aspects < framework` — with one closed, caused, edge-keyed
exception that is printed on every run rather than filed away.

Three of the five values publish a consumer path, each a **selection from the flat roster** rather
than a re-import, so `gen.lib.substrate.prelude` and the flat `prelude` are one value and not two
evaluations of the same source:

```
gen.lib.substrate   algebra bind dispatch graph prelude product schema scope select
gen.lib.modules     merge types
gen.lib.aspects     aspects class link
```

The other two publish nothing. `framework` (gen-settings) sits above the stack rather than in it — a
configuration framework assembles with it, and no substrate vocabulary is defined in its terms.
`retiring` (gen-resolve) marks a member whose content is
moving elsewhere: still reachable on the flat roster, deliberately not offered as something to adopt.
Both keep the declaration total without inviting a consumer onto a path that is about to close. The end
of the `retiring` path is leaving the roster once the content has landed — dropping the binding, the
stratum line and the hub pin together, with the repository orphaned for reference rather than deleted.
Four members have reached it: gen-demand took it first (ADR-0008 §4), gen-edge and gen-pipe
walked it together on ADR-0010 §3 once their content landed in gen-view, and gen-flake completed it
under ADR-0031 once its surfaces dissolved to their successors. The bucket is not a waiting
room — a member sits in it only while its destination is still being built.

### Dependency tiers

Libraries declare their class honestly: **A** pure `{}`, **B** gen-prelude, **C** nixpkgs-lib,
**D** nixpkgs-lib plus a gen dependency. Classes C and D are empty among the roster libraries. The
graph is strictly acyclic and shallow — most libraries have one or two inputs:

```
gen-prelude   zero inputs (Class A)
gen-algebra   zero inputs (Class A)
gen-select    zero inputs (Class A)

gen-types     ← prelude
gen-merge     ← prelude, types
gen-schema    ← prelude, types, merge, algebra
gen-aspects   ← prelude, merge, schema
gen-scope     ← prelude
gen-graph     ← prelude
gen-bind      ← prelude
gen-dispatch  ← prelude
gen-product   ← prelude
gen-class     ← prelude (+ gen-merge injected by the hub for tier 2)
gen-settings  ← prelude, algebra, bind, graph
gen-resolve   ← scope, graph, algebra, bind
gen-link      ← prelude, scope, resolve, schema, algebra, aspects
```

Libraries never import each other's flake inputs to reach a sibling's data — gen-select does not
import gen-scope, it provides an adapter that accepts gen-scope's result shape. That is what keeps the
roster composable at the consumer rather than at the library.

[ARCHITECTURE.md](ARCHITECTURE.md) is the deep reference: composition patterns, the data-flow chain,
the three fixpoint levels and who owns each, the memoization and cost model, and the full design
constraints.

## Core ideas

**Nix is the evaluator.** gen-scope does not build an attribute-grammar evaluator — it leverages Nix's
native lazy evaluation for demand-driven computation, `lib.fix` for memoization, and attrset lookup for
O(1) attribute access. The `_eval` cache co-located on each scope-graph node is just a lazy attrset.

**Accessors, not data.** gen-graph takes `{ edges = id: [...]; }` — functions, not materialized maps.
gen-select takes `{ data = id: {...}; parent = id: ...; }`. Wired to gen-scope's memoized `result.get`,
accessor calls are O(1) after first evaluation, and no computation is repeated between libraries.

**Identity everywhere.** Palmer's intensional functions — program-point identity with conservative
equality — power dedup across the ecosystem: search continuation dedup in gen-algebra, aspect diamond
dedup in gen-aspects, rule identity in gen-dispatch, selector equality in gen-select, and the
content-addressed `id_hash` in gen-schema.

**Step, loop and ordering are separate concerns.** gen-dispatch is the pure relational dispatch *step*,
a function of `(rules, context)` that never sorts and never iterates. Group ordering is a forward
producers-first order computed by gen-graph's `phaseOrder` over the condensation. The convergence *loop*
lives in gen-resolve via `gen-scope.circular` (Kleene ascent). Recomputing at the fixpoint makes the
action set a function of the converged state, so no cross-pass bookkeeping is needed.

**Actions are opaque.** gen-dispatch groups actions but never interprets them; gen-view materializes
content without knowing what content is; gen-scope's cascade produces pure data and constructs no modules. Libraries
provide machinery, consumers provide meaning.

## Theoretical foundations

The ecosystem is grounded in attribute-grammar theory, scope-graph formalism, and algebraic graph
construction:

- **Attribute grammars** — Knuth (1968), Vogt (1989, HOAG), Hedin (2000, RAG), Sloane (2010, Kiama)
- **Scope graphs** — Neron (2015), van Antwerpen (2016, Statix; 2018, Scopes as Types)
- **Algebraic graphs** — Mokhov (2017); graph products — Hammack, Imrich & Klavžar (2011)
- **Intensional functions** — Palmer (2024)
- **Record algebra** — Leijen (2005), Bracha & Cook (1990)
- **Contracts** — Findler (2002), Chitil (2012); refinement types — Rondon (2008)
- **Rule systems** — Forgy (1982, RETE), Ehrig (2006), Arntzenius (2016, Datafun)
- **Dataflow and stratification** — Kahn (1974, channels), Kahn (1962, toposort), Apt, Blair & Walker
  (1988, stratified evaluation)
- **Build systems** — Mokhov, Mitchell & Peyton Jones (2018, rebuilder dimension)

See [TERMINOLOGY.md](TERMINOLOGY.md) for the complete vocabulary with per-term provenance.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — Composition model, data flow, performance architecture, design constraints
- [TERMINOLOGY.md](TERMINOLOGY.md) — Unified vocabulary across the gen libraries, with academic provenance
- [TRUST.md](TRUST.md) — The map: what is proven, on which axis, and where each check lives
- [VALIDATION.md](VALIDATION.md) — The per-proof inventory: every claim, its command, and its failure mode
- [BENCHMARKS.md](BENCHMARKS.md) — Evaluation-time measurements and the gates that hold them
