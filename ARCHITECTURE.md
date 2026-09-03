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
  mkGenLibs keys (the roster of record is lib/mkGenLibs.nix, never a count — ADR-0015):
    gen-prelude · gen-algebra · gen-types · gen-merge · gen-schema
    gen-aspects · gen-scope · gen-memo · gen-graph · gen-select · gen-bind
    gen-dispatch · gen-class · gen-link
    gen-product · gen-settings · gen-assemble · gen-view · gen-identity · gen-program · gen-delivery
  standalone pure libs:
    gen-vars
  retired, archived for reference (off-roster, not a hub input):
    gen-demand   → re-expressed into gen-scope (ADR-0008 §4)
    gen-rebuild  → content moved onto the gen-memo plane (ADR-0008 §4, ADR-0005)
    gen-edge     → movement vocabulary, gen-view the fourth destination (ADR-0010 §3)
    gen-pipe     → movement vocabulary: gen-view, and gen-select for `sel` (ADR-0010 §3)
    gen-flake    → dissolved to per-surface successors: compose → this hub's `lib.compose` /
                   interim flakeModule; warm/override/trace → gen-memo; projection + realize →
                   gen-delivery; inject/terminals → the crossing's Adapter set (ADR-0031 F3)
    gen-resolve  → left on the 2026-09-02 transfer ruling with its eleven exports dispositioned
                   ROW BY ROW rather than moved as one content block: materialization vocabulary
                   and the reference construct → gen-view; crossing terminal → gen-bind; the
                   seal-level queries → gen-scope; the reuse key → gen-memo; `attr` and
                   `cascade` dissolved by ruling (ADR-0008 §4; map at den-hoag-p3y9)
                   ★ STRUCK 2026-09-03 — this row read "schedule and the seal-level queries →
                   gen-scope", and the static SCHEDULE's destination is NOT gen-scope. The owner
                   RULED it "THE QUERY-GATE HOME" (2026-08-11, den-hoag-ui5c; engine-spec R§5.2).
                   That referent has NEVER been resolved to a named library — ADR-0008 §3's "no
                   standalone analysis library" constrains the answer without supplying it — and
                   the struck destination is unexecuted at the substrate (gen-scope.lib ⇒ 89
                   exports, 0 matching [Ss]chedul, at a73bb80). Carrier resolving the referent:
                   den-hoag-query-gate-home-static-schedule-6poeg
