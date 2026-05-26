# gen Ecosystem Architecture

How the eight gen libraries compose to form a framework-building toolkit for Nix.

## Overview

The gen ecosystem is a set of decoupled Nix libraries that together provide the infrastructure for building demand-driven, graph-structured configuration frameworks. Each library owns one concern. The coupling point is the **consumer** (e.g., den), not the libraries themselves.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Consumer (den v2)                        │
│  Wires libraries with domain semantics: entities, aspects,     │
│  policies, pipes, output assembly                               │
└────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┬───┘
     │       │       │       │       │       │       │       │
     ▼       ▼       ▼       ▼       ▼       ▼       ▼       ▼
   gen    gen-     gen-     gen-    gen-    gen-    gen-    gen-
         schema  aspects   scope   graph  select   bind   derive
```

## Dependency Graph

Libraries have minimal inter-dependencies. Most are independent.

```
gen (pure primitives — zero deps)
├── gen-schema (imports gen)
├── gen-select (imports gen pure tier)
│   └── gen-derive (imports gen + gen-select adapter tier)
│
gen-aspects (independent — takes { lib } only)
gen-scope   (independent — takes { lib } only)
gen-graph   (independent — takes { lib } only)
gen-bind    (independent — takes { lib } only)
```

**Five of eight libraries have zero gen-ecosystem dependencies.** gen-schema depends on gen for identity/validation/refs. gen-select depends on gen pure tier for intensional equality. gen-derive depends on gen + gen-select for its adapter tier (core tier needs gen only).

## Library Roles

### Foundation Layer

**gen** — Pure primitives shared across the ecosystem.

- Search monad (indexed state threading with convergence)
- Intensional functions (program-point identity, conservative equality)
- Record algebra (scoped labels, mixin composition)
- Module tier: identity hashing, validators, strict modules, ref types

Every other gen-* library that needs identity or validation imports gen. The pure tier has zero dependencies — not even nixpkgs.

### Type System Layer

**gen-schema** — Typed record registries.

Declares **kinds** (record types), creates **instance registries**, handles strict validation, identity hashing, cross-instance references, collections, computed fields, refinement contracts, mixins, methods, and introspection. The apply pipeline is: validate → derive → apply.

Consumers use gen-schema to define their entity model (hosts, users, services, etc.) with typed, validated, extensible registries.

**gen-aspects** — Aspect type system.

Defines the **aspectType**: one type, dispatch in merge (Palmer flat typing). Classifies aspect keys into classes (output targets), collections (data aggregation), and nested aspects (recursive). Provides guard function detection (`canTake`), program-point identity, and configuration hooks (`cnf`).

Consumers use gen-aspects to define their composition units — the aspects that cut across entity boundaries and output dimensions.

### Evaluation Layer

**gen-scope** — HOAG evaluator.

Demand-driven evaluation over scope graphs. Provides `eval` which takes roots + attributes + parseParent and returns `{ node, get, allNodes }`. The `_eval` memoization cache co-located on every node ensures O(1) amortized attribute access. Supports inherited attributes (parent chain), synthesized attributes (children), circular attributes (fixpoint), collection attributes (traversal aggregation), and Neron resolution (D < I < P specificity).

This is the evaluation substrate — it computes values over the graph that other libraries query.

### Query Layer

**gen-graph** — Graph query combinators.

Accessor-based: takes `{ edges, parent, nodes, nodeData }` functions, answers structural questions. Lazy traversal (reachableFrom, canReach, pathsBetween) and global analysis (cycles, dependents, transpose). C-level BFS via `builtins.genericClosure`.

**gen-select** — Selector algebra.

Pattern matching over attributed graph positions. Selectors are `{ __sel = tag; ... }` attrsets. Constructors (star, attrs, and, or, not, has, within, when) compose into predicates evaluated by `matches selector id ctx`. Adapters bridge to gen-scope and gen-graph without importing them.

### Binding Layer

**gen-bind** — Module binding.

Injects external values into NixOS module functions. Handles three module shapes, merge strategy control (bind-wins/system-wins/error), lazy contracts, config thunks, provenance tracking, batch wrapping, and identity stamping. The bridge between scope-computed values and the NixOS module system.

### Dispatch Layer

**gen-derive** — Stratified rule dispatch.

Production rule system: rules (condition + action producer + identity) dispatched across stratified phases with DAG ordering. Fixpoint convergence loop handles monotonic context widening. Conflict resolution: override → priority → specificity → additive. Adapter tier bridges gen-select selectors as conditions.

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
   gen-derive: rules fire on context, produce effects, converge via fixpoint

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
       ├─ gen-derive dispatch (policy rules fire, produce effects)
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
graphLib.reachableFrom {
  edges = id: result.get id "imports";   # hits _eval cache
} "host:igloo"

# gen-select matches through gen-scope's accessors
ctx = selectLib.adapters.scope.mkContext {
  node = result.node;
  get = result.get;
};
selectLib.matches (sel.attrs { type = "host"; }) "host:igloo" ctx

# gen-derive uses gen-select adapter for rule conditions
deriveLib.dispatch {
  match = deriveLib.adapters.select.mkMatch selectLib;
  # ...
};
```

