# gen — A Framework-Building Toolkit for Nix

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

| Library | What it does | Tests | Deps |
|---------|-------------|-------|------|
| [gen-algebra](https://github.com/sini/gen-algebra) | Search monad, intensional functions, record algebra, validators | 40 | none |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries: kinds, instances, refs, collections, refinements, mixins | 129 | gen-algebra |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system: traits, classification, identity, class dispatch | 40 | none |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG evaluator: demand-driven attributes over scope graphs | 145 | none |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries: accessor-based traversal, reachability, cycles, fixpoint | 105 | none |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra: compositional pattern matching over graph positions | 163 | gen-algebra |
| [gen-bind](https://github.com/sini/gen-bind) | Module binding: inject args into NixOS modules, contracts, blame | 40+ | none |
| [gen-derive](https://github.com/sini/gen-derive) | Rule dispatch: stratified phases, fixpoint convergence, conflict resolution | 55 | gen-algebra, gen-select |

**Total: 717+ tests across 8 libraries.**

## Architecture

```
gen-algebra (pure primitives)
├── gen-schema (typed registries)
├── gen-select (selector algebra)
│   └── gen-derive (rule dispatch)
│
gen-aspects (aspect types)          ← independent
gen-scope   (HOAG evaluator)        ← independent
gen-graph   (graph queries)         ← independent
gen-bind    (module binding)        ← independent
```

Five of eight libraries have zero gen-ecosystem dependencies. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full composition model, data flow, and performance architecture.

## Core Ideas

**Nix is the evaluator.** gen-scope doesn't build an attribute grammar evaluator — it leverages Nix's native lazy evaluation for demand-driven computation, `lib.fix` for memoization, and attrset lookup for O(1) attribute access. The `_eval` cache co-located on each scope graph node is just a lazy attrset.

**Accessors, not data.** gen-graph takes `{ edges = id: [...]; }` — functions, not materialized maps. gen-select takes `{ data = id: {...}; parent = id: ...; }`. When wired to gen-scope's memoized `result.get`, accessor calls are O(1) after first evaluation. Zero redundant computation between libraries.

**Identity everywhere.** Palmer's intensional functions (program-point identity + conservative equality) power dedup across the ecosystem: search continuation dedup (gen-algebra), aspect diamond dedup (gen-aspects), rule identity dedup in fixpoint loops (gen-derive), selector equality (gen-select).

**Actions are opaque.** gen-derive dispatches rules and groups actions by phase, but never interprets what actions mean. The consumer defines the vocabulary. gen-select matches patterns, but adapters bridge to gen-scope and gen-graph without importing them. Libraries provide machinery; consumers provide meaning.

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

- [TERMINOLOGY.md](TERMINOLOGY.md) — Unified vocabulary across all 8 libraries with academic provenance
- [ARCHITECTURE.md](ARCHITECTURE.md) — Composition model, data flow, performance architecture, design constraints
