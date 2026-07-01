# gen Ecosystem Architecture

How the gen libraries compose to form a framework-building toolkit for Nix.

## Table of Contents

- [Overview](#overview)
- [Dependency Graph](#dependency-graph)
- [Library Roles](#library-roles)
- [Composition Patterns](#composition-patterns)
- [Performance Architecture](#performance-architecture)
- [Design Constraints](#design-constraints)

## Overview

The gen ecosystem is a set of decoupled Nix libraries that together provide the infrastructure for building demand-driven, graph-structured configuration frameworks. Each library owns one concern. The coupling point is the **consumer** (e.g., den), not the libraries themselves.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Consumer (den v2)                        │
│  Wires libraries with domain semantics: entities, aspects,     │
│  policies, pipes, output assembly                               │
└─────────────────────────────────────────────────────────────────┘
     │
     ▼
  mkGenLibs keys:
    gen-prelude · gen-algebra · gen-schema · gen-aspects · gen-scope
    gen-graph · gen-select · gen-bind · gen-dispatch · gen-resolve
  standalone pure libs:
    gen-rebuild · gen-vars
```

## Dependency Graph

Libraries have minimal inter-dependencies. Most are independent.

```
gen-prelude (pure nixpkgs-lib-free utility base — zero deps)
gen-algebra (pure primitives — zero deps)
├── gen-schema (imports gen-algebra; + nixpkgs-lib)
│   └── gen-aspects (imports gen-schema; + nixpkgs-lib)
│
gen-scope    (gen-prelude)
gen-graph    (gen-prelude)
gen-select   (gen-prelude; zero gen-sibling deps)
gen-bind     (gen-prelude)
gen-dispatch (gen-prelude only)
gen-rebuild  (gen-prelude)
gen-resolve  (gen-scope + gen-graph + gen-rebuild + gen-algebra + gen-bind)
gen-vars     (standalone pure)
```

Each library exposes a single `.lib` value output — the obsolete functor-call form `gen-graph { inherit lib; }` is gone (`__functor` is banned ecosystem-wide). Dependency classes are declared honestly: **A** pure `{}`, **B** gen-prelude, **C** nixpkgs-lib, **D** nixpkgs-lib + gen-dep.

Most libraries are now nixpkgs-lib-free, built on `gen-prelude`: gen-scope, gen-graph, gen-select, gen-bind, gen-dispatch, gen-rebuild. Only **gen-schema** and **gen-aspects** remain tethered to nixpkgs-lib (`lib.types` + `evalModules`, and the aspect grammar respectively), pending the pure-gen grammar re-host. gen-schema depends on gen-algebra for identity/validation/refs; gen-aspects depends on gen-schema for pluggable entry types via `mkType`. gen-dispatch depends only on gen-prelude (its gen-select bridge is a structural adapter, not an import). gen-resolve is Class B with five gen siblings — it hosts the convergence loop that ties the dispatch step, scope evaluation, and rebuild together.

## Library Roles

### Foundation Layer

**gen-prelude** — Pure nixpkgs-lib-free utility base.

Re-exports of `builtins` plus a vendored set of `lib` utilities, with zero dependency on nixpkgs. It is the substrate that lets gen-scope, gen-graph, gen-select, gen-bind, gen-dispatch, and gen-rebuild be nixpkgs-lib-free.

**gen-algebra** — Pure primitives shared across the ecosystem.

- Search monad (indexed state threading with convergence)
- Intensional functions (program-point identity, conservative equality)
- Record algebra (scoped labels, mixin composition, `foldLayers` for per-field-strategy fold)
- Either / validators / identity primitives

gen-algebra is now **fully pure** — a single `lib` tier (the former `pure` tier, renamed), zero dependencies, not even nixpkgs. Its old module tier (identity hashing, strict modules, ref types — the constructs that needed `lib.types`/`evalModules`) was relocated into gen-schema. Every other gen-\* library that needs identity or search imports gen-algebra.

### Type System Layer

**gen-schema** — Typed record registries.

Declares **kinds** (record types), creates **instance registries**, handles strict validation, identity hashing, cross-instance references, collections, computed fields, refinement contracts, mixins, methods, and introspection. The apply pipeline is: validate → derive → apply. The `mkType` parameter on `mkSchemaEntryType` supports pluggable entry types, allowing downstream libraries (e.g., gen-aspects) to define their own schema-backed types.

Consumers use gen-schema to define their entity model (hosts, users, services, etc.) with typed, validated, extensible registries.

**gen-aspects** — Aspect type system.

Defines the **aspectType**: one type, dispatch in merge (Palmer flat typing). Classifies aspect keys into classes (output targets), collections (data aggregation), and nested aspects (recursive). Provides guard function detection (`canTake`), program-point identity, and configuration hooks (`cnf`). Uses gen-schema's `mkType` for `mkAspectSchema` (schema-backed aspect registries) and provides `flatten` for recursive tree-to-flat-registry conversion by path identity.

Consumers use gen-aspects to define their composition units — the aspects that cut across entity boundaries and output dimensions.

### Evaluation Layer

**gen-scope** — HOAG evaluator.

Demand-driven evaluation over scope graphs. Provides `eval` which takes roots + attributes + parseParent and returns `{ node, get, allNodes }`. The `_eval` memoization cache co-located on every node ensures O(1) amortized attribute access. Supports inherited attributes (parent chain), synthesized attributes (children), circular attributes (fixpoint), collection attributes (traversal aggregation with traverse modes including `"neron"` for D > I > P ordered collection), and Neron resolution (D < I < P specificity).

This is the evaluation substrate — it computes values over the graph that other libraries query.

### Query Layer

**gen-graph** — Graph query combinators.

Accessor-based: takes `{ edges, parent, nodes, nodeData }` functions, answers structural questions. Lazy traversal (reachableFrom, canReach, pathsBetween) and global analysis (cycles, dependents, transpose). C-level BFS via `builtins.genericClosure`. It also owns the ordering front-door (`order.nix`): `phaseOrder` — a forward producers-first order over the condensation (a cycle or self-loop throws) — plus `entryAnywhere`/`entryAfter`/`entryBefore`/`entryBetween`. This is where gen-derive's phase ordering moved; gen-dispatch consumes the result.

**gen-select** — Selector algebra.

Pattern matching over attributed graph positions. Selectors are `{ __sel = tag; ... }` attrsets. Constructors (star, attrs, and, or, not, has, within, when) compose into predicates evaluated by `matches selector id ctx`. Adapters bridge to gen-scope and gen-graph without importing them.

### Binding Layer

**gen-bind** — Module binding.

Injects external values into NixOS module functions. Handles three module shapes, merge strategy control (bind-wins/system-wins/error), lazy contracts, config thunks, provenance tracking, batch wrapping, and identity stamping. The bridge between scope-computed values and the NixOS module system.

### Dispatch Layer

**gen-dispatch** — Relational rule dispatch STEP.

Production rule system: rules (condition + action producer + identity) dispatched across stratified phases. It is deliberately just the *step* — it does **not** own the convergence loop and does **not** sort phases. `dispatch` takes a pre-ordered `phaseOrder :: [phaseName]` (computed elsewhere) and returns `orderedPhases`, the present-only subsequence. Conflict resolution: override → priority → specificity → additive. `dispatchStep`/`dispatchInit` pair the step with an external loop; a gen-select bridge (`adapters.select`) supplies selectors as conditions. Removed vs the old gen-derive: `fixpoint` (the loop, now gen-resolve) and `topoSort`/`entry*` (the ordering, now gen-graph).

### Evaluation / Convergence Layer

**gen-resolve** — Demand-driven RAG evaluator over scope graphs.

A pure-Nix RAG schedule-conductor (Knuth 1968 attribute schedule + Vogt 1989 HOAG gate + two-stratum partition, cold/warm fold into `gen-scope.eval`). It **owns the convergence loop**: `gen-scope.circular { init = dispatchInit ctx; eq; } (dispatchStep { inherit dispatch; } cfg)` (Kleene ascent, Sloane 2010 §2.2) reproduces the old gen-derive fixpoint byte-identically. Class B — five gen siblings (gen-scope, gen-graph, gen-rebuild, gen-algebra, gen-bind).

## Composition Patterns

### How Libraries Wire Together in a Consumer

```
1. Schema defines entity model
   gen-schema: kinds (host, user, home), registries, refs, validation

2. Aspects define composition units
   gen-aspects: aspectType classifies content into classes/collections/nested

3. Scope graph evaluates the tree
   gen-scope: eval builds nodes, computes attributes demand-driven

4. Rules dispatch policies
   gen-dispatch: rules fire on context, produce effects (one step);
   gen-graph phaseOrder orders the phases; gen-resolve loops to convergence

5. Selectors match positions
   gen-select: neededBy, pipe.gather, policy guards use selectors as predicates

6. Graphs answer structural queries
   gen-graph: reachability, cycles, impact analysis over accessor records

7. Bindings wire values into modules
   gen-bind: scope-computed values → NixOS module functions via partial application
```

### Data Flow

```
Entity declarations (user input)
  → gen-schema registries (typed, validated, referenced)
  → gen-scope graph nodes (minimal descriptors with decls)
  → gen-scope eval (demand-driven attribute computation)
       ├─ gen-dispatch dispatch (policy rules fire, produce effects)
       ├─ gen-select matches (selectors filter graph positions)
       └─ gen-graph queries (reachability, cycles, impact)
  → gen-bind wrapping (computed values → NixOS module args)
  → Class output (NixOS, darwin, homeManager evalModules)
```

### Accessor Chain

The accessor pattern is the zero-cost bridge between libraries:

```nix
# gen-scope provides memoized evaluation
result = engine.eval { roots; attributes; parseParent; };

# gen-graph queries through gen-scope's accessors — O(1) per cached attr
genGraph.reachableFrom {
  edges = id: result.get id "imports";   # hits _eval cache
} "host:igloo"

# gen-select matches through gen-scope's accessors
ctx = genSelect.adapters.scope.mkContext {
  node = result.node;
  get = result.get;
};
genSelect.matches (sel.attrs { type = "host"; }) "host:igloo" ctx

# gen-dispatch uses gen-select adapter for rule conditions;
# phaseOrder comes from gen-graph, the loop from gen-resolve
genDispatch.dispatch {
  match = genDispatch.adapters.select.mkMatch genSelect;
  phaseOrder = genGraph.phaseOrder { /* phases + entry* constraints */ };
  # ...
};
```

Each call hits memoized values. No redundant computation between libraries.

### Fixpoint Coordination

Three fixpoint loops, each at a different level:

| Level | Library | What converges | Triggered by |
|-------|---------|---------------|-------------|
| Value | gen-algebra (search.converge) | Index state + continuations | Search monad operations |
| Structure | gen-scope (circular attr) | Attribute values on nodes | Circular dependencies between attributes |
| Dispatch | gen-resolve (via gen-scope.circular) | Rule context + fired set | Enrichment actions that widen context |

The dispatch loop is **not** owned by gen-dispatch — gen-dispatch supplies only the step (`dispatchStep`/`dispatchInit`), and gen-resolve drives it to convergence with `gen-scope.circular` (Kleene ascent). The consumer (den) coordinates these: gen-resolve's loop runs the dispatch step, which may trigger gen-scope attribute recomputation, which in turn may trigger gen-algebra search convergence. Nix's lazy evaluation ensures only demanded values are computed.

## Performance Architecture

### Memoization Strategy

| Library | Mechanism | Scope |
|---------|-----------|-------|
| gen-scope | `_eval` attrset co-located on each node | Per-node, per-attribute |
| gen-graph | Accessor functions (caller's responsibility) | Delegates to source (gen-scope `_eval` when wired) |
| gen-dispatch | `fired` set across loop iterations (loop driven by gen-resolve) | Per-dispatch-session |
| gen-select | None (stateless predicate evaluation) | Each match is fresh but data access hits gen-scope cache |

### Cost Model

| Operation | Cost | Bottleneck |
|-----------|------|-----------|
| Attribute access (cached) | O(1) | Nix attrset lookup |
| Attribute access (first, root) | O(1) | Lazy thunk evaluation |
| Attribute access (first, synthesized) | O(depth) | Parent chain walk via parseParent |
| Graph traversal (lazy) | O(reachable) | C-level BFS |
| Graph traversal (global) | O(n) | Full node enumeration |
| Selector match | O(selector complexity) | Short-circuit on first false/true |
| Rule dispatch (one step) | O(rules × context checks) | fromFunctionMatch is O(1) per rule |
| Convergence loop iteration | O(iterations × dispatch) | gen-resolve loop; identified rules fire at most once |

### Fleet Scale Guidance

- **Use parseParent** in gen-scope — O(depth) vs O(n) node resolution
- **Use Tier 1 operations** (node, get) for per-entity work; Tier 2 (allNodes) for diagrams/fleet queries
- **Use point queries** (canReach, dependentsOf) over global analysis (dependents, transitiveClosure)
- **Partition large graphs** before global operations — cross-partition edges are rare
- **Accessor pattern** ensures zero redundant evaluation between gen-scope and gen-graph

## Design Constraints

1. **No circular library dependencies.** The dependency DAG is strictly acyclic.
1. **Libraries don't import each other's flake inputs.** gen-select doesn't import gen-scope; it provides adapters that accept gen-scope's result shape.
1. **Actions are opaque.** gen-dispatch doesn't interpret actions — consumers define the vocabulary via `mkActions` and `classify`.
1. **Conditions are opaque (in core).** gen-dispatch's core tier takes a `match` function; the adapter tier bridges gen-select as one possible condition language.
1. **Nix IS the evaluator.** gen-scope doesn't build an AG evaluator — it leverages Nix's native lazy evaluation, `lib.fix` for memoization, and attrset lookup for O(1) access.
1. **gen-algebra is fully pure.** Its single `lib` tier (search, intensional, record, either, identity) works without nixpkgs. Libraries that only need identity/search import it directly. The nixpkgs-lib-free base for the rest of the ecosystem is `gen-prelude`; only gen-schema and gen-aspects remain tethered to nixpkgs-lib.