```

The ecosystem now spans **two evaluation planes**. The *composition plane* is pure and
nixpkgs-lib-free: a module-system substrate (`gen-types → gen-merge → { gen-schema, gen-aspects }`)
composes gen module trees to resolved VALUES without ever touching `lib.evalModules`. The *terminal
plane* is nixpkgs: gen-delivery's `realize` folds the composed projection through per-class terminals,
with this hub's interim `flakeModules.default` supplying the default `nixos` terminal (a consumer may
override or suppress it) — the boundary that injects those values into a consumer's nixpkgs eval and
builds NixOS systems. Historically the sole boundary here was `gen-flake`; it dissolved and its repo
orphans as reference (ADR-0031 F3; see Terminal Layer, below). The invariant across the crossing: **gen
TYPES never leave the pure eval; only VALUES cross** (value-injection, not type-driving). This holds
under ADR-0023's declared interim (checking off by default; unstated crossings become declared
opt-outs with their price recorded) until the by-construction target (`den-hoag-zgps`) lands.

### The CI harness is not a library, and it does not live here

`gen-harness` (`github:sini/gen-harness`) owns **`mkCi`**, the flake wrapper each gen repo's `ci/` is
built from. It is not on the roster, not a hub input, and exports no gen concern — it is CI packaging,
not a library. What makes it a separate repository is that **it pins no gen library**: a library's
`ci/` lock would otherwise drag in the aggregator that pins that same library, which is the
hub → lib → lib's `ci` → hub cycle the extraction exists to cut. The cut is a property of the pins,
so it is read off them rather than remembered: in `gen-harness`,
`grep -oE '"gen-[a-z]+"' flake.lock` returns nothing, while the same command in any library's
`ci/flake.lock` returns that library's gen inputs.

**Who consumes it.** Every gen repo's `ci/flake.nix` calls `gen-harness.lib.mkCi` — the one exception
is `gen-vars`, excluded from the inventory by ADR-0003 and knowingly left at an older pin. gen-flake
called it too, migrating onto the harness in its own commit before its later dissolution (ADR-0031 F3),
so no repository was left holding a pin it could not move. From any library root,
`grep -c 'gen-harness\.lib\.mkCi' ci/flake.nix` says whether that repo is on the harness, so the fact is
re-derived rather than remembered.

**The hub itself is not an `mkCi` consumer.** `ci/mkCi.nix` and `ci/flakeModule.nix` — the copies the
harness was extracted from — retired at `a19685b` (2026-08-17, five files); the hub's own gate now
consumes `gen-harness`'s declared check builders (`lib.checks.treefmtTreeRoot`,
`lib.checks.mdformatPlugins`, `lib.mdformatBasePlugins`) directly, and the root no longer publishes
`lib.mkCi` at all — the hub's own `ci/` was always a parity/perf harness exposing flake `checks` and a
perf `app`, never a `mkCi`-shaped `tests` output. The extraction this section once described as
"specified but NOT landed" landed the same day it was specified — see
`specs/2026-08-17-gen-hub-ci-extraction-completion-spec.md` in den-ag-design, stamped LANDED. A reader
meeting `gen-harness.lib.mkCi` everywhere but the hub itself is meeting the current, single-copy
topology, not a defect.

## Dependency Graph

Libraries have minimal inter-dependencies. Most are independent.

```
gen-prelude (pure nixpkgs-lib-free utility base — zero deps)
gen-algebra (pure primitives — zero deps)

  # module-system substrate (all nixpkgs-lib-free, built on gen-prelude)
  gen-types  (structural checker; imports gen-prelude)
  gen-merge  (byte-mode evalModuleTree; imports gen-prelude, injects gen-types)
  ├── gen-schema (imports gen-prelude + gen-merge + gen-algebra)
  │   └── gen-aspects (imports gen-prelude + gen-merge + gen-schema)
  │
gen-scope    (gen-prelude)
gen-graph    (gen-prelude)
gen-select   (zero deps — Class A, builtins only)
gen-bind     (gen-prelude)
gen-dispatch (gen-prelude only)
gen-memo     (gen-prelude + gen-graph)
gen-assemble (ZERO inputs by design — substrate injected by the consumer, ADR-0014)
gen-resolve  (gen-scope + gen-graph + gen-algebra + gen-bind)
gen-vars     (standalone pure)

  # L2 concern libraries (hub-wired via mkGenLibs; all Class B, nixpkgs-lib-free)
  gen-product  (gen-prelude; consumes gen-graph accessor + gen-schema id_hash shape structurally)
  gen-settings (gen-prelude + gen-algebra + gen-bind; gen-schema interface-only)

  # historically gen-flake sat here as the one nixpkgs boundary (import-tree + gen-merge +
  # gen-schema + gen-aspects + gen-bind + nixpkgs); it dissolved (ADR-0031 F3) — see Overview
  # and Terminal Layer for where full nixpkgs enters today
