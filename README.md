# gen — A Framework-Building Toolkit for Nix

[![CI](https://github.com/sini/gen/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

The gen ecosystem is a set of decoupled Nix libraries for building demand-driven, graph-structured configuration frameworks.

Each library owns one concern — types, evaluation, queries, binding, dispatch — and communicates through accessor functions and plain attrsets. The libraries compose at the consumer level, not through deep coupling. You can use gen-graph for graph queries without touching gen-scope, or gen-schema for typed registries without knowing about aspects.

The primary consumer is [den](https://github.com/sini/den), a NixOS/nix-darwin/home-manager configuration framework. But the gen libraries are generic — they have no knowledge of NixOS, system configuration, or den-specific concepts.

## Table of Contents

- [Trust — three proof axes](#trust--three-proof-axes)
- [Libraries](#libraries)
- [Architecture](#architecture)
- [Core Ideas](#core-ideas)
- [Theoretical Foundations](#theoretical-foundations)
- [Documentation](#documentation)

## Trust — three proof axes

If users are asked to write modules evaluated by a separate eval system, they need proof, not
promises. Everything below re-runs from a command — nothing here is taken on faith. The ecosystem
stands on three proof axes, each with public, CI-enforced artifacts.

**Correctness.** [VALIDATION.md](VALIDATION.md) is the full inventory: every claim paired with the
command that re-runs it and the way it fails. The two load-bearing proofs are the **byte-parity
oracles** (`nix flake check ./ci`) — the pure stack is byte-identical to the frozen nixpkgs stack it
replaced, down to the `id_hash` SHA, with mutation teeth proving the oracle discriminates content
(design in [`ci/README.md`](ci/README.md)). Underneath sit the per-library nix-unit suites — the
[gen-merge](https://github.com/sini/gen-merge) byte-mode engine's 167 tests, the
[gen-flake](https://github.com/sini/gen-flake) terminal's 89, and the rest — the purity scanners
that keep the cores nixpkgs-lib-free, the config-thunk deferral regression, and three migrated demos
(gen-schema / gen-aspects / gen-vars) that byte-check whole small consumers across engine bumps.

**Performance.** [BENCHMARKS.md](BENCHMARKS.md) reports evaluation-time cost against that same frozen
nixpkgs stack, **byte-parity-gated first** so a fast-but-wrong change cannot pass. The live table
regenerates from `nix run ./ci#perf-bench` (parity + ratio + linearity gates, plus the `classShare`
and `overrideWarm` reuse gates); the
[3-way comparison](BENCHMARKS.md#3-way-real-flake-comparison--gen-flake-vs-flake-parts-vs-adios-flake)
puts [gen-flake](https://github.com/sini/gen-flake) head-to-head with flake-parts and adios-flake
under a drvPath-equivalence oracle (`nix run ./ci#flake-compare`, 15/15 byte-identical). The
fleet-scale dedup numbers are measured in a separate lab and frozen as gates
([hola](https://github.com/sini/hola)).

**Observability.** The surface nixpkgs `evalModules` cannot offer:
[gen-flake](https://github.com/sini/gen-flake) v1 exposes provenance (which module set each option,
at what priority), a diff between two composes, and a memoization decision trace — powered by
[gen-merge](https://github.com/sini/gen-merge)'s always-on provenance channel and its warm re-eval,
with [gen-class](https://github.com/sini/gen-class) carrying the class-share mechanism den-hoag
consumes. Every one of these surfaces is asserted in tests (VALIDATION §2) and its engine cost is
measured (the BENCHMARKS engine-cost note).

## Libraries

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-types](https://github.com/sini/gen-types) | Pure structural type checker (`verify`-only leaf checkers — the checking half of the module system) |
| [gen-merge](https://github.com/sini/gen-merge) | Byte-mode module merge engine (`evalModuleTree` — a nixpkgs-lib-free `lib.evalModules`; the merge half) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) — re-hosted on gen-merge + gen-types |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system (traits, classification, dispatch) — re-hosted on gen-merge + gen-schema |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-flake](https://github.com/sini/gen-flake) | The single nixpkgs boundary (compose purely → inject resolved VALUES → build NixOS systems) |
| [gen-rebuild](https://github.com/sini/gen-rebuild) | Pure-Nix incremental rebuilder (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |

The hub exposes `mkGenLibs` with thirteen keys — `prelude`, `algebra`, `types`, `merge`, `schema`, `aspects`, `scope`, `graph`, `select`, `bind`, `dispatch`, `resolve`, `flake` — plus two standalone pure libraries, `gen-rebuild` and `gen-vars`. Each library exposes a single `.lib` value output.

## Architecture

```
gen-prelude  (pure nixpkgs-lib-free utility base)
gen-algebra  (pure primitives)

# module-system substrate (all nixpkgs-lib-free)
gen-types    (structural checker)          ← gen-prelude
gen-merge    (byte-mode evalModuleTree)    ← gen-prelude, gen-types
├── gen-schema   (typed registries)        ← gen-prelude, gen-merge, gen-algebra
│   └── gen-aspects (aspect types)         ← gen-prelude, gen-merge, gen-schema
│
gen-scope    (HOAG evaluator)              ← gen-prelude
gen-graph    (graph queries + ordering)    ← gen-prelude
gen-select   (selector algebra)            ← gen-prelude
gen-bind     (module binding)              ← gen-prelude
gen-dispatch (rule dispatch step)          ← gen-prelude
gen-rebuild  (incremental rebuilder)       ← gen-prelude
gen-resolve  (RAG evaluator + loop)        ← gen-scope, gen-graph, gen-rebuild, gen-algebra, gen-bind
gen-vars     (vars/secrets)                ← standalone

# the ONE nixpkgs boundary (compose purely → inject VALUES → build systems)
gen-flake    (value-injection terminal)    ← import-tree, gen-merge, gen-schema, gen-aspects, gen-bind, nixpkgs
```

The whole ecosystem is now **nixpkgs-lib-free**: gen-schema and gen-aspects were re-hosted onto gen-merge + gen-types (their `lib/` no longer touches `lib.evalModules` / `lib.types`, byte-identically to the old nixpkgs-driven versions). Full nixpkgs enters at exactly one place — `gen-flake`, the terminal that injects resolved values into a consumer's nixpkgs eval and builds NixOS systems. See [ARCHITECTURE.md](ARCHITECTURE.md) for the two-plane split, composition model, data flow, and performance architecture.

## Core Ideas

**Nix is the evaluator.** gen-scope doesn't build an attribute grammar evaluator — it leverages Nix's native lazy evaluation for demand-driven computation, `lib.fix` for memoization, and attrset lookup for O(1) attribute access. The `_eval` cache co-located on each scope graph node is just a lazy attrset.

**Accessors, not data.** gen-graph takes `{ edges = id: [...]; }` — functions, not materialized maps. gen-select takes `{ data = id: {...}; parent = id: ...; }`. When wired to gen-scope's memoized `result.get`, accessor calls are O(1) after first evaluation. Zero redundant computation between libraries.

**Identity everywhere.** Palmer's intensional functions (program-point identity + conservative equality) power dedup across the ecosystem: search continuation dedup (gen-algebra), aspect diamond dedup (gen-aspects), rule identity dedup (gen-dispatch), selector equality (gen-select).

**Step, loop, and ordering are separate concerns.** gen-dispatch is the pure relational dispatch *step* (guard→effect rules); it never sorts phases and never loops. Phase ordering is a forward producers-first order computed by gen-graph (`phaseOrder` over condensation), and the convergence *loop* lives in gen-resolve via `gen-scope.circular` (Kleene ascent). `dispatchStep`/`dispatchInit` pair the step with any loop.

**Actions are opaque.** gen-dispatch dispatches rules over a caller-supplied `phaseOrder` and groups actions by phase, but never interprets what actions mean. The consumer defines the vocabulary. gen-select matches patterns, but adapters bridge to gen-scope and gen-graph without importing them. Libraries provide machinery; consumers provide meaning.

**Compose purely, inject VALUES.** The module system is a pure plane: gen module trees are composed by gen-merge's byte-mode `evalModuleTree` (a nixpkgs-lib-free `lib.evalModules`), checked by gen-types, over the gen-schema/gen-aspects grammar — all without nixpkgs. gen-flake is the single terminal that crosses into nixpkgs: it injects the resolved config VALUES into a consumer's nixpkgs eval via `_module.args` (the query surface), then builds NixOS systems. **The invariant: gen TYPES never leave the pure eval; only VALUES cross.** A gen type rides as inert data inside `_module.args` (a consumer can read `genValues.schema.<kind>.options.<f>.type.name`) yet never enters the consumer's options tree, so nixpkgs never type-walks it. This is value-injection, not type-driving — the same one-way trade [adios](https://github.com/adisbladis/adios) takes. A pure engine cannot be driven by foreign nixpkgs-module libraries.

## Theoretical Foundations

The ecosystem is grounded in attribute grammar theory, scope graph formalism, and algebraic graph construction:

- **Attribute grammars** — Knuth (1968), Vogt (1989, HOAG), Hedin (2000, RAG), Sloane (2010, Kiama)
- **Scope graphs** — Neron (2015), van Antwerpen (2016, Statix; 2018, Scopes as Types)
- **Algebraic graphs** — Mokhov (2017)
- **Intensional functions** — Palmer (2024)
- **Record algebra** — Leijen (2005), Bracha & Cook (1990)
- **Contracts** — Findler (2002), Chitil (2012)
- **Rule systems** — Forgy (1982, RETE), Ehrig (2006), Arntzenius (2016, Datafun)

See [TERMINOLOGY.md](TERMINOLOGY.md) for the complete vocabulary with provenance.

## Documentation

- [TERMINOLOGY.md](TERMINOLOGY.md) — Unified vocabulary across the gen libraries with academic provenance
- [ARCHITECTURE.md](ARCHITECTURE.md) — Composition model, data flow, performance architecture, design constraints