Each call hits memoized values. No redundant computation between libraries.

### Fixpoint Coordination

Three fixpoint loops, each at a different level:

| Level | Library | What converges | Triggered by |
|-------|---------|---------------|-------------|
| Value | gen (search.converge) | Index state + continuations | Search monad operations |
| Structure | gen-scope (circular attr) | Attribute values on nodes | Circular dependencies between attributes |
| Dispatch | gen-derive (fixpoint) | Rule context + fired set | Enrichment actions that widen context |

The consumer (den) coordinates these: gen-derive's fixpoint dispatches rules that may trigger gen-scope attribute recomputation, which in turn may trigger gen search convergence. Nix's lazy evaluation ensures only demanded values are computed.

## Performance Architecture

### Memoization Strategy

| Library | Mechanism | Scope |
|---------|-----------|-------|
| gen-scope | `_eval` attrset co-located on each node | Per-node, per-attribute |
| gen-graph | Accessor functions (caller's responsibility) | Delegates to source (gen-scope `_eval` when wired) |
| gen-derive | `fired` set across fixpoint iterations | Per-dispatch-session |
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
| Rule dispatch | O(rules × context checks) | fromFunctionMatch is O(1) per rule |
| Fixpoint iteration | O(iterations × dispatch) | Identified rules fire at most once |

### Fleet Scale Guidance

- **Use parseParent** in gen-scope — O(depth) vs O(n) node resolution
- **Use Tier 1 operations** (node, get) for per-entity work; Tier 2 (allNodes) for diagrams/fleet queries
- **Use point queries** (canReach, dependentsOf) over global analysis (dependents, transitiveClosure)
- **Partition large graphs** before global operations — cross-partition edges are rare
- **Accessor pattern** ensures zero redundant evaluation between gen-scope and gen-graph

## Design Constraints

1. **No circular library dependencies.** The dependency DAG is strictly acyclic.
2. **Libraries don't import each other's flake inputs.** gen-select doesn't import gen-scope; it provides adapters that accept gen-scope's result shape.
3. **Actions are opaque.** gen-derive doesn't interpret actions — consumers define the vocabulary via `mkActions` and `classify`.
4. **Conditions are opaque (in core).** gen-derive's core tier takes a `match` function; the adapter tier bridges gen-select as one possible condition language.
5. **Nix IS the evaluator.** gen-scope doesn't build an AG evaluator — it leverages Nix's native lazy evaluation, `lib.fix` for memoization, and attrset lookup for O(1) access.
6. **Pure tier has zero deps.** gen's pure tier (search, intensional, record) works without nixpkgs. Libraries that only need identity/search import the pure tier.