```

Each library exposes a single `.lib` value output — the obsolete functor-call form `gen-graph { inherit lib; }` is gone (`__functor` is banned ecosystem-wide). Dependency classes are declared honestly: **A** pure `{}`, **B** gen-prelude, **C** nixpkgs-lib, **D** nixpkgs-lib + gen-dep.

The ecosystem is now **entirely nixpkgs-lib-free** at the library level. The module-system substrate landed the re-host: **gen-types** is the verify-only structural checker (the checking half); **gen-merge** is the byte-mode `evalModuleTree` (the merge half — a pure `lib.evalModules` + `lib.types`-merge reproduction over a priority subset, byte-identical on den's surface). **gen-schema** and **gen-aspects** were re-hosted onto that substrate — their `lib/` no longer imports `lib.evalModules`/`lib.types` (byte-identical to the old nixpkgs-driven versions over every non-identity field; the re-minted `id_hash` is the ADR-0016 excluded axis, held by a teeth arm on the pure engine rather than against the frozen witness); gen-schema now takes `{ prelude, merge, algebra }`, gen-aspects `{ prelude, merge, schema }`. Class C/D are therefore empty among the pure libs. gen-dispatch depends only on gen-prelude (its gen-select bridge is a structural adapter, not an import). gen-resolve is Class B with four gen siblings — it hosts the convergence loop that ties the dispatch step and scope evaluation together. No library on today's roster consumes full nixpkgs at all — historically **gen-flake** was the sole one that did, and only in its terminals (`realize` driven by `terminals.nixosSystem`); its pure core (`compose`/`injectArgs`) was itself nixpkgs-lib-free. gen-flake dissolved (ADR-0031 F3): its pure core lives on at this hub's `lib.compose`, still nixpkgs-lib-free, and its terminal now sits at this hub's interim `flakeModules.default` and gen-delivery's `realize` — see Overview and Terminal Layer.

Above the L1 substrate sit two **L2 concern libraries** — gen-product and gen-settings — each a Class B (nixpkgs-lib-free) library that pins one algebra a configuration framework assembles with: graph products and layered settings. They depend only on L1 siblings and import nothing upward. Each flake `.lib` self-resolves its own deps, so they are **hub-wired via `mkGenLibs`** (keys `product`, `settings`) like the self-wiring libraries above. Three more stood here and have retired, each archived for reference rather than deleted: **gen-demand** (typed demand), whose cascade ADR-0008 §4 re-expresses over gen-scope, the sole engine; and **gen-edge** (content movement) and **gen-pipe** (scoped-channel dataflow), which ADR-0010 §3 retires together into the movement vocabulary — the substrate constructs of gen-view, gen-select, gen-graph and gen-scope. The L2 tier shrinking is the point of that ruling rather than an accident of it: a concern expressible in substrate vocabulary did not need a library of its own.

### The nixpkgs.lib policy

Anywhere the gen ecosystem needs nixpkgs *lib* only, it uses a pinned `github:nix-community/nixpkgs.lib` — not full nixpkgs. Full nixpkgs is pulled ONLY where `pkgs`/`nixosSystem` are genuinely needed: the nix-unit/treefmt CI runners and, at the library level, nowhere else — historically the gen-flake terminal, now this hub's interim `flakeModules.default` and gen-delivery's `realize` (ADR-0031 F3; see Terminal Layer). Those are the terminal-plane's single legitimate points of entry for full nixpkgs.

## Library Roles

### Foundation Layer

**gen-prelude** — Pure nixpkgs-lib-free utility base.

Re-exports of `builtins` plus a vendored set of `lib` utilities, with zero dependency on nixpkgs. It is the substrate that lets gen-scope, gen-graph, gen-select, gen-bind, gen-dispatch, and gen-memo be nixpkgs-lib-free.

**gen-algebra** — Pure primitives shared across the ecosystem.

- Search monad (indexed state threading with convergence)
- Intensional functions (program-point identity, conservative equality — the mint itself is injected, not owned)
- Record algebra (scoped labels, mixin composition, `foldLayers` for per-field-strategy fold)
- Either combinators

gen-algebra is now **fully pure** — a single `lib` tier (the former `pure` tier, renamed), zero dependencies, not even nixpkgs. Its old module tier (strict modules, ref types, validators — the constructs that needed `lib.types`/`evalModules`) was relocated into gen-schema; identity minting split further, into `gen-identity` — the substrate's one minting authority (ADR-0016 ruling 5) — which gen-schema now takes injected rather than owning (`gen-schema/lib/id-hash.nix`). Every other gen-\* library that needs search imports gen-algebra; one that needs identity minting imports gen-identity.

### Module System Layer

The pure-Nix module system that replaces nixpkgs' `lib.evalModules` + `lib.types` on the gen surface. A clean split: gen-types **checks**, gen-merge **merges**; they meet only at leaves, post-merge.

**gen-types** — Pure structural type checker.

The *checking half*. A type is a predicate boundary (Findler & Felleisen 2002): `verify` a value and get back `null` (it inhabits the type) or an error string (it does not). Nothing else — no merging, no priority, no fixpoint. Primitives, polymorphic combinators (`option`/`listOf`/`attrsOf`/`union`/`tuple`/…), `struct` with closed-world `.override`, refinement contracts (Rondon 2008), validators, and name-only intensional identity (`__id` = sha256 of the type name — the same discipline as gen-schema's `id_hash`). A successful `verify` is a single pass; failure re-scans only to locate the first offender. It is a self-contained **leaf** library (its own flake) so it imports *below* a registry without a flake cycle.

**gen-merge** — Byte-mode module merge engine.

The *merge half*. `evalModuleTree` collects a tree of modules, ties the self-referential `config` fixpoint (one local `fix` per call), resolves per-option definitions by priority, recurses into structural types, routes unknown keys through a freeform type, and verifies leaves via the injected gen-types checkers — reproducing nixpkgs' merge **output**, byte-for-byte, on the surface a real configuration uses, with zero nixpkgs. It implements **one** priority rule (lowest-number wins, ties merge, over `mkForce`/`mkDefault`/`mkOverride`/`mkOptionDefault`) plus `mkMerge`/`mkIf` — the entire nixpkgs ORDER pass (`mkOrder`/`mkBefore`/`mkAfter`) is dropped (zero uses on the surface). A byte-identity oracle with mutation-teeth (`ci/tests/oracle.nix`) gates it against `lib.evalModules`. Structural merge strategies (`submodule`/`listOf`/`attrsOf`/`lazyAttrsOf`/`deferredModule`/`either`/…) live here; leaf checkers come from gen-types. The unified `genMerge.types` namespace (gen-types leaves ⊎ gen-merge strategies) is the `lib.types` drop-in the re-host points at.

### Type System Layer

Re-hosted onto the module-system substrate above — nixpkgs-lib-free, byte-identical to the old nixpkgs-driven versions.

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

Accessor-based: takes `{ edges, parent, nodes, nodeData }` functions, answers structural questions. Lazy traversal (reachableFrom, canReach, pathsBetween) and global analysis (cycles, dependents, transpose). C-level BFS via `builtins.genericClosure`. It also owns the ordering front-door (`order.nix`): `phaseOrder` — a forward producers-first order over the condensation (a cycle or self-loop throws) — plus `entryAnywhere`/`entryAfter`/`entryBefore`/`entryBetween`. This is where gen-derive's group ordering moved; gen-dispatch consumes the result as its `groupOrder`.

**gen-select** — Selector algebra.

Pattern matching over attributed graph positions. Selectors are `{ __sel = tag; ... }` attrsets. Constructors (star, attrs, entity, kind, and, any, not, has, within, parentMatches, when) compose into predicates evaluated by `matches selector id ctx`. **Identity-bearing selectors** (`sel.entity`, `sel.kind`) match by gen-schema `id_hash` / kind rather than attribute values, taking registry entries or kind values (never `"kind:name"` strings). Adapters bridge to gen-scope, gen-graph, a flat registry, and gen-product cells without importing them.

### Binding Layer

**gen-bind** — Module binding.

Injects external values into NixOS module functions. Handles three module shapes, merge strategy control (bind-wins/system-wins/error), lazy contracts, config thunks, provenance tracking, batch wrapping, and identity stamping. The bridge between scope-computed values and the NixOS module system.

### Dispatch Layer

**gen-dispatch** — Relational rule dispatch STEP.

Production rule system: rules (condition + action producer + identity) dispatched across stratified groups. It owns **rule evaluation only** — a pure function of `(rules, context)`. It does **not** own the convergence loop and does **not** sort groups. `dispatch` takes a pre-ordered `groupOrder :: [groupName]` (computed elsewhere) and returns `orderedGroups`, the present-only subsequence. Conflict resolution: override → priority → specificity → additive. A caller iterates by threading plain domain state through repeated one-shot dispatch and reading actions off the fixpoint (recompute-at-fixpoint = confluence, so no cross-pass `fired` bookkeeping); a gen-select bridge (`adapters.select`) supplies selectors as conditions. Removed vs the old gen-derive: `fixpoint` (the loop, now gen-resolve), `topoSort`/`entry*` (the ordering, now gen-graph), and the `dispatchStep`/`dispatchInit` migration seam (retired once the recompute-at-fixpoint pattern was blessed).

### Evaluation / Convergence Layer

**gen-resolve** — Demand-driven RAG evaluator over scope graphs.

A pure-Nix RAG schedule-conductor (Knuth 1968 attribute schedule + Vogt 1989 HOAG gate + two-stratum partition, cold/warm fold into `gen-scope.eval`). It **owns the convergence loop**: `gen-scope.circular` iterates a step over the domain state to a fixpoint (Kleene ascent, Sloane 2010 §2.2); a relational-dispatch fixpoint is expressed by making that step a one-shot `gen-dispatch.dispatch` whose output context is the next iterate, then reading the actions off the converged context. Class B — four gen siblings (gen-scope, gen-graph, gen-algebra, gen-bind).

### Terminal Layer

The nixpkgs-facing crossing. **gen-flake was the sole boundary here; ADR-0031 F2 dissolved it into
per-surface successors** — the compose S2 core at this hub's `lib.compose` / interim
`flakeModules.default`; warm/override/trace in gen-memo; the projection + `realize` in gen-delivery;
inject/terminals at the crossing's Adapter set. gen-flake's own section below is kept as the retired
surface's record, in the same pattern as gen-edge and gen-demand above.

This hub's OWN `flakeModules.default` — rehomed from gen-flake under ADR-0031 F1, marked INTERIM (not
yet ADR-0027) — is the current flake-parts ergonomics: one `imports` gives both the injected query
surface (into top-level and `perSystem` args) and `flake.nixosConfigurations` from one compose, over
the option surface `gen.tree` / `gen.extraModules`. It consumes no gen-flake surface. The **invariant**
gen-flake proved end-to-end (gen TYPES never leave the pure eval; only VALUES cross) carries forward
architecturally at the new boundary under ADR-0023's declared interim (b) — target-invoked checking off
by default until the by-construction target (`den-hoag-zgps`) lands; the hub's `ci/inject-payload.nix`
(ADR-0023 (b), the crossing Adapter side) is the live check that keeps that declared opt-out's price
measured rather than assumed.

**gen-flake** — The value-injection boundary. **ORPHANED AS REFERENCE (ADR-0031 F3) — dissolution
complete; off the roster, not a hub input. Take no new dependency on it.**

It was the single sanctioned crossing from the pure composition plane into nixpkgs. Three ops:

- **`compose { tree ? null, modules ? [], specialArgs ? {} } -> { values; classContent; hostContent }`** — loaded a gen module tree (as a bare path list via the import-tree fork) and resolved it PURELY via gen-merge's `evalModuleTree`. Threaded the gen constructors (`genMerge`/`genSchema`/`genAspects`/`genTypes`/`genPrelude`) to every module so definition modules declared their typed surfaces without nixpkgs. `values` = the resolved config; `classContent` = the flat aspect registry (query surface); `hostContent` = the per-host `(class, host)` projection (build surface). Successor: this hub's `lib.compose`.
- **`injectArgs composed -> { _module.args.genValues = composed.values; }`** — packaged the resolved VALUES as a plain query module so a consumer's nixpkgs modules read `{ genValues, ... }: … genValues.hosts.<h>.addr …`. Pure — no gen TYPE crosses. Successor: the crossing's Adapter set.
- **`realize { composed, terminals, bindings ? {}, extraModules ? {} } -> { <class> = { <host> = <built> } }`** — the terminal **driver**, and the split mattered: `realize` was the class-major fold. Per class and host it selected `composed.hosts.<h>.classes.<c>`, merged the three binding layers (`hc.bindings // bindings // bindings.<host>`), knot-tied the colmena-style `nodes` accessor to the class's own lazily-built result set, and called the terminal. It never partial-applied anything itself. Output keys were exactly the `terminals` keys. The **binding** happened one level down, in `terminals.mkSystemTerminal { evaluator }`: that is where `gen-bind.wrapAll { modules; bindings; }` ran, and where `nodes` reached the modules as `specialArgs`. `mkSystemTerminal` named no system class and touched no nixpkgs; `terminals.nixosSystem { nixpkgs; }` was that generic terminal instantiated with `nixpkgs.lib.nixosSystem`, and was the ONE place that touched nixpkgs. `terminals.mkFlakeTerminal` was the flake-parts crossing beside it. Successor: gen-delivery's projection + `realize`.
  - The v0 terminal `mkSystems { hostContent; nixpkgs; extraModules; }` was **retired**, not renamed, before the dissolution: it was absent from `gen-flake/lib/` entirely. Its replacement, per gen-flake's own migration table, was `realize { composed; terminals.nixos = terminals.nixosSystem { nixpkgs; }; extraModules; }`, and `composed.hostContent` became `composed.hosts`.

