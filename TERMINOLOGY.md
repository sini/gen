# gen Ecosystem Terminology

A consistent vocabulary grounded in academic literature, spanning the gen libraries and the den framework that consumes them.

## Table of Contents

- [Design Principles](#design-principles)
- [Core Terms](#core-terms)
- [Per-Library Vocabulary](#per-library-vocabulary)
  - [gen-prelude](#gen-prelude--pure-utility-base)
  - [gen-algebra](#gen-algebra--pure-primitives)
  - [gen-types](#gen-types--structural-type-checker)
  - [gen-merge](#gen-merge--byte-mode-merge-engine)
  - [gen-schema](#gen-schema--typed-record-registries)
  - [gen-aspects](#gen-aspects--aspect-type-system)
  - [gen-scope](#gen-scope--hoag-evaluator)
  - [gen-graph](#gen-graph--accessor-based-graph-queries)
  - [gen-select](#gen-select--selector-algebra)
  - [gen-bind](#gen-bind--module-binding)
  - [gen-dispatch](#gen-dispatch--relational-rule-dispatch-step)
  - [gen-resolve](#gen-resolve--rag-evaluator--convergence-loop)
  - [gen-flake](#gen-flake--value-injection-boundary)
  - [gen-edge](#gen-edge--content-movement-contract)
  - [gen-product](#gen-product--graph-products)
  - [gen-settings](#gen-settings--stratified-settings-resolution)
  - [gen-demand](#gen-demand--typed-demand-cascade)
  - [gen-pipe](#gen-pipe--scoped-channel-dataflow)
- [Den v2 Vocabulary (Consumer)](#den-v2-vocabulary-consumer)
- [Classes: The Output Dimension](#classes-the-output-dimension)
- [Cross-Cutting Patterns](#cross-cutting-patterns)
- [Academic References](#academic-references)

## Design Principles

1. **Every term has academic provenance.** No novel coinages for library concepts. Novel names only in user-facing effect vocabularies where clarity to non-academics takes priority.
1. **Same pattern, same name.** gen-schema collections and den collections are the same abstract pattern (multi-contributor aggregation with merge) at different levels (definition-time vs evaluation-time).
1. **Traits are for types, attributes are for values, collections are for aggregation, combinators are for composition.** Four orthogonal concerns, four terms, no overlap.
1. **The graph vocabulary (nodes, edges, constraints) is the structural substrate.** Everything else operates ON the graph.
1. **Prefix conventions are consistent across the ecosystem:**
   - `_key` on module-system configs = internal computed/read-only options (e.g., `_topology`, `_strict`, `_module`)
   - `__key` on plain attrsets = framework markers and pipeline internals (e.g., `__functor`, `__isWrappedFn`, `__sel`)
1. **No wasted work, by construction (Lévy 1978).** Laziness discharges Lévy's type-1 obligation (never evaluate a discarded subexpression) for free (Barendregt 1987); first-order acyclic scope/attribute evaluation never instantiates Lévy's type-2 (interior-sharing) problem. So no optimal-reduction engine is needed — `_eval`/dedup is Wadsworth DAG sharing, not interior sharing.

______________________________________________________________________

## Core Terms

These terms are shared across multiple libraries.

| Term | Definition | Used by | Academic provenance |
|------|-----------|---------|-------------------|
| **Attributes** | Computed values on graph nodes. Demand-driven, memoized by Nix laziness. | gen-scope, den | Knuth 1968; Sloane 2010 |
| **Collections** | Named multi-contributor aggregation points with a merge strategy. Multiple sources contribute; a combine function merges. | gen-schema, gen-scope, den | Sloane 2010 "collection attributes"; Van Wyk 2010 (Silver) |
| **Combinators** | Composition primitives that build attributes from other attributes or queries from other queries. | gen-scope, gen-graph | Sloane 2010 (attribute combinators); Arntzenius 2016 (monotonic query combinators) |
| **Traits** | Type classification and dispatch. One type, dispatch in merge. | gen-aspects | Palmer 2024 (intensional functions); den interpretation |
| **Nodes** | Vertices in a scope graph or abstract graph. Entities and aspects. | gen-scope, gen-graph, gen-schema | Neron 2015; Mokhov 2017 |
| **Edges** | Labeled relationships between nodes: P (parent/lexical), I (import/composition), custom labels. | gen-scope, gen-graph, gen-schema | Neron 2015; van Antwerpen 2018 |
| **Constraints** | Pruning rules that restrict resolution or composition. Propagate via graph ancestry. | gen-aspects, den | van Antwerpen 2016 (constraint-based scope graphs) |
| **Identity** | Program-point identity for conservative equality of functions and entities. | gen-algebra, gen-aspects, gen-dispatch, gen-schema | Palmer 2024 §2.2 |
| **Selectors** | Compositional pattern matching predicates over graph positions. | gen-select, gen-dispatch | CSS Selectors Level 4; XPath 3.1; Neron 2015 |
| **Rules** | Guarded transformation units: condition + action producer + identity. | gen-dispatch | Forgy 1982 (RETE); Ehrig 2006 |
| **Fixpoint** | Convergent iteration until a stability condition holds. The dispatch convergence loop lives in gen-resolve (via `gen-scope.circular`), not in gen-dispatch. | gen-resolve, gen-graph, gen-scope | Arntzenius 2016; Radul 2009; Sloane 2010 §2.2 |
| **Byte-mode** | Reproducing nixpkgs' order-sensitive `lib.evalModules` merge OUTPUT byte-for-byte on the gen surface, gated by an equivalence oracle. The cut-over conformance contract; distinct from the deferred confluent/structural merge mode. | gen-merge | nixpkgs module system; identity-dedup spike §3 |
| **Value-injection** | Composing purely, then injecting resolved config VALUES (never gen TYPES) into a consumer's nixpkgs eval via `_module.args`. The invariant: a pure engine cannot be driven by foreign nixpkgs-module libraries, so only values cross. | gen-flake | adios (adisbladis) — `compose → value → nixpkgs` prior art |
| **Two-plane split** | The composition plane (pure, nixpkgs-lib-free: `gen-types → gen-merge → { gen-schema, gen-aspects }`) vs the terminal plane (nixpkgs: `gen-flake.terminals.nixosSystem`, driven by `realize`). One sanctioned crossing. | gen-merge, gen-flake | — |

______________________________________________________________________

## Per-Library Vocabulary

### gen-prelude — Pure Utility Base

The nixpkgs-lib-free substrate. Re-exports of `builtins` plus a vendored set of `lib` utilities, with zero dependency on nixpkgs. gen-types, gen-merge, gen-scope, gen-graph, gen-select, gen-bind, gen-dispatch, and gen-rebuild are all built on it (Class B). With the module-system substrate (`gen-types → gen-merge`) now hosting gen-schema and gen-aspects, the whole library level is nixpkgs-lib-free — full nixpkgs enters only at the gen-flake terminal.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Prelude** | Vendored utility base: `builtins` re-exports + a curated subset of `lib` reimplemented without nixpkgs. | — |
| **Dependency class** | Honest tiering: **A** pure `{}`, **B** gen-prelude, **C** nixpkgs-lib, **D** nixpkgs-lib + gen-dep. | — |

### gen-algebra — Pure Primitives

Foundation library. **Fully pure** — a single `lib` tier (the former `pure` tier, renamed), zero dependencies, not even nixpkgs. The old module tier (identity/strict/ref constructs that needed `lib.types`/`evalModules`) was relocated into gen-schema. Exports record, search, either, intensional identity.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Search** | Indexed state monad for monotonic data accumulation with continuation-driven convergence. | Palmer 2024 §3 |
| **Index** | Key-value store within search state. Values accumulate via append. | Palmer 2024 §3 |
| **Continuations** | Registered callbacks that fire when an index key has unprocessed values during `converge`. | Palmer 2024 §3 |
| **Converge** | Fixed-point loop: fire all continuations on unprocessed values, repeat until stable. Safety guard at 1000 iterations. | Palmer 2024 §3 |
| **Intensional Functions** | Callable attrsets with `name` for identity comparison and inspectable `closure`. | Palmer 2024 §2.2-2.3 |
| **Intensional Equality** | Conservative equality by program point — same `name` = equal, regardless of closure contents. | Palmer 2024 §2.3, Theorem 1 (relies on Lemma 5.12) |
| **Record** | Attrset-with-shadow-stack representation supporting scoped labels. O(1) select. | Leijen 2005 |
| **Scoped Labels** | Duplicate labels form a stack — extension pushes, restriction pops, exposing previous values. | Leijen 2005 §2 |
| **Mixin** | Composition operator with two orientations: Smalltalk (delta wins over parent) and Beta (parent wins). gen-algebra uses Smalltalk: `combine (delta parent) parent`. | Bracha & Cook 1990 §2-4 |
| **Compose** | Associative mixin composition operator (⋆). | Bracha & Cook 1990 |
| **Either** | Sum type: `right` (success) or `left` (error). Used in validation pipelines. | — |
| **Validator** | Named predicate with error message. `mkValidator name pred message`. | — |
| **Identity Module** | NixOS module injecting deterministic `id_hash` (SHA-256) from primitive options. *(Relocated to gen-schema — needs `lib.types`/`evalModules`.)* | — |
| **Strict Module** | Freeform type that rejects undeclared keys with fix guidance. *(Relocated to gen-schema.)* | — |
| **Ref Type** | Cross-registry reference type. Input: string key. Output: resolved instance. *(Relocated to gen-schema.)* | — |
| **foldLayers** | Per-field-strategy fold over ordered layers. Each field declares its own merge strategy; layers are folded in order. Settings composition primitive. | Leijen 2005 (scoped labels generalized to per-field merge) |

### gen-types — Structural Type Checker

The checking half of the pure-gen module system. A type is a predicate boundary — `verify` returns `null` (inhabits) or an error string (blame). No merge, no priority, no fixpoint. `nixpkgs.lib`-free (Class B, gen-prelude).

| Term | Definition | Provenance |
|------|-----------|------------|
| **Checker** | The type record `{ name; verify; check; __name; __id; }`. `verify : v → null | err`; `check : v: v2:` throws-or-passes. | Findler 2002 (contracts as boundaries) |
| **verify / check** | `verify` = the predicate boundary (null = ok). `check` = validate-and-pass-through (throws the blame on failure). | Findler 2002 |
| **Primitives** | `string`/`str`, `int`, `bool`, `float`, `number`, `path`, `pathLike`, `attrs`, `list`, `function`, `derivation`, `null`, `any`, `never`. | `builtins.is*` |
| **Combinators** | `option`, `listOf`, `attrsOf`, `union`, `intersection`, `enum`, `tuple`, `optionalAttr`. Errors thread context through nesting. | structural typing |
| **struct** | Record checker + `.override { total?; unknown?; verify?; }`. `unknown = false` = closed world (reject undeclared keys). | structural / width subtyping |
| **Refined** | Base checker + predicate contracts (`{ check; message; }`); base verified first, then predicates single-pass. `refinements` = `tcpPort`/`nonEmpty`/`positive`. | Rondon 2008 (Liquid Types); Findler 2002 |
| **strict** | `strict knownNames` — the pure-checking form of closed-world key rejection (was `mkStrictModule`'s freeform throw). | structural width closure |
| **Validators** | `mkValidator`/`runValidators`/`formatErrors`/`defaultOnError` — named predicate contracts over a kind's instances → `Either`. | Findler 2002 (blame) |
| **Intensional Identity** | `__id` = sha256 of the type name; two checkers are equal iff names agree (name-only ceiling — no closure/structural comparison). `typeEq`/`intensionalEq`. | Palmer 2024 §2.3 |
| **Frugality** | Happy path = single pass (`all` short-circuits); failure re-scans only to locate the first offender; structs allocate no intermediate attrset on success. | design requirement |

### gen-merge — Byte-Mode Merge Engine

The merge half of the pure-gen module system. `evalModuleTree` reproduces `lib.evalModules` + `lib.types`-merge output byte-for-byte on den's surface, with zero nixpkgs. `nixpkgs.lib`-free (Class B: gen-prelude; injects gen-types as `types`).

| Term | Definition | Provenance |
|------|-----------|------------|
| **evalModuleTree** | The engine. One call = one `lib.evalModules` = one local `prelude.fix`. `{ modules; specialArgs?; check?; prefix?; } → { config; options; type; }`. | nixpkgs `mergeModules'` |
| **The 7-item primitive** | The surface den's grammar/registry reduces to: typed options+defaults; freeform `lazyAttrsOf`/`attrsOf`; per-key `name`+`_module.args`; the self-ref `config` fixpoint; `imports` collection; the `(loc,defs)` custom-merge hook; `deferredModule` as tagged lazy data (`functionTo` omitted). | design spec §1 |
| **mergeDefs** | The shared fold: discharge properties → filter overrides (min-priority wins) → dispatch to `type.merge` (structural) or `mergeLeaf` (scalar) → `verify` at the leaf. The `(loc, defs)` contract the whole engine rides. | nixpkgs `type.merge` |
| **Priority subset** | ONE override rule (lowest priority-number wins; ties merge) over `mkForce`(50)/bare(100)/`mkOverride N`/`mkDefault`(1000)/`mkOptionDefault`(1500), plus `mkMerge`/`mkIf`. Priority numbers match nixpkgs exactly. | design spec §7 (grepped, closed) |
| **Dropped ORDER pass** | The nixpkgs order pass (`mkOrder`/`mkBefore`/`mkAfter`) and exotic named overrides are deliberately absent — zero uses on the surface. Equal-priority defs merge in reverse module order (byte-identical to nixpkgs-without-`mkOrder`). | design spec §7 |
| **Structural strategies** | The merge-bearing types (`submodule`/`listOf`/`attrsOf`/`lazyAttrsOf`/`deferredModule`/`nullOr`/`either`/`oneOf`/`raw`/`anything`) — each carries `.merge loc defs`. Leaf checkers come from gen-types. | nixpkgs `lib.types` |
| **types namespace** | `genMerge.types` = gen-types leaf checkers ⊎ gen-merge strategies — the `lib.types` drop-in the re-host points at (`lib.types.X → genMerge.types.X`). | — |
| **Nested option paths (#16)** | `options.a.b.c = mkOption {…}` builds a nested option TREE; a second module's `options.a.b.d` recurses beside it; leaf/group collision throws; undeclared-key check is per group level. | nixpkgs `mergeOptionDecls` |
| **Path-leaf import (#20)** | A bare path in the module list is `import`ed and re-entered (and a path inside `imports` too) — enables `(import-tree dir).files` fed straight to `evalModuleTree`. | nixpkgs path-module import |
| **deferredModule** | A lazy, import-usable module value, NEVER forced by composition — handed opaque to the terminal (the two-plane invariant). | Lorenzen 2025 §2.3 |
| **Byte-identity oracle** | `ci/tests/oracle.nix`: `evalModuleTree.config == lib.evalModules.config` on parameterized fixtures, with mutation-teeth (an oracle that can't fail is decorative). | design spec §3 |
| **Swappable kernel** | The per-option combine is a parameter; byte-mode passes the nixpkgs-faithful kernel. The deferred structural mode later swaps a confluent-join kernel without changing the engine skeleton. | design spec §6/§8 |

### gen-schema — Typed Record Registries

Typed record registries with extension, validation, introspection, and scope-graph bridge. Re-hosted onto gen-merge + gen-types (`lib/` is nixpkgs-lib-free); takes `{ prelude, merge, algebra }`.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Kinds** | Schema-level type declarations. Deferred modules defining options and config. | — |
| **Instances** | Concrete values of a kind, evaluated through `mkInstanceRegistry`. | — |
| **Instance Registry** | `attrsOf` instance type with apply pipeline (validate → derive → apply). | — |
| **Extension** | Any module can extend any kind. Extensions merge through deferred module merge. | — |
| **Base Module** | Module injected into every kind automatically. Static, set at `mkSchemaOption` call time. | — |
| **Collections** | Named data fields extracted from kind definitions before module merge, exposed on result. Built-in: `methods`, `validators`. | Van Wyk 2010 (Silver collection attributes) |
| **Computed Fields** | Derived values computed from collection content and raw definitions. | — |
| **Refs** | Cross-registry references between kinds. Two modes: deferred (bound at registry time) and direct (resolved immediately). | — |
| **Deferred Ref** | Ref declared on the kind (as string), bound to a concrete registry via `refs` on `mkInstanceRegistry`. | — |
| **Direct Ref** | Ref resolved immediately when the target registry is in scope. | — |
| **Deferred Coerce** | Self-referential ref resolution deferred to apply pipeline. 3-arg coerce hook receives raw instances. | — |
| **Set** | Deduplicated list by `id_hash`, preserving first-seen order. `setOf` and `toSet`. | — |
| **Methods** | Declarative functions on entity instances. Named args auto-resolved from instance config. `schemaFn`. | — |
| **Topology** | Parent-child relationships between kinds. `_topology`, `_roots`, `_leaves`. | — |
| **Introspection** | Flat `_`-prefixed read-only options for programmatic access: `_kindNames`, `_edges`, `_kindMeta`, `_refEdges`. | — |
| **Refinement** | Predicate co-located with a type declaration. Validated during apply pipeline. `schema.types.refined`. | Rondon 2008 (Liquid Types); Findler 2002 |
| **Blame** | Field-level error attribution for contract violations. `schema.blame`. | Findler 2002 |
| **Mixin (schema)** | Reusable schema fragment with `requires`/`provides` fields and structural compatibility. `schema.mkMixin`. | Bracha & Cook 1990 |
| **Derive** | Post-evaluation enrichment hook on registries. Runs after validation. | — |
| **mkType** | Pluggable entry type parameter on `mkSchemaEntryType`. Allows downstream libraries to define schema-backed types with custom submodule structure. | — |
| **Emit Module** | Bridge from record-algebra records to NixOS modules. `schema.emitModule`. | Cardelli 1997 |

### gen-aspects — Aspect Type System

Aspect type system with gen-schema integration. Traits, classification, identity, schema-backed registries. Re-hosted onto gen-merge + gen-schema (`lib/` is nixpkgs-lib-free); takes `{ prelude, merge, schema }`. The grammar (`types.nix`) produces the aspect node set without `lib.evalModules`; `aspectType`'s Palmer one-type-dispatch-in-merge rides gen-merge's `mkOptionType { merge }`.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Aspects** | Submodules with structural identity and freeform content. Composable configuration units. | Batory 2005 (AHEAD feature algebra) |
| **Traits** | The aspect type: one type, dispatch in merge. Attrsets and module functions → submodule; guard functions → `functionTo` wrapper. | Palmer 2024 (intensional functions); den interpretation of §5.1 |
| **Classes** | Registered output targets (NixOS, darwin, homeManager). Explicit `deferredModule` options. Content exits the scope graph into external evaluation. | Tarr 1999 (multi-dimensional separation of concerns; "hyperspace" terminology from Ossher & Tarr 2001) |
| **Classification** | `canTake`: determines if a function is a module-fn (evaluated immediately) or guard-fn (deferred). | Palmer 2024 |
| **Guard Functions** | Context-dependent aspects: `{ host, ... }: { nixos = ...; }`. Detected via `canTake`, wrapped via `functionTo` (tagged, still-callable functors — analogy to, not implementation of, defunctionalization). | Palmer 2024 (intensional reflection); Reynolds 1972 §6 (analogy) |
| **Module Functions** | Functions evaluated immediately by the submodule: `{ config, ... }: { ... }`, `{ aspect, ... }: { ... }`. | — |
| **Identity (aspect)** | Program-point identity from `key`, `aspectPath`, `pathKey`. Powers diamond dedup. | Palmer 2024 §2.2 |
| **Includes** | Forward I edges — outbound composition references between aspects. | Neron 2015 |
| **neededBy** | Reverse I edges — inbound injection declarations. Static, not inside parametric bodies. | Inspired by JastAdd's aspect-oriented extension (Hedin 2003); reverse-edge semantics are den-specific |
| **Configuration (cnf)** | Hooks: `classes`, `moduleArgs`, `aspectModules`, `metaModules`. Consumer provides these to customize aspect behavior. | — |
| **Nested Aspects** | Non-structural, non-class keys on an aspect become sub-aspects with their own identity. | — |
| **mkAspectSchema** | Schema-backed aspect registry using gen-schema's `mkType`. Integrates aspect types into gen-schema's kind/instance/validation infrastructure. | — |
| **Flatten** | Recursive aspect tree → flat registry by path identity. Collapses nested aspect hierarchies into a single-level attrset keyed by path. | — |
| **Key Classification** | Trifecta: class key (registered class → module fragment), collection key (registered collection → data), nested key (unregistered → sub-aspect). | — |

### gen-scope — HOAG Evaluator

Demand-driven Higher-Order Attribute Grammar evaluator over algebraic scope graphs.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Nodes** | Minimal descriptors: `{ id, type, parent, decls }`. | Neron 2015 |
| **Roots** | Entry-point nodes. Provided to `eval` directly or built via `buildNodes`. | — |
| **Children** | Synthesized nodes produced by the `children` attribute. HOAG: tree structure is a computable attribute. | Vogt 1989 |
| **Derived Children** | Second-stage synthesized nodes from `derived-children`. Can read sibling attributes. | Extends Vogt 1989 NTAs (§2.4) with two-stage stratification; stratification is gen-scope's design |
| **Attributes** | Named computations on nodes. Defined in `attributes` parameter to `eval`. Memoized via `_eval`. | Knuth 1968; Sloane 2010 |
| **\_eval** | Co-located memoization cache on each node. Lazy attrset of attribute computations. | Sloane 2010 (CachedAttribute) |
| **Inherit'** | Parent-chain walker. Walks upward until `resolve` returns non-null. Cycle-safe. | Knuth 1968 (inherited attributes) |
| **InheritAll** | Accumulates values along entire parent chain. | — |
| **Circular** | Fixed-point iteration attribute. `init` → iterate `f` → converge via `eq`. | Sloane 2010; Arntzenius 2016 |
| **CollectionAttr** | Traversal-based aggregation attribute. Traverse modes: `"imports"`, `"children"`, `"siblings"`, `"ancestors"`, `"label:<name>"`, `"neron"`, or custom function. | Van Wyk 2010 (Silver collection attributes); Sloane 2010 (planned, §7) |
| **Neron Traverse** | `"neron"` traverse mode on `collectionAttr`. Collects contributions in D > I > P order — all contributions from matching scopes, complementing `query`'s single-result resolution. | Neron 2015 |
| **Query** | Neron resolution: local → imports → parent with specificity D < I < P. | Neron 2015 |
| **QueryAll** | All reachable results without shadowing. For ambiguity detection. | Neron 2015 |
| **ParamAttr** | Parameterized attribute: `f self id param`. | Sloane 2010 §3 |
| **Import Edges** | Computed attributes (`self.get id "imports"`). Stored in `decls.__edges.I`. | Hedin 2000 (RAG) |
| **Algebraic Graph** | Graph construction via four primitives: `empty`, `vertex`, `overlay`, `connect`. | Mokhov 2017 |
| **Tier 1** | Navigation: `self.node id`, `self.get id attrName` — O(1) or O(depth). | — |
| **Tier 2** | Materialization: `self.allNodes` — O(n), forces full tree. | — |
| **parseParent** | ID → parent ID function. Mandatory for fleet scale (O(depth) vs O(n) resolution). | — |
| **Selective Materialization** | `subtreeOf`, `nodesOfType`, `allNodesWhere` — constrained tree forcing. | — |
| **Shadow** | Inner shadows outer (key-based). Resolution specificity: D < I < P. | Neron 2015 |
| **Well-Formedness** | Scope graph validity. No ambiguous resolution. | Neron 2015 (WF predicate); generalized in van Antwerpen 2016 |

### gen-graph — Accessor-Based Graph Queries

Pure graph query combinators. Queries take accessor functions, not node maps.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Accessor Record** | Attrset of functions describing graph structure: `{ edges, parent, nodes, nodeData }`. | gen-graph design; callers own data, queries compose via function arguments |
| **edges** | `id → [id]` — outgoing edge targets. | — |
| **parent** | `id → id \| null` — immediate parent. | — |
| **nodes** | `[id]` — all node IDs. Required by global operations. | — |
| **nodeData** | `id → attrset` — attribute data for a node. Required by `select`. | — |
| **Traversal (lazy)** | Visits only reachable nodes. `reachableFrom`, `reachableWhere`, `canReach`, `selfReachable`, `ancestorsOf`, `pathsBetween`. | — |
| **Global Analysis** | Enumerates all nodes. `cycles`, `dependents`, `dependentsOf`, `impactOf`, `transpose`. | — |
| **Materialize** | Builds edge map `{ id → [id] }` from accessor record. One-time scan. | — |
| **Edge Map** | Materialized `{ id → [id] }` attrset. Target for set operations: `unionEdges`, `intersectEdges`, `differenceEdges`, `selectEdges`. | gen-graph design; algebraic foundation from Mokhov 2017 |
| **Transitive Closure** | Full edge map preserving all reachability. Fixpoint over `compose`. | — |
| **Transitive Reduction** | Minimal edge map preserving reachability. O(1) inner membership via attrset. | — |
| **Fixpoint (graph)** | Iterates `step` on `seed` until stable. Throws on non-monotonic steps. | Arntzenius 2016 |
| **phaseOrder** | Ordering front-door (`order.nix`): a forward producers-first order over the condensation. A cycle or self-loop throws. This is where gen-dispatch's group ordering moved; `dispatch` consumes the result as its `groupOrder :: [groupName]`. (The gen-graph function keeps the name `phaseOrder`; it is a general topological order gen-dispatch reads as a group order.) | Sloane 2010 (dependency-driven scheduling) |
| **entry\*** | Ordering constraints feeding `phaseOrder`: `entryAnywhere`, `entryAfter`, `entryBefore`, `entryBetween`. Formerly on gen-derive; now gen-graph's. | — |
| **Mock** | Test helpers: `mkGraph`, `fromNodeMap`, `fixtures` (diamond, chain, cyclic, tree, serviceGraph, disconnected). | — |

### gen-select — Selector Algebra

Pattern matching over attributed graph positions. Zero-dependency (Class A, builtins only) — intensional equality is inlined name-equality; no gen-algebra or gen-prelude dependency.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Selector** | `{ __sel = tag; ... }` attrset. Matched by `matches` against an accessor context. | CSS Selectors Level 4 |
| **Context** | Five accessor functions: `data`, `parent`, `children`, `ancestors`, `siblings`. ID is the second arg to `matches`, not in context. | Neron 2015 (scope graph traversal) |
| **Matches** | `selector → id → context → bool`. Core dispatch on `__sel` tag. | — |
| **star** | Matches everything. | CSS `*` |
| **attrs** | Matches when all k:v pairs equal in `data id`. | CSS attribute selectors |
| **entity** | Matches when the node's projected identity (`__identity.id_hash`) equals the entry's `id_hash`. Takes a registry entry — never a `"kind:name"` string. | Neron 2015 (declaration identity); gen-schema `id_hash` |
| **kind** | Matches when the node's projected kind (`__identity.kind`) equals the kind value's `kind`. Takes a gen-schema kind value. | CSS Selectors L4 §5.1 (type selector, lifted to schema kinds) |
| **and** | All selectors match. `and [] = true`. | CSS compound selectors |
| **any** | Any selector matches. `any [] = false`. | CSS `:is()` |
| **not** | Does not match. | CSS `:not()` |
| **has** | Any child matches. | CSS `:has()` |
| **within** | Any ancestor matches. | CSS descendant combinator (inverted) |
| **parentMatches** | Immediate parent matches. | CSS child combinator (inverted) |
| **child** | Sugar: `and [ c (parentMatches p) ]`. Parent-child combinator. | CSS `>` |
| **descendant** | Sugar: `and [ d (within a) ]`. Ancestor-descendant combinator. | CSS ` ` (space) |
| **when** | Programmatic escape hatch. `fn id ctx → bool`. Supports intensional identity. | — |
| **isIdentified** | True when a `when` selector wraps an intensional function. | Palmer 2024 |
| **selectorEq** | Structural equality for selectors. Delegates to `intensionalEq` for identified `when` selectors. | Palmer 2024 |
| **Adapters** | Bridges to gen-scope (`adapters.scope.mkContext`), gen-graph (`adapters.graph.mkPredicate`, `mkSelectPredicate`), a flat registry (`adapters.registry.mkContext`), and gen-product cells (`adapters.product.coord`/`inSlice`/`mkContext`). Pure structural contracts — no imports of the bridged libraries. | — |
| **\_\_identity** | The reserved record the enriched adapters project alongside node data (`{ id_hash; kind; entry; }` or `null`), off which `entity`/`kind` selectors match. A missing key is a loud identity-blind-context throw. | — |

### gen-bind — Module Binding

Inject external bindings into NixOS module functions with collision detection and lazy contracts.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Bindings** | Named external values injected into module functions via partial application. | Reynolds 1972 (closure environments and partial application) |
| **Wrapping** | Partial application of bindings into a module's args. `builtins.functionArgs` introspection determines injection targets. | Reynolds 1972 (deferred evaluation via closure inspection) |
| **Merge Strategy** | Resolution policy when a binding name collides with a module-system arg: `bind-wins`, `system-wins`, `error`. | Leijen 2005 (free extension over strict extension; scoped label selection) |
| **Thunk** | Config-dependent deferred value. `{ __configThunk = true; __fn = fn; }`. Resolved inside `evalModules` when `config` is available. | — |
| **Contract** | Lazy assertion on a binding value. Checked on demand, not at wrap time. `contract.mk`, `contract.hasFields`, `contract.isType`, `contract.nonEmpty`. | Chitil 2012 (lazy contracts) |
| **Provenance** | Source-tracking metadata surfaced in blame messages. `{ source; scope?; }`. | Findler 2002 (blame tracking) |
| **Signature** | Static record: `{ requires, bound, unsatisfied, mergeStrategies }`. Describes a module's binding interface. | Cardelli 1997 (linksets) |
| **Compose** | Left-fold `//` across binding attrsets. Later layers shadow earlier ones. | — |
| **ComposeWith** | Structured merge across all four binding fields (bindings, provenance, contracts, mergeStrategies). | — |
| **Identity Wrapping** | Stamps a stable NixOS module `key` onto a wrapped module for evalModules dedup. `wrapIdentity`. | Cardelli 1997 |
| **Arg Stripping** | Removes bound arg names from a module's advertised formal args. Prevents `evalModules` from probing `_module.args` for bound names. | — |
| **Module Shapes** | Three shapes: function (`{ arg, ... }: { ... }`), imports attrset (`{ imports = [...]; }`), plain attrset (`{ config = ...; }`). | — |

### gen-dispatch — Relational Rule Dispatch STEP

Pure relational rule dispatch — **rule evaluation only**, a function of `(rules, context)`. It is deliberately just the **step**: it does *not* own the convergence loop (that is gen-resolve, via `gen-scope.circular`) and does *not* sort groups (that is gen-graph's `phaseOrder`). Depends only on gen-prelude. (Renamed from gen-derive; a GitHub redirect keeps old refs resolving.)

| Term | Definition | Provenance |
|------|-----------|------------|
| **Rule** | Guarded transformation unit: condition + action producer + identity. | Forgy 1982 (RETE); Ehrig 2006 |
| **Condition** | Predicate determining when a rule fires. Opaque in core — caller provides `match`. | Forgy 1982 (RETE LHS) |
| **Action** | Opaque tagged value produced when a rule fires. Caller provides `classify` to route to groups. | Forgy 1982 (RETE RHS) |
| **Group** | Named dispatch stratum (the leaked den-ism "phase", renamed). Ordering is supplied externally: `dispatch` takes a pre-ordered `groupOrder :: [groupName]` (from gen-graph's `phaseOrder`/`entry*`) and does not sort internally. | Classical Datalog stratification; monotonicity from Arntzenius 2016 |
| **Match** | Testing a condition against a position: `condition → id → ctx → bool`. | Ehrig 2006 (match morphism) |
| **Dispatch** | One-shot pure step: fire matching rules over the caller-supplied `groupOrder`, group actions by group. Result `orderedGroups` = present-only subsequence of `groupOrder`. NAC → match → override → priority → exclusive → fire → classify → group. | — |
| **Convergence (blessed pattern)** | `dispatch` is a pure function of `(rules, context)`, so a caller iterates by threading the plain domain state: the step is one one-shot `dispatch` whose output context is the next iterate, `gen-scope.circular` drives it to a fixpoint (Kleene ascent), and the actions are read off the converged context by one post-convergence dispatch. Recompute-at-fixpoint = confluence, so no cross-pass accumulator or `fired` set is threaded. (Retired: the `dispatchStep`/`dispatchInit` migration seam that carried the old fixpoint accumulator.) | Kleene ascent (Sloane 2010 §2.2); Arntzenius 2016; Radul 2009 |
| **NAC** | Negative Application Condition — pattern that must NOT match. First-class `nac` field, checked before condition. | Ehrig 2006 |
| **Override** | Rule names identities it replaces via `overrides` field. Applied before priority (unconditional suppression). | Inspired by Batory 2005 (AHEAD feature composition); override semantics are gen-dispatch's design |
| **Priority** | Numeric precedence (higher fires first). `exclusive` mode: only highest-priority group fires. | — |
| **Specificity** | Selector constraint term count. Adapter tier only, via `selectorSpecificity`. | CSS Selectors (specificity) |
| **Conflict Resolution** | Three-tier: override suppression → priority sort → specificity → additive ties. | — |
| **fromFunction** | Converts a Nix function into a rule. `builtins.functionArgs` as condition. Detects `mkIntensional`. | Palmer 2024 |
| **fromFunctionMatch** | Default match implementation for `fromFunction` rules. Checks required args present in context. | — |
| **mkActions** | Generates tagged action constructors + `classify` from group declarations. | — |
| **Rule Composition** | `restrict` (narrow condition), `override` (replace rule), `chain` (sequential: A's actions feed B). | Inspired by Batory 2005 (AHEAD feature algebra); named operations are gen-dispatch's design |
| **Adapter** | gen-select bridge: `adapters.select.mkMatch` bridges selectors as conditions; `selectorSpecificity` for conflict resolution. | — |

### gen-resolve — RAG Evaluator + Convergence Loop

Demand-driven RAG evaluator over scope graphs. Owns the **convergence loop** that the dispatch step lacks. Class B: five gen siblings (gen-scope, gen-graph, gen-rebuild, gen-algebra, gen-bind).

| Term | Definition | Provenance |
|------|-----------|------------|
| **Attribute Schedule** | Static schedule for demand-driven RAG evaluation over the scope graph. | Knuth 1968 (attribute schedule) |
| **HOAG Gate** | Higher-order gate on schedule expansion. | Vogt 1989 (HOAG) |
| **Two-Stratum Partition** | Cold/warm fold into `gen-scope.eval`: a static schedule stratum and a convergence stratum. | Knuth 1968; Vogt 1989 |
| **Convergence Loop** | The Kleene-ascent loop (`gen-scope.circular`) that drives repeated one-shot `gen-dispatch.dispatch` over the domain state to a fixpoint; actions are read off the converged context. | Sloane 2010 §2.2 (Kleene ascent) |

### gen-flake — Value-Injection Boundary

The single sanctioned crossing from the pure composition plane into nixpkgs. Its pure core (`compose`/`injectArgs`) is nixpkgs-lib-free; only the instantiated terminal (`terminals.nixosSystem`) and flake-parts module touch nixpkgs.

| Term | Definition | Provenance |
|------|-----------|------------|
| **compose** | `{ tree ? null; modules ? []; specialArgs ? {}; } → { values; classContent; hostContent; }`. Loads a gen module tree (a bare path list via the import-tree fork) and resolves it PURELY via `gen-merge.evalModuleTree`. | — |
| **values** | The resolved fixpoint config (`result.config`): instances, `id_hash`, resolved refs, flattened surfaces. The injection payload — VALUES, not types. | — |
| **classContent** | `genAspects.flatten values.aspects` — the flat aspect registry keyed by path; each entry carries per-class `deferredModule` fields, unforced. The query surface. | — |
| **hostContent** | The per-host `(class, host)` projection: `{ <host> = { bindings = { host = <instance>; }; classes = { <class> = [ deferredModule ]; }; }; }`, driven by each host's `aspects` membership. The build surface. | — |
| **injectArgs** | `composed → { _module.args.genValues = composed.values; }`. Packages resolved VALUES as a plain query module — pure, no gen type crosses. | — |
| **genValues** | The injected arg name — the resolved config values a consumer's nixpkgs modules query (`{ genValues, ... }: … genValues.hosts.<h>.addr …`). | — |
| **realize** | `{ composed; terminals; bindings ? {}; extraModules ? {}; } → { <class> = { <host> = <built>; }; }`. The terminal DRIVER, not the binder: the class-major fold selects each host's class modules, merges the three binding layers (`hc.bindings // bindings // bindings.<host>`), knot-ties the `nodes` accessor to the class's own result set, and calls the terminal. It partial-applies nothing itself — `wrapAll` runs one level down, in the terminal. Output keys are exactly the `terminals` keys. | — |
| **mkSystemTerminal / nixosSystem** | `mkSystemTerminal { evaluator }` is the GENERIC system terminal — no system class named, no nixpkgs touched. **This is where the binding happens**: `genBind.wrapAll { modules; bindings; }`, then `evaluator { modules = wrapped.all ++ extraModules; specialArgs = { inherit nodes; }; }` (`gen-flake/lib/terminals.nix:mkSystemTerminal`; gen-bind is threaded ONLY into that file). `terminals.nixosSystem { nixpkgs; }` is it instantiated with `nixpkgs.lib.nixosSystem`, and is the ONE place that touches nixpkgs; `mkFlakeTerminal` is the flake-parts crossing beside it. | Reynolds 1972 (partial application) |
| **mkSystems** | **RETIRED (v0).** The former terminal, `{ hostContent; nixpkgs; extraModules ? {}; } → { <host> = nixosSystem; }`. It is absent from `gen-flake/lib/`, not renamed; the v1 replacement is `realize { composed; terminals.nixos = terminals.nixosSystem { nixpkgs; }; extraModules; }`, and `composed.hostContent` became `composed.hosts`. Retained here only so the v0 name resolves to its successor. | — |
| **nodes** | The colmena-style cross-terminal accessor in the system terminal's specialArgs — the whole set of built systems, lazy (`nodes.<peer>.config.…`). | — |
| **flakeModules.default** | Flake-parts ergonomics: one `imports` gives the injected query surface (top-level + `perSystem` args) and `flake.nixosConfigurations` from one compose. `options.gen = { tree; modules; specialArgs; inject; nixpkgs; extraModules; composed; }`. | — |
| **The invariant** | gen TYPES never leave the pure eval; only VALUES cross. A gen type rides as inert data in `_module.args` (`genValues.schema.<kind>.options.<f>.type.name` is a readable string) yet never enters a consumer's options tree (`nixosConfigurations.<h>.options ? schema == false`), so nixpkgs never type-walks it. | value-injection; adios prior art |
| **Reader escape hatch** | For shapes the shipped terminals do not fit (multi-target/terranix, nested `fleet.hosts`, reader-computed bindings): use `compose`/`injectArgs` for the pure values and keep your own terminal reading `genValues`, or hand your own evaluator to `mkSystemTerminal`. | — |

*The five libraries below are nixpkgs-lib-free (Class B) L2 concern libraries built on the L1 substrate — each pins one algebra a configuration framework assembles with, and all five are hub-wired via `mkGenLibs` (keys `edge`, `product`, `settings`, `demand`, `pipe`).*

### gen-edge — Content-Movement Contract

The `(S,T,P,M)` edge algebra: everything that moves content between graph positions is an edge. Depends on gen-prelude + gen-graph.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Edge `(S,T,P,M)`** | A content-movement record: source, target, attr**p**ath, **m**ode. The only thing that moves content between positions. | edge algebra |
| **Source (S)** | Where content comes from: `collected` (a channel bucket of a subtree), `synthesize` (adapter-built), `value`/`keyedValue` (direct), `rewalk` (legacy). | — |
| **Target (T)** | Where content goes: `root { root, class }` (an instantiation root) or `output` (a terminal flake-output sink). | — |
| **Mode (M)** | Closed enum `merge` / `nest` / `nest-verbatim`. Apparent hybrids decompose into edge composition (`nest ∘ merge`). | — |
| **edgesFor** | The complete edge set of a root: one default-fold merge edge per channel in the resolved isolation-bounded subtree, plus every declared edge targeting the root. | default-fold-by-construction |
| **toposort** | Kahn's algorithm over the accumulator dependency relation (edge B depends on A iff B reads a cell A writes). Incomparable edges emit in frozen sort-key order; cycles abort loudly. | Kahn 1962 (A. B. Kahn, topological sort) |
| **materialize** | THE fold: one left fold over the ordered edge list, seeded from the projection Π, dispatching on the single mode switch. Produces the per-root/per-channel content map. | — |
| **trace `E`** | The normalized, stably-sorted, hashable edge trace. Renders edge identities and never forces resolved content — a cross-repo structural parity oracle. | — |
| **Content inertness** | Construction (`edgesFor`/`toposort`/`trace`/`project`) forces no bucket content — only structural accessors and channel presence; resolved values enter solely through `materialize`. | HOAG r2 §B2 |

### gen-product — Graph Products

The four standard graph products over gen-graph accessor-graphs. Depends on gen-prelude (consumes the gen-graph accessor convention and gen-schema `id_hash` shape structurally).

| Term | Definition | Provenance |
|------|-----------|------------|
| **Product** | An accessor-graph over ordered factor specs, extended with product metadata. `productN kind factors`; a product is itself a factor of other products. | Hammack, Imrich & Klavžar 2011 |
| **Product kinds** | `cartesian` (□), `tensor` (×), `strong` (⊠), `lexicographic` (∘) — standard definitions applied coordinatewise to directed adjacency. | Hammack et al. 2011 (Part I) |
| **Factor spec** | `{ dim; graph; key ? }` — a named dimension whose coordinates are registry entries (default key `e: e.id_hash`). | — |
| **Cell** | A full coordinate `{ <dim> = entry; … }`; the id gen-graph queries take. `cell` / `coordsOf` / `cells` (lazy row-major enumeration). | — |
| **slice / fiber / projectTo** | Induced sub-product over remaining dims; preimage of a projection; factor graph + projection metadata. | Hammack et al. 2011 (layers/projections) |
| **restrict** | Sparse sub-product over a membership relation — the real, non-dense fleet (not every coordinate exists). | — |
| **quotient** | Class-share as a quotient of a graph by a class map; generalizes gen-graph's condensation quotient. | Mokhov 2017 |
| **containmentChain** | The specificity lattice for a cell under a linearization — an ordered layer list (consumed downstream as settings layers). | — |
| **Lazy in, lazy out** | Adjacency, addressing, slices, and chains are pointwise — they never scan a factor's `nodes` (documented `en-masse` exceptions aside). | Kahn 1974 (via gen-graph) |

### gen-settings — Stratified Settings Resolution

Settings resolution as a pure layered fold with provenance, refs, and injection. Depends on gen-prelude + gen-algebra + gen-bind; gen-schema interface-only.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Settings schema** | `mkSchema { aspect; fields; }` — bare-key `{ default; merge ? }` leaves, always introspectable. `merge ∈ { replace, append, recursive }`. | — |
| **Layer** | `{ scope; rendered; via; value; }` — a partial contribution keyed by registry-entry scope; the ordered list is least → most specific. | — |
| **Layered fold** | Positional last-wins (`replace`) / accumulation (`append`/`recursive`); byte-identical to gen-algebra's `foldLayers` (the Spike 5 gate). Authority is positional — no strength lattice. | gen-algebra `foldLayersTraced`; Leijen 2005 |
| **Lattice-blind** | The layer order arrives precomputed; gen-settings never reorders, dedups, or filters it. | — |
| **Ref as data** | `ref aspectEntry [path]` — an identity-bearing cross-aspect reference, inert data (no thunks), so the dependency graph is statically computable (`refGraph`). | Mokhov et al. 2018 (applicative task deps) |
| **Static ref graph** | Conservative over pre-fold values, structurally strict; definition-time cycle detection (E3) names every address in a cycle. | Mokhov et al. 2018 §3 |
| **Structured provenance** | Per-field ordered chain `{ scope; rendered; via; value; refs; }`; per-entry lazy ref substitution (forcing one entry never resolves another's refs). | Cheney et al. 2009 |
| **Injection** | `injectAspectSettings` routes class content through gen-bind `wrap` (namespaced `settings.<key>.<field>`); `assembleHost` keys modules by `id_hash` pairs. | Cardelli 1997; Chitil 2012 (via gen-bind) |

### gen-demand — Typed Demand Cascade

A terminating, stratified demand cascade over a downward-only kind DAG. Depends on gen-prelude + gen-graph; gen-select optional.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Demand** | A typed unit of work emitted by a graph node; the subject is a registry entry. The multiset **grows during resolution**. | — |
| **Kind** | A registered resolver: `resolve d ctx → { resources; wiring; demands }`. `below` declares the sub-demands it desugars into (a downward-only DAG). | — |
| **depth / stratum** | Per-kind `depth` = `0` for a leaf else `1 + max` over `below`; `resolveAll` runs `maxDepth + 1` strata top-down. | Apt, Blair & Walker 1988 (stratified evaluation) |
| **Termination theorem** | Every `below` edge strictly decreases depth, so the cascade quiesces in ≤ DAG-depth rounds — no cap, no convergence loop. | well-founded (Noetherian) recursion on ℕ |
| **Emission ⊥ consumption** | A resolver sees only the demand's own fields plus static `ctx` — no accumulator, no already-resolved view. The eval-cycle failure mode is unexpressible. | HOAG r2 §B5 |
| **Resources / wiring / sub-demands** | Provider-side artifacts; consumer-side splice data; lower-level demands a composite desugars into. All opaque to the engine. | — |
| **Pinned-order dedup** | Grouped fragments fold in schedule order; undeclared duplication is a loud resource-key collision, never silent last-wins. | — |
| **Trace** | Witness + derivation provenance (each artifact ↦ producing demand instances, with parent chains to roots). | Cheney, Chiticariu & Tan 2009 |

### gen-pipe — Scoped-Channel Dataflow

Content-agnostic dataflow algebra for scoped channels. Depends on gen-prelude + gen-select + gen-scope.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Channel** | A typed, named accumulation lane; its value at a position is a deterministic fold over the contributions visible there. | — |
| **Determinism as law** | Pinned traversal (self → imports → parent) + associative-only combine; no silent reorder or dedup. Determinism is **not** KPN (channels have multiple writers). | Kahn 1974 (informed-by, caveated); HOAG r2 §B5 |
| **Operators** | `map`, `filter`, `fold`, `scan`, `route`, `join`, `tee` — connect channels into a dataflow DAG, validated at composition time, evaluated demand-driven. | — |
| **route / tee / join** | Selector-matched delivery edges (`route`), fan-out (`tee`), and fan-in (`join`); routing predicates are gen-select selectors. | — |
| **Provenance as data** | Every contribution carries its producer as structured registry-entry identities (entity, scope, aspect); operators extend the chain. | Cheney et al. 2009 |
| **Class as type** | Contributions are class-tagged at emission; a deferred value's `config` means the producing class's config at the producing scope; cross-class consumption needs a declared adapter. | — |
| **classInvariant** | A static config-dependence flag derived from arg-shape and composed through operators at composition time — never runtime discovery. | — |
| **Two-stratum discipline** | gen-pipe reads the graph and produces plain data; no output can feed graph structure (sound reading of an under-construction scope graph). | van Antwerpen et al. 2016 (Statix, via HOAG r2 §B2) |

______________________________________________________________________

## Den v2 Vocabulary (Consumer)

Den wires the gen libraries with domain-specific semantics. These terms are den-specific, not part of gen.

### Structural (building the graph)

| Term | What it does |
|------|-------------|
| `spawn "kind" { bindings }` | Create scope node with P edge to parent |
| `enrich { key = val }` | Add declarations to current scope |
| `emit entityCfg` | Wire entity into output configurations |

### Resolution (operating on the graph)

| Term | What it does |
|------|-------------|
| `edge aspect` | Add I edge: current scope → aspect node |
| `drop aspect` | Constraint: prune aspect from resolution |
| `reroute { from, to }` | Redirect class content between classes |
| `inject { class, module }` | Direct emission into class output |

### Composition (aspect-declared edges)

| Term | What it does |
|------|-------------|
| `includes = [ ... ]` | Forward I edges (outbound composition) |
| `neededBy = [ ... ]` | Reverse I edges (inbound injection) |
| `meta.guard = pred` | Conditional edge activation |
| `meta.drop = [ ... ]` | Subtree constraint declaration |
| `meta.substitute = { X = Y; }` | Edge target replacement |

### Collections (named data aggregation)

| Term | What it does |
|------|-------------|
| `den.collections.X = { ... }` | Declare a named collection |
| `pipe.from "X" [stages]` | Route collection data |
| `pipe.gather pred` | Traverse and collect from matching scopes |
| `pipe.ascend` | Collection data flows up P edge |
| `pipe.source pred` | Filter: only matching scopes contribute |
| `pipe.target [aspects]` | Delivery: only these aspects receive |
| `pipe.channel "Y"` | Redirect to different collection |

______________________________________________________________________

## Classes: The Output Dimension

Classes are orthogonal to collections. They represent the OUTPUT boundary — where computation leaves the scope graph and enters external evaluation.

| Concept | What flows | Where it goes | Consumer | Merge semantics |
|---------|-----------|---------------|----------|-----------------|
| **Collections** | Data values | Internal: stays in graph | Other aspects (as module args) | Merge strategy (++, //, custom) |
| **Classes** | Module fragments (deferredModule) | External: leaves the graph | Output system (nixosSystem, darwinSystem, etc.) | evalModules |

In AG terms, classes are the **terminal attributes** — the final synthesized output of the grammar (Knuth 1968: "the translation"). In Tarr (1999) terms, classes are the **dimensions** in multi-dimensional separation of concerns.

### The Key Classification Trifecta

```
Aspect key → classified as:
  ├── class key (registered in den.classes)          → module fragment → external eval
  ├── collection key (registered in den.collections) → data value → internal routing
  └── nested key (unregistered)                      → sub-aspect → recurse
```

______________________________________________________________________

## Cross-Cutting Patterns

### Accessor Pattern

Used consistently across gen-scope, gen-graph, and gen-select. Callers provide functions describing their data; libraries query through these functions without storing state.

| Library | Accessor shape | Pattern |
|---------|---------------|---------|
| gen-scope | `{ node, get }` returned by `eval` | Memoized attribute access |
| gen-graph | `{ edges, parent, nodes, nodeData }` | Structural graph queries |
| gen-select | `{ data, parent, children, ancestors, siblings }` | Pattern matching context |

gen-select's `adapters.scope.mkContext` bridges gen-scope → gen-select context. gen-select's `adapters.graph.mkPredicate` bridges gen-select → gen-graph predicates. gen-scope's `_eval` memoization is the performance backstop for accessor calls from gen-graph.

### Intensional Identity

Consistent across gen-algebra (foundation), gen-aspects (aspect identity), gen-dispatch (rule dedup), and gen-select (selector equality).

| Library | Creates | Compares | Uses |
|---------|---------|----------|------|
| gen-algebra | `mkIntensional name closure fn` | `intensionalEq a b` | Search continuation dedup |
| gen-aspects | `key`, `aspectPath`, `pathKey` | — | Diamond dedup in fold-based collect |
| gen-dispatch | `fromFunction` detects `mkIntensional` | Rule identity dedup across loop iterations (loop driven by gen-resolve) | Convergent dispatch |
| gen-select | `sel.when` detects intensional via three-field check | `selectorEq` delegates to `intensionalEq` | Selector equality |

### Fixpoint Convergence

Fixpoint loops appear at several levels, each with domain-appropriate semantics:

| Library | Entry point | Monotonicity | Dedup |
|---------|------------|-------------|-------|
| gen-algebra (search) | `converge` | Index keys grow monotonically | Intensional continuation dedup |
| gen-graph | `fixpoint { seed, step }` | Edge count must not shrink (throws) | Edge map equality |
| gen-scope | `circular { init, f, eq }` | Attribute values converge under `eq` | `_eval` memoization |
| gen-resolve | `gen-scope.circular` over one-shot `dispatch` | Context widens monotonically | Actions are a function of the converged context (confluence) |

### Lazy Evaluation Contracts

| Library | Pattern | Provenance |
|---------|---------|------------|
| gen-schema | `schema.types.refined` — predicates co-located with types, `lazy = true` defers to access | Chitil 2012; Rondon 2008 |
| gen-bind | `contract.mk` — assertions fire only when bound value demanded | Chitil 2012 |
| gen-aspects | `deferredModule` — class content as lazy constructor, inspectable before forcing | Lorenzen 2025 §1-2.3 |

______________________________________________________________________

## Academic References

| Author(s) | Year | Paper | Gen ecosystem usage |
|-----------|------|-------|-------------------|
| Knuth | 1968 | Semantics of context-free languages | Attributes (inherited, synthesized) |
| Reynolds | 1972 | Definitional interpreters for higher-order programming languages | Defunctionalization-by-analogy (gen-aspects guard wrapping — functor, arrow retained), closure environments §5 (gen-bind partial application, gen-flake `terminals.mkSystemTerminal` binding via `wrapAll`) |
| Kahn | 1974 | Semantics of a simple language for parallel programming | Deterministic dataflow, named channels |
| Bracha & Cook | 1990 | Mixin-based inheritance | Record mixin composition (gen-algebra), schema mixins (gen-schema) |
| Forgy | 1982 | RETE: A fast algorithm for the many pattern/many object pattern match problem | Rule dispatch (gen-dispatch) |
| Vogt et al. | 1989 | Higher-order attribute grammars | Non-terminal attributes / dynamic node synthesis (gen-scope children); derived-children extends this |
| Cardelli | 1997 | Program fragments, linking, and modularization | Module signatures (gen-bind), NixOS module bridge (gen-schema) |
| Hedin | 2000 | Reference attributed grammars | Cross-node import edges (gen-scope) |
| Findler & Felleisen | 2002 | Contracts for higher-order functions | Blame tracking (gen-bind, gen-schema); the checker-as-boundary and post-merge leaf `verify` (gen-types, gen-merge) |
| Hedin & Magnusson | 2003 | JastAdd — an aspect-oriented compiler construction system | Demand-driven AG evaluation, aspect-oriented modular extension (inspires neededBy) |
| Batory | 2005 | Feature-oriented programming and the AHEAD tool suite | Feature algebra (inspires gen-dispatch rule composition), aspects as features |
| Leijen | 2005 | Extensible records with scoped labels | Record algebra (gen-algebra), merge resolution (gen-bind) |
| Ehrig et al. | 2006 | Fundamentals of algebraic graph transformation | Graph rewriting rules, NACs (gen-dispatch) |
| Rondon et al. | 2008 | Liquid Types | Refinement predicates (gen-schema, gen-types) |
| Radul & Sussman | 2009 | Art of the propagator | Monotonic convergence / quiescence (gen-dispatch, gen-graph) |
| Berry & Boudol | 1990 | The chemical abstract machine | Rules as reactions (gen-dispatch) |
| Sloane et al. | 2010 | A pure embedding of attribute grammars (Kiama) | Attribute combinators, CachedAttribute, paramAttr, circular attributes (gen-scope); collection attributes planned (§7) |
| Van Wyk et al. | 2010 | Silver | Forwarding, collection attributes |
| Chitil | 2012 | Practical typed lazy contracts | Lazy contracts (gen-bind, gen-schema) |
| Neron et al. | 2015 | A theory of name resolution | Scope graphs, P/I edges, resolution (gen-scope, gen-select) |
| van Antwerpen et al. | 2016 | A constraint language for static semantic analysis based on scope graphs | Constraint-based scope graph resolution, well-formedness generalization |
| Arntzenius & Krishnaswami | 2016 | Datafun | Monotonic fixpoint with typed guarantees (gen-dispatch, gen-graph); group stratification inspired by classical Datalog |
| Mokhov | 2017 | Algebraic graphs with class | Graph construction primitives (gen-scope); algebraic foundation for gen-graph |
| van Antwerpen et al. | 2018 | Scopes as types (introduces Statix) | Custom edge labels, structural subtyping, Statix DSL (gen-scope) |
| Palmer et al. | 2024 | Intensional functions | Program-point identity, conservative equality, search monad (gen-algebra, gen-aspects, gen-dispatch, gen-select) |
| Lorenzen et al. | 2025 | First-order laziness | Lazy constructors inspectable before forcing, §1-2.3 (gen-aspects/gen-merge deferredModule) |
| Tarr et al. | 1999 | N degrees of separation | Multi-dimensional separation of concerns (classes as dimensions) |
| Kiczales et al. | 1997 | Aspect-oriented programming | Cross-cutting concerns, aspect weaving (conceptual ancestor; "pointcut"/"advice" terminology from later AspectJ) |
| Apel et al. | 2009 | An overview of feature-oriented software development | Feature-oriented decomposition |
| Thum et al. | 2014 | Analysis strategies for software product lines | Feature interaction detection |
| Kahn, A. B. | 1962 | Topological sorting of large networks | Accumulator-DAG toposort (gen-edge) — distinct from Gilles Kahn 1974 |
| Apt, Blair & Walker | 1988 | Towards a theory of declarative knowledge | Stratified bottom-up evaluation, stratum-local aggregation (gen-demand) |
| Cheney, Chiticariu & Tan | 2009 | Provenance in databases: why, how, and where | Witness/derivation provenance traces (gen-demand, gen-pipe, gen-settings) |
| Hammack, Imrich & Klavžar | 2011 | Handbook of Product Graphs (2nd ed.) | Four standard graph products, projections/layers (gen-product; gen-select `coord`) |
| Mokhov, Mitchell & Peyton Jones | 2018 | Build Systems à la Carte | Applicative (static) task dependencies (gen-settings `refGraph`) |
