# gen — A Framework-Building Toolkit for Nix

[![CI](https://github.com/sini/gen/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

The gen ecosystem is a set of decoupled Nix libraries for building demand-driven, graph-structured configuration frameworks.

Each library owns one concern — types, evaluation, queries, binding, dispatch — and communicates through accessor functions and plain attrsets. The libraries compose at the consumer level, not through deep coupling. You can use gen-graph for graph queries without touching gen-scope, or gen-schema for typed registries without knowing about aspects.

The primary consumer is [den](https://github.com/sini/den), a NixOS/nix-darwin/home-manager configuration framework. But the gen libraries are generic — they have no knowledge of NixOS, system configuration, or den-specific concepts.

## Table of Contents

- [Libraries](#libraries)
- [Architecture](#architecture)
- [Core Ideas](#core-ideas)
- [Theoretical Foundations](#theoretical-foundations)
- [Documentation](#documentation)

## Libraries

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system (traits, classification, dispatch) |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-rebuild](https://github.com/sini/gen-rebuild) | Pure-Nix incremental rebuilder (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |

The hub exposes `mkGenLibs` with ten keys — `prelude`, `algebra`, `schema`, `aspects`, `scope`, `graph`, `select`, `bind`, `dispatch`, `resolve` — plus two standalone pure libraries, `gen-rebuild` and `gen-vars`. Each library exposes a single `.lib` value output.

## Architecture

```
gen-prelude  (pure nixpkgs-lib-free utility base)
gen-algebra  (pure primitives)
├── gen-schema   (typed registries)        ← + nixpkgs-lib
│   └── gen-aspects (aspect types)         ← + nixpkgs-lib
│
gen-scope    (HOAG evaluator)              ← gen-prelude
gen-graph    (graph queries + ordering)    ← gen-prelude
gen-select   (selector algebra)            ← gen-prelude
gen-bind     (module binding)              ← gen-prelude
gen-dispatch (rule dispatch step)          ← gen-prelude
gen-rebuild  (incremental rebuilder)       ← gen-prelude
gen-resolve  (RAG evaluator + loop)        ← gen-scope, gen-graph, gen-rebuild, gen-algebra, gen-bind
gen-vars     (vars/secrets)                ← standalone
```

Most libraries are nixpkgs-lib-free, built on `gen-prelude`. Only `gen-schema` and `gen-aspects` remain tethered to `nixpkgs-lib` (pending the pure-gen grammar re-host). See [ARCHITECTURE.md](ARCHITECTURE.md) for the full composition model, data flow, and performance architecture.

## Core Ideas

**Nix is the evaluator.** gen-scope doesn't build an attribute grammar evaluator — it leverages Nix's native lazy evaluation for demand-driven computation, `lib.fix` for memoization, and attrset lookup for O(1) attribute access. The `_eval` cache co-located on each scope graph node is just a lazy attrset.

**Accessors, not data.** gen-graph takes `{ edges = id: [...]; }` — functions, not materialized maps. gen-select takes `{ data = id: {...}; parent = id: ...; }`. When wired to gen-scope's memoized `result.get`, accessor calls are O(1) after first evaluation. Zero redundant computation between libraries.

**Identity everywhere.** Palmer's intensional functions (program-point identity + conservative equality) power dedup across the ecosystem: search continuation dedup (gen-algebra), aspect diamond dedup (gen-aspects), rule identity dedup (gen-dispatch), selector equality (gen-select).

**Step, loop, and ordering are separate concerns.** gen-dispatch is the pure relational dispatch *step* (guard→effect rules); it never sorts phases and never loops. Phase ordering is a forward producers-first order computed by gen-graph (`phaseOrder` over condensation), and the convergence *loop* lives in gen-resolve via `gen-scope.circular` (Kleene ascent). `dispatchStep`/`dispatchInit` pair the step with any loop.

**Actions are opaque.** gen-dispatch dispatches rules over a caller-supplied `phaseOrder` and groups actions by phase, but never interprets what actions mean. The consumer defines the vocabulary. gen-select matches patterns, but adapters bridge to gen-scope and gen-graph without importing them. Libraries provide machinery; consumers provide meaning.

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