`diff.nix` stays in the orphaned repo as reference — a named input to gen-memo's failure-attribution
spec, not code to copy. This was the same one-way `compose → value → nixpkgs` trade adios (adisbladis)
takes; a pure engine cannot be driven by foreign nixpkgs-module libraries.

### L2 Concern Libraries

These libraries build on the L1 substrate as nixpkgs-lib-free (Class B) concern libraries. Each fixes one algebra a configuration framework needs but the substrate deliberately leaves to the consumer. Two remain — gen-product and gen-settings — and each flake `.lib` self-resolves its own deps, so both are hub-wired via `mkGenLibs` (keys `product`, `settings`). Three retired and are off the roster and no longer hub inputs: **gen-demand** (ADR-0008 §4, re-expressed over gen-scope, the sole engine), **gen-edge** and **gen-pipe** (ADR-0010 §3, retired together into the movement vocabulary). Their sections below are kept as the retired surfaces' record — each states where its content went, because a section deleted outright leaves a reader who meets the name in old code with nowhere to go.

**gen-edge** — Content-movement contract. **RETIRED (ADR-0010 §3) — off the roster, not a hub input, archived for reference. Take no new dependency on it.**

Everything that moved content between graph positions was an edge `(S, T, P, M)` — source, target, attrpath, mode. gen-edge owned the edge record and its constructors, edge-set derivation for a root (`edgesFor`), toposorted materialization (Kahn's algorithm over the accumulator dependency relation) into a per-root/per-channel content map, and a frozen, hashable **edge trace** that rendered edge identities without forcing resolved content — a cross-repo parity oracle. Positions, channels, and content were all opaque; it depended on gen-prelude and gen-graph. Twelve of its eighteen exports name destination constructs in **gen-view**, the fourth destination ADR-0010 §3 gained on 2026-08-20, with the Kahn arm reached through `accumulatorOrder` over the relation `accumulatorRelation` builds. The edge trace was the instrument that validated the very spec retiring it, so the oracle cluster retired last, after movement AC-7 ran; that run demoted the trace from acceptance authority to topology evidence, because two runs with different answers can share a byte-equal fingerprint.

**gen-product** — Graph products over accessor-graphs.

Builds the four standard graph products — Cartesian, tensor, strong, lexicographic — over the gen-graph accessor-record convention. A product *is* an accessor-graph (gen-graph queries apply unchanged) extended with product metadata. Provides cells (full coordinates), slices, fibers, projections, quotients, sparse `restrict` (the real, non-dense fleet), and specificity `containmentChain`s. Lazy in, lazy out; coordinates are registry entries, never `"kind:name"` strings. Depends only on gen-prelude.

**gen-settings** — Stratified settings resolution.

Resolves an aspect's static `{ default; merge }` settings schema against an ordered layer list (least → most specific) as a pure layered fold — byte-identical to gen-algebra's `foldLayers` over the same strategies. Adds identity-bearing cross-aspect **refs** as inert data (statically computable dependency graph, definition-time cycle detection), structured per-field provenance, and graduated injection (`injectAspectSettings` / `assembleHost`) via gen-bind. Lattice-blind by design: the layer order arrives precomputed. Depends on gen-prelude, gen-algebra, and gen-bind; consumes gen-schema interface-only (`id_hash`).

**gen-demand** — Typed demand cascade. **RETIRED (ADR-0008 §4) — off the roster, not a hub input, archived for reference. Take no new dependency on it.**

Graph nodes emitted typed **demands**; registered **kinds** resolved each into resources, wiring, and sub-demands over a downward-only kind DAG. A stratified fold resolved the growing demand multiset in ≤ DAG-depth rounds (termination a theorem, not a convergence loop), with pinned-order dedup and a full provenance trace. Emission independent of consumption by signature. It depended on gen-prelude and gen-graph, with gen-select optional (subject-matching adapter). All of that now lives in **gen-scope** as `lib/cascade.nix` + `lib/folds.nix`, under claim vocabulary — the request value is a `mkClaim`, named for what it is rather than for the evaluation strategy. The one export that did not move is `adapters`: it retires with its construct, and gen-scope takes no gen-select edge.

**gen-pipe** — Scoped-channel dataflow algebra. **RETIRED (ADR-0010 §3) — off the roster, not a hub input, archived for reference. Take no new dependency on it.**

A channel was a typed, named accumulation lane whose value at a scope position was a deterministic fold (pinned traversal, associative-only combine) over the contributions visible there. Operators (`map`, `filter`, `fold`, `scan`, `route`, `join`, `tee`) connected channels into a dataflow DAG, validated at composition time and evaluated demand-driven. Contributions carried structured provenance and a class tag; a `classInvariant` flag recorded config-dependence statically. It depended on gen-prelude, gen-select, and gen-scope. Twelve of its seventeen exports name destination constructs in **gen-view**; `sel` was a gen-select re-export and consumers bind gen-select directly; `join` has no single successor construct and is a caller-side composition. The B5 laws survive as properties of the query construction rather than of a library — first-appearance walk order, a whitelist of declared associative combines, and a record for every drop or reorder.

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
   gen-dispatch: rules fire on context, produce effects (one pure step);
   gen-graph phaseOrder orders the groups; gen-resolve loops to convergence

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
# groupOrder comes from gen-graph, the loop from gen-resolve
genDispatch.dispatch {
  match = genDispatch.adapters.select.mkMatch genSelect;
  groupOrder = genGraph.phaseOrder { /* groups + entry* constraints */ };
  # ...
};
```

Each call hits memoized values. No redundant computation between libraries.

### Fixpoint Coordination

Three fixpoint loops, each at a different level:

| Level     | Library                              | What converges              | Triggered by                             |
| --------- | ------------------------------------ | --------------------------- | ---------------------------------------- |
| Value     | gen-algebra (search.converge)        | Index state + continuations | Search monad operations                  |
| Structure | gen-scope (circular attr)            | Attribute values on nodes   | Circular dependencies between attributes |
| Dispatch  | gen-resolve (via gen-scope.circular) | Rule context (domain state) | Enrichment actions that widen context    |

The dispatch loop is **not** owned by gen-dispatch — gen-dispatch supplies only the pure step (`dispatch`, a function of `(rules, context)`), and gen-resolve drives it to convergence with `gen-scope.circular` (Kleene ascent) by threading the plain domain state and reading actions off the fixpoint. The consumer (den) coordinates these: gen-resolve's loop runs the dispatch step, which may trigger gen-scope attribute recomputation, which in turn may trigger gen-algebra search convergence. Nix's lazy evaluation ensures only demanded values are computed.

## Performance Architecture

### Memoization Strategy

| Library      | Mechanism                                                       | Scope                                                    |
| ------------ | --------------------------------------------------------------- | -------------------------------------------------------- |
| gen-scope    | `_eval` attrset co-located on each node                         | Per-node, per-attribute                                  |
| gen-graph    | Accessor functions (caller's responsibility)                    | Delegates to source (gen-scope `_eval` when wired)       |
| gen-dispatch | `fired` set across loop iterations (loop driven by gen-resolve) | Per-dispatch-session                                     |
| gen-select   | None (stateless predicate evaluation)                           | Each match is fresh but data access hits gen-scope cache |

### Cost Model

| Operation                             | Cost                      | Bottleneck                                           |
| ------------------------------------- | ------------------------- | ---------------------------------------------------- |
| Attribute access (cached)             | O(1)                      | Nix attrset lookup                                   |
| Attribute access (first, root)        | O(1)                      | Lazy thunk evaluation                                |
| Attribute access (first, synthesized) | O(depth)                  | Parent chain walk via parseParent                    |
| Graph traversal (lazy)                | O(reachable)              | C-level BFS                                          |
| Graph traversal (global)              | O(n)                      | Full node enumeration                                |
| Selector match                        | O(selector complexity)    | Short-circuit on first false/true                    |
| Rule dispatch (one step)              | O(rules × context checks) | fromFunctionMatch is O(1) per rule                   |
| Convergence loop iteration            | O(iterations × dispatch)  | gen-resolve loop; identified rules fire at most once |

### Fleet Scale Guidance

- **Use parseParent** in gen-scope — O(depth) vs O(n) node resolution
- **Use Tier 1 operations** (node, get) for per-entity work; Tier 2 (allNodes) for diagrams/fleet queries
- **Use point queries** (canReach, dependentsOf) over global analysis (dependents, transitiveClosure)
- **Partition large graphs** before global operations — cross-partition edges are rare
- **Accessor pattern** ensures zero redundant evaluation between gen-scope and gen-graph

## Design Constraints

1. **No circular library dependencies.** The dependency DAG is strictly acyclic.
2. **Libraries don't import each other's flake inputs.** gen-select doesn't import gen-scope; it provides adapters that accept gen-scope's result shape.
3. **Actions are opaque.** gen-dispatch doesn't interpret actions — consumers define the vocabulary via `mkActions` and `classify`.
4. **Conditions are opaque (in core).** gen-dispatch's core tier takes a `match` function; the adapter tier bridges gen-select as one possible condition language.
5. **Nix IS the evaluator.** gen-scope doesn't build an AG evaluator — it leverages Nix's native lazy evaluation, `lib.fix` for memoization, and attrset lookup for O(1) access.
6. **gen-algebra is fully pure.** Its single `lib` tier (search, intensional, record, either) works without nixpkgs. Libraries that only need search or the intensional constructors import it directly; identity minting is `gen-identity`'s (ADR-0016 ruling 5), taken injected. The nixpkgs-lib-free base for the rest of the ecosystem is `gen-prelude`.
7. **The library level is nixpkgs-lib-free.** The module-system substrate (`gen-types → gen-merge → { gen-schema, gen-aspects }`) replaced nixpkgs' `lib.evalModules`/`lib.types` on the gen surface, so no library `lib/` imports nixpkgs. Full nixpkgs enters at exactly one plane — the terminal plane — plus the CI runners; historically that terminal was the `gen-flake` repository (`terminals.nixosSystem`, the generic `mkSystemTerminal` instantiated with `nixpkgs.lib.nixosSystem`), which dissolved (ADR-0031 F3) into this hub's interim `flakeModules.default` and gen-delivery's `realize`. Where only nixpkgs *lib* is needed, use a pinned `nixpkgs.lib`, not full nixpkgs.
8. **Compose purely, inject VALUES — never TYPES.** Composition happens in the pure plane; only resolved values cross into a consumer's nixpkgs eval (via `_module.args`), never gen type objects. A gen type may ride along as inert data but must never enter a consumer's options tree, so nixpkgs never type-walks it (value-injection, not type-driving). Today this holds under ADR-0023's declared interim — checking off by default, unstated crossings recorded as declared opt-outs with their price — until the by-construction target (`den-hoag-zgps`) lands.
