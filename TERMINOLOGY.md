# gen Ecosystem Terminology

A consistent vocabulary grounded in academic literature, spanning the gen libraries and the den framework that consumes them.

## Table of Contents

- [Design Principles](#design-principles)
- [Core Terms](#core-terms)
- [Per-Library Vocabulary](#per-library-vocabulary)
  - [gen-prelude](#gen-prelude--pure-utility-base)
  - [gen-algebra](#gen-algebra--pure-primitives)
  - [gen-schema](#gen-schema--typed-record-registries)
  - [gen-aspects](#gen-aspects--aspect-type-system)
  - [gen-scope](#gen-scope--hoag-evaluator)
  - [gen-graph](#gen-graph--accessor-based-graph-queries)
  - [gen-select](#gen-select--selector-algebra)
  - [gen-bind](#gen-bind--module-binding)
  - [gen-dispatch](#gen-dispatch--relational-rule-dispatch-step)
  - [gen-resolve](#gen-resolve--rag-evaluator--convergence-loop)
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

______________________________________________________________________

## Per-Library Vocabulary

### gen-prelude — Pure Utility Base

The nixpkgs-lib-free substrate. Re-exports of `builtins` plus a vendored set of `lib` utilities, with zero dependency on nixpkgs. gen-scope, gen-graph, gen-select, gen-bind, gen-dispatch, and gen-rebuild are all built on it (Class B), which is what makes them nixpkgs-lib-free.

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

### gen-schema — Typed Record Registries

Typed record registries with extension, validation, introspection, and scope-graph bridge.

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

Aspect type system with gen-schema integration. Traits, classification, identity, schema-backed registries.

| Term | Definition | Provenance |
|------|-----------|------------|
| **Aspects** | Submodules with structural identity and freeform content. Composable configuration units. | Batory 2005 (AHEAD feature algebra) |
| **Traits** | The aspect type: one type, dispatch in merge. Attrsets and module functions → submodule; guard functions → `functionTo` wrapper. | Palmer 2024 (intensional functions); den interpretation of §5.1 |
| **Classes** | Registered output targets (NixOS, darwin, homeManager). Explicit `deferredModule` options. Content exits the scope graph into external evaluation. | Tarr 1999 (multi-dimensional separation of concerns; "hyperspace" terminology from Ossher & Tarr 2001) |
| **Classification** | `canTake`: determines if a function is a module-fn (evaluated immediately) or guard-fn (deferred). | Palmer 2024 |
| **Guard Functions** | Context-dependent aspects: `{ host, ... }: { nixos = ...; }`. Detected via `canTake`, wrapped via `functionTo`. | Reynolds 1972 (defunctionalization) |
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
| **phaseOrder** | Ordering front-door (`order.nix`): a forward producers-first order over the condensation. A cycle or self-loop throws. This is where gen-dispatch's phase ordering moved; `dispatch` consumes the result as `phaseOrder :: [phaseName]`. | Sloane 2010 (dependency-driven scheduling) |
| **entry\*** | Ordering constraints feeding `phaseOrder`: `entryAnywhere`, `entryAfter`, `entryBefore`, `entryBetween`. Formerly on gen-derive; now gen-graph's. | — |
| **Mock** | Test helpers: `mkGraph`, `fromNodeMap`, `fixtures` (diamond, chain, cyclic, tree, serviceGraph, disconnected). | — |

### gen-select — Selector Algebra

Pattern matching over attributed graph positions. Uses gen-algebra's intensional identity; otherwise nixpkgs-lib-free (built on gen-prelude).

| Term | Definition | Provenance |
|------|-----------|------------|
| **Selector** | `{ __sel = tag; ... }` attrset. Matched by `matches` against an accessor context. | CSS Selectors Level 4 |
| **Context** | Five accessor functions: `data`, `parent`, `children`, `ancestors`, `siblings`. ID is the second arg to `matches`, not in context. | Neron 2015 (scope graph traversal) |
| **Matches** | `selector → id → context → bool`. Core dispatch on `__sel` tag. | — |
| **star** | Matches everything. | CSS `*` |
| **attrs** | Matches when all k:v pairs equal in `data id`. | CSS attribute selectors |
| **and** | All selectors match. `and [] = true`. | CSS compound selectors |
| **or** | Any selector matches. `or [] = false`. | CSS `:is()` |
| **not** | Does not match. | CSS `:not()` |
| **has** | Any child matches. | CSS `:has()` |
| **within** | Any ancestor matches. | CSS descendant combinator (inverted) |
| **parentMatches** | Immediate parent matches. | CSS child combinator (inverted) |
| **child** | Sugar: `and [ c (parentMatches p) ]`. Parent-child combinator. | CSS `>` |
| **descendant** | Sugar: `and [ d (within a) ]`. Ancestor-descendant combinator. | CSS ` ` (space) |
| **when** | Programmatic escape hatch. `fn id ctx → bool`. Supports intensional identity. | — |
| **isIdentified** | True when a `when` selector wraps an intensional function. | Palmer 2024 |
| **selectorEq** | Structural equality for selectors. Delegates to `intensionalEq` for identified `when` selectors. | Palmer 2024 |
| **Adapters** | Bridges to gen-scope (`adapters.scope.mkContext`) and gen-graph (`adapters.graph.mkPredicate`, `mkSelectPredicate`). Pure structural contracts — no imports of gen-scope/gen-graph. | — |

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

Pure relational rule dispatch. It is deliberately just the **step**: it does *not* own the convergence loop (that is gen-resolve, via `gen-scope.circular`) and does *not* sort phases (that is gen-graph's `phaseOrder`). Depends only on gen-prelude. (Renamed from gen-derive; a GitHub redirect keeps old refs resolving.)

| Term | Definition | Provenance |
|------|-----------|------------|
| **Rule** | Guarded transformation unit: condition + action producer + identity. | Forgy 1982 (RETE); Ehrig 2006 |
| **Condition** | Predicate determining when a rule fires. Opaque in core — caller provides `match`. | Forgy 1982 (RETE LHS) |
| **Action** | Opaque tagged value produced when a rule fires. Caller provides `classify` to route to phases. | Forgy 1982 (RETE RHS) |
| **Phase** | Named dispatch group. Ordering is supplied externally: `dispatch` takes a pre-ordered `phaseOrder :: [phaseName]` (from gen-graph's `phaseOrder`/`entry*`) and does not sort internally. | Classical Datalog stratification; monotonicity from Arntzenius 2016 |
| **Match** | Testing a condition against a position: `condition → id → ctx → bool`. | Ehrig 2006 (match morphism) |
| **Dispatch** | One-shot step: fire matching rules over the caller-supplied `phaseOrder`, group actions by phase. Result `orderedPhases` = present-only subsequence of `phaseOrder`. NAC → match → override → priority → exclusive → fire → classify → group. | — |
| **dispatchStep / dispatchInit** | The step paired with an external loop. `gen-scope.circular { init = dispatchInit ctx; eq; } (dispatchStep { inherit dispatch; } cfg)` (driven by gen-resolve) reproduces the old gen-derive fixpoint byte-identically. | Kleene ascent (Sloane 2010 §2.2); Arntzenius 2016; Radul 2009 |
| **NAC** | Negative Application Condition — pattern that must NOT match. First-class `nac` field, checked before condition. | Ehrig 2006 |
| **Override** | Rule names identities it replaces via `overrides` field. Applied before priority (unconditional suppression). | Inspired by Batory 2005 (AHEAD feature composition); override semantics are gen-dispatch's design |
| **Priority** | Numeric precedence (higher fires first). `exclusive` mode: only highest-priority group fires. | — |
| **Specificity** | Selector constraint term count. Adapter tier only, via `selectorSpecificity`. | CSS Selectors (specificity) |
| **Conflict Resolution** | Three-tier: override suppression → priority sort → specificity → additive ties. | — |
| **fromFunction** | Converts a Nix function into a rule. `builtins.functionArgs` as condition. Detects `mkIntensional`. | Palmer 2024 |
| **fromFunctionMatch** | Default match implementation for `fromFunction` rules. Checks required args present in context. | — |
| **mkActions** | Generates tagged action constructors + `classify` from phase declarations. | — |
| **Rule Composition** | `restrict` (narrow condition), `override` (replace rule), `chain` (sequential: A's actions feed B). | Inspired by Batory 2005 (AHEAD feature algebra); named operations are gen-dispatch's design |
| **Adapter** | gen-select bridge: `adapters.select.mkMatch` bridges selectors as conditions; `selectorSpecificity` for conflict resolution. | — |

### gen-resolve — RAG Evaluator + Convergence Loop

Demand-driven RAG evaluator over scope graphs. Owns the **convergence loop** that the dispatch step lacks. Class B: five gen siblings (gen-scope, gen-graph, gen-rebuild, gen-algebra, gen-bind).

| Term | Definition | Provenance |
|------|-----------|------------|
| **Attribute Schedule** | Static schedule for demand-driven RAG evaluation over the scope graph. | Knuth 1968 (attribute schedule) |
| **HOAG Gate** | Higher-order gate on schedule expansion. | Vogt 1989 (HOAG) |
| **Two-Stratum Partition** | Cold/warm fold into `gen-scope.eval`: a static schedule stratum and a convergence stratum. | Knuth 1968; Vogt 1989 |
| **Convergence Loop** | The Kleene-ascent loop (`gen-scope.circular`) that drives gen-dispatch's `dispatchStep` to a fixpoint. Reproduces the old gen-derive fixpoint byte-identically. | Sloane 2010 §2.2 (Kleene ascent) |

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
| gen-resolve | `gen-scope.circular` over `dispatchStep` | Context widens monotonically | Identified rules fire once globally |

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
| Reynolds | 1972 | Definitional interpreters for higher-order programming languages | Defunctionalization (gen-aspects guard wrapping), closure environments (gen-bind partial application) |
| Kahn | 1974 | Semantics of a simple language for parallel programming | Deterministic dataflow, named channels |
| Bracha & Cook | 1990 | Mixin-based inheritance | Record mixin composition (gen-algebra), schema mixins (gen-schema) |
| Forgy | 1982 | RETE: A fast algorithm for the many pattern/many object pattern match problem | Rule dispatch (gen-dispatch) |
| Vogt et al. | 1989 | Higher-order attribute grammars | Non-terminal attributes / dynamic node synthesis (gen-scope children); derived-children extends this |
| Cardelli | 1997 | Program fragments, linking, and modularization | Module signatures (gen-bind), NixOS module bridge (gen-schema) |
| Hedin | 2000 | Reference attributed grammars | Cross-node import edges (gen-scope) |
| Findler & Felleisen | 2002 | Contracts for higher-order functions | Blame tracking (gen-bind, gen-schema) |
| Hedin & Magnusson | 2003 | JastAdd — an aspect-oriented compiler construction system | Demand-driven AG evaluation, aspect-oriented modular extension (inspires neededBy) |
| Batory | 2005 | Feature-oriented programming and the AHEAD tool suite | Feature algebra (inspires gen-dispatch rule composition), aspects as features |
| Leijen | 2005 | Extensible records with scoped labels | Record algebra (gen-algebra), merge resolution (gen-bind) |
| Ehrig et al. | 2006 | Fundamentals of algebraic graph transformation | Graph rewriting rules, NACs (gen-dispatch) |
| Rondon et al. | 2008 | Liquid Types | Refinement predicates (gen-schema) |
| Radul & Sussman | 2009 | Art of the propagator | Monotonic convergence / quiescence (gen-dispatch, gen-graph) |
| Berry & Boudol | 1990 | The chemical abstract machine | Rules as reactions (gen-dispatch) |
| Sloane et al. | 2010 | A pure embedding of attribute grammars (Kiama) | Attribute combinators, CachedAttribute, paramAttr, circular attributes (gen-scope); collection attributes planned (§7) |
| Van Wyk et al. | 2010 | Silver | Forwarding, collection attributes |
| Chitil | 2012 | Practical typed lazy contracts | Lazy contracts (gen-bind, gen-schema) |
| Neron et al. | 2015 | A theory of name resolution | Scope graphs, P/I edges, resolution (gen-scope, gen-select) |
| van Antwerpen et al. | 2016 | A constraint language for static semantic analysis based on scope graphs | Constraint-based scope graph resolution, well-formedness generalization |
| Arntzenius & Krishnaswami | 2016 | Datafun | Monotonic fixpoint with typed guarantees (gen-dispatch, gen-graph); phase stratification inspired by classical Datalog |
| Mokhov | 2017 | Algebraic graphs with class | Graph construction primitives (gen-scope); algebraic foundation for gen-graph |
| van Antwerpen et al. | 2018 | Scopes as types (introduces Statix) | Custom edge labels, structural subtyping, Statix DSL (gen-scope) |
| Palmer et al. | 2024 | Intensional functions | Program-point identity, conservative equality, search monad (gen-algebra, gen-aspects, gen-dispatch, gen-select) |
| Lorenzen et al. | 2025 | First-order laziness | Lazy constructors inspectable before forcing, §1-2.3 (gen-aspects deferredModule) |
| Tarr et al. | 1999 | N degrees of separation | Multi-dimensional separation of concerns (classes as dimensions) |
| Kiczales et al. | 1997 | Aspect-oriented programming | Cross-cutting concerns, aspect weaving (conceptual ancestor; "pointcut"/"advice" terminology from later AspectJ) |
| Apel et al. | 2009 | An overview of feature-oriented software development | Feature-oriented decomposition |
| Thum et al. | 2014 | Analysis strategies for software product lines | Feature interaction detection |
