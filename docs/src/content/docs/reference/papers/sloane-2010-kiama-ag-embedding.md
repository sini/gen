---
title: Sloane et al. (2010) -- A Pure Object-Oriented Embedding of Attribute Grammars
description: Our reading of A pure embedding of attribute grammars.
source:
  - den-ag-design:used/summaries/sloane-2010-kiama-ag-embedding.md
---

> A. M. Sloane, L. C. Kats, and E. Visser, "A pure embedding of attribute grammars," *Science of Computer Programming*, vol. 78, no. 10, pp. 1752–1769, 2011. doi: [10.1016/j.scico.2011.11.005](https://doi.org/10.1016/j.scico.2011.11.005) · [open access](https://www.sciencedirect.com/science/article/pii/S016764231100205X/pdf) · [summary](/reference/papers/sloane-2010-kiama-ag-embedding/).

## Paper Summary

Sloane, Kats, and Visser address the overhead imposed by attribute grammar (AG) generators: custom front-ends, specialized build pipelines, steep learning curves, and tight coupling to a particular code-generation strategy. Despite a decade of dynamically-scheduled AG systems (JastAdd, LRC, UU AG, Silver) that evaluate attributes by need at run-time rather than computing a static evaluation order at generation time, every system still required a pre-processor step translating AG specifications into a general-purpose language. The question the paper poses is whether the generator can be eliminated entirely by embedding the AG formalism as a library in a sufficiently expressive host language.

The answer is Kiama, a pure embedding of attribute grammars in Scala. "Pure" means no pre-processor, no code generation, no custom syntax -- the entire AG is expressed using standard Scala constructs: case classes for abstract syntax trees, pattern-matching anonymous functions for attribute equations, traits and mixins for modular composition. The embedding exploits Scala's combination of object-oriented programming (state encapsulation, inheritance, traits) and functional programming (first-class functions, pattern matching, algebraic-data-type-like case classes) to express AG concepts without sacrificing the declarative, high-level nature of the formalism.

The paper presents two running examples. Repmin (S2.1), the classic tree transformation problem, demonstrates synthesized attributes (`locmin`), inherited attributes (`globmin` propagated from root via `parent`), and higher-order attributes (`repmin` producing a new tree). Variable liveness (S2.2) demonstrates reference attributes (`succ` following control-flow edges outside the tree spine), inherited attributes defined via parent matching (`following` using `childAttr`), and circular attributes (`in`, `out`) evaluated to a fixed point using the algorithm of Magnusson and Hedin (2003). The circular attribute constructor takes an initial value and iterates until convergence, enabling data-flow equations to be expressed declaratively within the AG framework.

The implementation (S3) consists of approximately 230 lines of Scala. The central abstraction is `CachedAttribute[T,U]` (Figure 6), a partial function from tree nodes to attribute values that memoizes results in an identity hash map. On first access, a sentinel `None` is stored to detect circular self-references (reporting an error for non-circular attributes); the defining equations are then evaluated, and the result cached as `Some(u)`. Subsequent accesses return the cached value in O(1). This is the same general approach as JastAdd's demand-driven evaluation, but caches reside in attribute objects rather than in tree nodes -- a design that preserves modularity at the cost of slight space overhead. Parameterized attributes (`paramAttr`, S3/Figure 4) support value-indexed attribute families (e.g., name lookup keyed by identifier string). `CircularAttribute` provides Magnusson-Hedin fixed-point evaluation for circular dependencies.

The structural infrastructure (S3.1) requires AST case classes to inherit from `Attributable`, which uses Scala's `Product` trait to generically traverse constructor fields and set `parent`, `next`, `prev`, `isRoot`, `isFirst`, `isLast`, and `index` properties. The paper carefully distinguishes containment (case class fields) from the parent-child relation (the `Attributable` subset of fields, including sequences and optionals).

Section 4 addresses modularity. Static separation of concerns (S4.1) uses Scala traits to define attribute interfaces (`ControlFlow`, `Variables`) and mixin composition to combine implementations (`LivenessImpl with VariablesImpl with ControlFlowImpl`). Dynamically extensible attribute definitions (S4.2) introduce the `+=` operator on attribute objects, allowing new equation cases to be added at run-time from separately compiled, dynamically loaded plugins. The `using` block (a scoped `try/finally` pattern) activates extensions only within a delimited scope, then removes them -- enabling disciplined, reversible language extension.

Performance evaluation (S5) compares Kiama, handwritten Scala, and three JastAdd variants on the PicoJava specification (18 productions, 10 attributes). With full caching and no rewrites, Kiama is 1.5-2.8x slower than JastAdd but comparable in specification size (262 vs. 243 LOC), while the handwritten version requires 424 LOC for a 2x speedup. The paper concludes that the embedding is practical for realistic language processing, with the trade-off being runtime overhead versus the elimination of the generator, simplified build process, and full access to the host language ecosystem.

Section 7 notes future work on collection attributes (Boyland 2005; Magnusson, Ekman, Hedin 2007) -- traversal-based aggregation attributes that collect contributions from multiple tree nodes into a single value, evaluated by visiting the tree and folding contributions.

## Key Concepts

- **Pure Embedding of AGs:** The entire attribute grammar is expressed in the host language (Scala) with no generator, no pre-processor, and no custom syntax. Attribute equations are pattern-matching functions; composition uses traits and mixins. This proves that a sufficiently expressive host language can absorb the AG formalism as a library. (S1, S7)

- **CachedAttribute Pattern:** The core memoization abstraction. A partial function `T ==> U` backed by an identity hash map. First access stores a sentinel, evaluates the defining function, caches the result. Subsequent accesses are O(1). Cycle detection via sentinel check. (S3.2, Figure 6)

- **Circular Attributes with Fixed-Point Evaluation:** The `circular(init)(f)` constructor creates attributes evaluated by iterating from an initial value until convergence, following Magnusson and Hedin's algorithm. Enables declarative expression of data-flow equations (e.g., liveness analysis) within the AG framework. (S2.2, Figure 3-4)

- **Parameterized Attributes:** `paramAttr(f)` creates attribute families indexed by a parameter of type S. The result is a curried function `S => T ==> U`, supporting value-parameterized lookups such as name resolution keyed by identifier. (S3, Figure 4)

- **Inherited Attributes via Parent Matching:** `childAttr(f)` defines attributes by pattern-matching on the parent node, enabling inherited attribute propagation without explicit copy rules. The parent reference is a structural property set during tree initialization. (S2.1-2.2, S3.1)

- **Dynamic Attribute Extension:** The `+=` operator on attributes appends new equation cases to an internally maintained list of partial functions. `using(extension) { block }` provides scoped activation with guaranteed cleanup. Enables separately compiled language extensions as binary plugins. (S4.2, Figure 7)

- **Static Modular Composition:** Scala traits define attribute interfaces; self-type annotations declare dependencies; mixin composition assembles implementations. This replaces the "aspect weaving" of generator-based systems with explicit, type-checked composition. (S4.1)

- **Collection Attributes (Future Work):** Mentioned in S7 as planned. Multi-contributor aggregation attributes where multiple tree nodes contribute values that are folded into a single result via tree traversal. (S7, refs [4,15])

## Implementation Mapping

### Current Usage in Gen Ecosystem

**gen-scope (MAJOR -- directly implements four Kiama constructs)**

1. **`_eval` co-located cache = CachedAttribute (S3.2, Figure 6).** Every scope graph node receives an `_eval` attrset -- a lazy Nix attrset where each key is an attribute computation. Nix's lazy evaluation means the thunk for `_eval.region` is evaluated at most once and cached automatically by the Nix evaluator. This is structurally identical to `CachedAttribute`'s identity hash map: the hash map key is the node identity (Kiama uses an `IdentityHashMap[T, Option[U]]`; gen-scope uses the node's `id` as the attrset key), and the cached value is the thunk's forced result. The sentinel-based cycle detection from Figure 6 is replaced by Nix's native infinite-recursion detection, which serves the same purpose. The critical design insight is that caches are co-located ON nodes (like JastAdd's field-based caching, unlike Kiama's separate attribute objects), but achieve the same O(1) amortized access.

   - **Files:** `eval` function in gen-scope, `_eval` construction during `children`/`derived-children` wrapping
   - **Mapping:** `CachedAttribute.apply(t)` = Nix attrset lazy thunk evaluation; `CachedAttribute.memo` = the `_eval` attrset itself; `memo.get(t) match { case Some(Some(u)) => u }` = subsequent attrset access returning cached value

2. **`paramAttr` = Parameterized Attributes (S3, Figure 4).** gen-scope's `paramAttr f self id param` constructor creates attributes parameterized by an additional value. The signature `f self id param` corresponds to Kiama's `paramAttr { n => { case ... } }` where the outer function receives the parameter and the inner function receives the node. Used for value-indexed attribute families such as name lookups parameterized by the identifier being sought.

   - **Files:** `paramAttr` in gen-scope attribute combinators
   - **Mapping:** Kiama `paramAttr (f : S => T ==> U)` = gen-scope `paramAttr f self id param` where `S` = param type, `T` = node id, `U` = result

3. **`circular` = Circular Fixed-Point Attributes (S2.2, Figure 3-4).** gen-scope's `circular { init; eq; maxIter; } f self id` constructor evaluates an attribute by iterating from `init` until `eq prev next` returns true or `maxIter` is reached. This implements the Magnusson-Hedin algorithm that Kiama wraps in `CircularAttribute`. The `init` parameter corresponds to Kiama's `circular(Set[String]())`, the convergence check replaces Kiama's built-in equality, and `maxIter` adds a safety bound absent in the original.

   - **Files:** `circular` in gen-scope attribute combinators
   - **Mapping:** Kiama `circular (init : U) (f : T => U)` = gen-scope `circular { init; eq; maxIter; } f self id`; Magnusson-Hedin iteration loop = gen-scope's recursive `go` with convergence check

4. **`collectionAttr` = Collection Attributes (S7, future work realized).** Kiama's S7 mentions collection attributes as planned future work, citing Boyland (2005) and Magnusson, Ekman, Hedin (2007). gen-scope implements this as `collectionAttr { traverse; extract; combine; filter; }`, which traverses the scope graph along a specified axis (imports, children, siblings, ancestors, custom label, or arbitrary function), extracts values from matching nodes, and folds them with `combine`. This realizes what Sloane described as "extending attribute grammars with collection attributes -- evaluation and applications."

   - **Files:** `collectionAttr` in gen-scope attribute combinators
   - **Mapping:** Boyland/Magnusson's collection attributes (Kiama ref [4,15]) = gen-scope `collectionAttr`; the `traverse` parameter generalizes Silver's fold-over-tree to arbitrary graph traversal strategies

**gen-scope (MINOR -- conceptual influence)**

5. **Inherited attributes via `inherit'`.** gen-scope's `inherit' { resolve }` walks the parent chain until `resolve node` returns non-null. This captures the same pattern as Kiama's `childAttr` and parent-matching inherited attributes (S2.1 `globmin`), but inverts the perspective: Kiama matches on the parent to define the child's value, while gen-scope walks upward from the child. Both achieve the same result -- propagation of values down the tree without explicit copy rules.

### Relevance to Den v2 HOAG Pipeline

The central thesis of Kiama -- that a sufficiently expressive host language can serve as the AG evaluator, eliminating the need for a custom generator -- is the architectural foundation of den v2. The mapping is:

| Kiama concept                          | Scala mechanism                                                  | Den v2 / Nix mechanism                                               |
| -------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------- |
| CachedAttribute memoization            | IdentityHashMap in attribute objects                             | `_eval` lazy attrset on scope nodes; Nix thunk evaluation = memo     |
| Demand-driven scheduling               | `apply()` evaluates on first access                              | Nix lazy evaluation: thunks forced only when demanded                |
| Pattern-matching equations             | Scala `case` in anonymous functions                              | Nix `if/else` chains and pattern matching in attribute bodies        |
| Circular fixed-point                   | `CircularAttribute` iterates to convergence                      | `circular` combinator with `eq`-based convergence check              |
| Parameterized attributes               | `paramAttr` curried function                                     | `paramAttr f self id param`                                          |
| Trait-based modularity                 | Scala traits + mixin composition                                 | Aspect composition + gen-derive rule dispatch                        |
| Dynamic extension (`+=`)               | Partial function list with scoped activation                     | gen-derive's rule override/priority system with fixpoint convergence |
| Host-language laziness as AG evaluator | Scala lazy vals (limited -- Kiama uses explicit caching instead) | Nix lazy evaluation (native -- every attrset value is a lazy thunk)  |

The last row highlights a key difference: Kiama notes (S6) that Scala's lazy values could theoretically replace explicit caching, but doing so "would require attribute definitions to reside in the abstract syntax classes, which goes against modularity." Nix does not have this constraint. Because Nix attrsets are inherently lazy and `lib.fix` provides self-referential binding, gen-scope achieves what Kiama could not -- true host-language laziness as the evaluation mechanism with no explicit caching infrastructure, while preserving full modularity (attributes are defined externally and composed into `_eval` at node construction time). **Nix IS the AG evaluator** in a way that Scala could not fully be for Kiama.

The HOAG pipeline in den v2 operates as follows, with Kiama concepts at each stage:

1. **Graph construction** -- `buildNodes` creates scope graph nodes (entities, aspects) with P/I edges. Each node is a minimal descriptor.
2. **Attribute definition** -- Consumer (den) defines attributes as `self: id: value` functions. These are the "equations" in Kiama terms.
3. **`_eval` wrapping** -- `eval` wraps each node with `_eval`, a lazy attrset of attribute computations. This is the `CachedAttribute` instantiation.
4. **Demand-driven evaluation** -- When den needs a value (`result.get "host:igloo" "resolved-aspects"`), Nix forces the corresponding `_eval` thunk. The thunk may recursively force other `_eval` entries on other nodes -- inherited attributes walk parent chains, synthesized attributes walk children, import-following attributes traverse I edges. All of this is scheduled by Nix's native lazy evaluator.
5. **Circular convergence** -- Pipe convergence (where multiple aspects contribute to a collection that feeds back into aspect resolution) uses `circular` attributes that iterate to a fixed point, directly implementing the liveness-analysis pattern from S2.2.
6. **Collection aggregation** -- `collectionAttr` realizes the S7 future work for aggregating contributions from multiple scope graph positions into pipes and collections.

## Appendix: Follow-up Work

### Unexploited Ideas

- **Dynamic attribute extension with scoped activation (S4.2).** Kiama's `+=` operator and `using` block provide run-time attribute equation extension with guaranteed cleanup. gen-scope's attributes are currently static -- defined once at `eval` time. A dynamic extension mechanism would allow aspects to inject additional attribute equations at evaluation time, useful for plugin systems or conditional attribute augmentation. The scoped `using` pattern (try/finally semantics) maps naturally to Nix's `let ... in` scoping but would require gen-scope to support attribute equation composition post-construction.

- **`isDefinedAt` domain checking (S3.2, Figure 6).** Kiama's `CachedAttribute` inherits `isDefinedAt` from `PartialFunction`, enabling completeness checking -- verifying that every node type has a defining equation. gen-scope attributes are total functions (`self: id: value`) that must handle all node types or throw. A partial-attribute mechanism with domain introspection could catch missing equation cases at definition time rather than evaluation time.

- **Structural property initialization via Product trait (S3.1).** Kiama's `Attributable` automatically derives `parent`, `next`, `prev`, `index` from case class constructor fields using Scala's `Product` interface. gen-scope requires explicit `parent` fields on node descriptors. An auto-derivation mechanism for structural properties from node declaration shape (similar to `buildNodes` but more granular) could reduce boilerplate for complex node hierarchies.

### Potential New Libraries or Features

- **gen-scope dynamic attributes.** A `dynamicAttr` combinator that wraps an attribute with an extension list, supporting `extend` (add equations) and `scope` (delimited activation). This would directly implement Kiama S4.2 in Nix. Scope: moderate -- requires changes to `_eval` construction to compose base + extension equations. Interaction: gen-derive could use this to inject rule-produced attribute equations during fixpoint convergence, rather than requiring all attributes to be defined upfront.

- **gen-scope partial attributes with domain checking.** An `assertComplete` wrapper that takes a set of node types and an attribute definition, verifying at construction time that the attribute's pattern covers all declared types. Scope: small -- purely a validation wrapper. Interaction: gen-schema's kind declarations could provide the node type universe for completeness checking.

- **gen-scope attribute profiling.** Kiama's performance evaluation (S5) highlights that knowing which attributes are evaluated, how often, and whether caching is beneficial is important for optimization. A `profile` wrapper on `eval` that counts thunk forces per attribute per node type would help identify over-evaluation in large den configurations. Scope: moderate -- requires instrumenting `_eval` without breaking laziness.

### Research Directions

- **Optimal caching granularity.** Kiama caches in attribute objects; JastAdd caches in tree nodes; gen-scope caches in co-located `_eval` attrsets. The trade-off between memory footprint and access speed across these strategies has not been formally characterized for lazy host languages where the evaluator itself provides memoization. A formal analysis of when explicit caching (gen-scope's `_eval`) adds value over bare Nix laziness would inform whether some attributes can safely omit `_eval` wrapping.

- **Incremental re-evaluation.** Kiama's dynamic extension mechanism (S4.2) and the broader AG literature on incremental evaluation (Reps, Teitelbaum 1984) suggest a path toward incremental den reconfiguration: when an aspect changes, only affected attribute values should be recomputed. Nix's content-addressed store provides some of this at the derivation level, but attribute-level incrementality within a single evaluation is an open problem for Nix-embedded AGs.

- **Static completeness guarantees for embedded AGs.** Kiama notes (S6) that sealed case classes give partial completeness checking via Scala's exhaustiveness warnings. Nix has no equivalent. Whether Nix's type-level tooling (e.g., NixOS module type declarations) can provide analogous coverage guarantees for AG equations is unexplored. gen-schema's kind/type system could potentially serve as the "sealed class" equivalent, constraining the node type universe.
