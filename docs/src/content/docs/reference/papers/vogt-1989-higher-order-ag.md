---
title: Vogt et al. (1989) -- Higher-Order Attribute Grammars
description: Our reading of Higher order attribute grammars.
source:
  - den-ag-design:used/summaries/vogt-1989-higher-order-ag.md
---

> H. Vogt, S. D. Swierstra, and M. Kuiper, "Higher order attribute grammars," *PLDI89: Programming Language Design & Implementation*, pp. 131–145, 1989. doi: [10.1145/73141.74830](https://doi.org/10.1145/73141.74830) · [open access](https://dspace.library.uu.nl/handle/1874/16594) · [summary](/reference/papers/vogt-1989-higher-order-ag/).

## Paper Summary

Vogt, Swierstra, and Kuiper address a fundamental limitation of classical attribute grammars (AGs): the rigid separation between the structure tree (built by the parser) and the attributes (computed during evaluation). In conventional AGs, the parse tree is fixed before semantic analysis begins, which means multi-pass compilation -- where intermediate representations are constructed, transformed, and re-analyzed -- cannot be expressed naturally within the AG formalism. Programmers must resort to encoding intermediate languages as attribute values and manually threading them through semantic functions, producing specifications that are difficult to write and harder to understand.

Higher-Order Attribute Grammars (HAGs) remove this boundary by introducing **non-terminal attributes** (NTAs): attributes whose values are themselves structure trees. During attribute evaluation, when an NTA is computed, the parse tree is *expanded* at the corresponding leaf -- the virtual non-terminal is replaced by the computed subtree, which then becomes part of the attributed tree and participates in further attribute evaluation. The term "higher order" is chosen by analogy with higher-order functions: just as a higher-order function can return or accept functions, a higher-order AG can compute and consume tree structures as attribute values.

The paper formalizes HAGs by extending the standard AG definition (Definition 3.1) with NTAs (Definition 3.7), virtual vs. instantiated non-terminals (Definition 3.8), labeled trees with virtual leaves (Definition 3.9), and correct typing of NTA semantic functions (Definition 3.10). The Attribute Evaluation Algorithm (Figure 13) extends the classical work-list algorithm from Knuth (1968) and Reps (1982) with a tree-expansion step: when a selected work-list item is an NTA, the labeled tree is expanded at the corresponding virtual leaf, new dependency edges and attribute instances are added to the work-list, and evaluation continues.

Two correctness concerns arise. First, an NTA must not depend on its own synthesized attributes -- those are only available *after* expansion. The paper handles this by defining Extended Direct Dependency Predicates (EDDP, Definition 3.12), which add synthetic dependencies from each NTA to all synthesized attributes of its non-terminal, ensuring that expansion precedes attribute computation on the expanded subtree. Lemma 3.1 proves that every virtual NTA will be computed if and only if the EDDP-augmented dependency graph remains acyclic during evaluation. Second, the tree must not expand indefinitely. Lemma 3.2 provides a sufficient condition: if on every path in every structure tree a particular NTA occurs at most once, expansion is finite. This amounts to requiring that each NTA roots a "non-recursive" separate context-free grammar -- a decidable property (polynomial in the grammar size).

Theorem 3.2 combines these into the well-definedness criterion: a HAG is well-defined if it is complete, no partial tree contains EDDP-cycles, and NTAs satisfy the finite-expansion condition.

For efficient evaluation, the paper reduces a HAG to an ordinary AG (Definition 4.1) by replacing NTA occurrences with inherited attributes (X.atree). Theorem 4.1 shows that if the reduced AG is an Ordered Attribute Grammar (OAG, per Kastens 1980), then the HAG is ordered. Visit-sequences for the HAG (HVS, Definition 4.3) are derived from the OAG visit-sequences by mapping X.atree evaluations to NTA expansion instructions. The entire check -- reduction, OAG test, visit-sequence derivation, finite-expansion check -- runs in time polynomial in the grammar size.

The running example throughout is a four-step compiler for expressions in an Algol68-like language: parsing, operator-precedence restructuring, type checking with coercion insertion, and code generation. Each step produces an intermediate structure tree consumed by the next, demonstrating that HAGs naturally express multi-pass compilation as a single unified specification.

## Key Concepts

- **Non-Terminal Attributes (NTAs):** Attributes whose values are parse trees derivable from the attribute's non-terminal. During evaluation, the virtual non-terminal leaf is replaced by the computed tree, which is then attributed. (S2.4, Definition 3.7)

- **Virtual vs. Instantiated Non-Terminals:** A virtual NTA is an unevaluated leaf (depicted as an open circle); once its defining semantic function fires, it becomes an instantiated non-terminal (a filled circle) with a fully expanded subtree. (Definition 3.8)

- **Tree Expansion During Evaluation:** The Attribute Evaluation Algorithm extends the standard work-list algorithm: evaluating an NTA triggers tree expansion, adds new attribute instances and dependencies, and extends the work-list. (Figure 13)

- **Extended Direct Dependency Predicates (EDDP):** For each NTA X in a production, all synthesized attributes of X are made dependent on X itself. This prevents an NTA from depending on attributes that only exist after its own expansion. (Definition 3.12, Lemma 3.1)

- **Finite Expansion Condition:** If no NTA occurs twice on any path in any structure tree, expansion terminates. Equivalently, each NTA roots a non-recursive context-free grammar. This is decidable in polynomial time. (Lemma 3.2)

- **Well-Definedness Theorem:** A HAG is well-defined if complete, EDDP-acyclic for all partial trees, and satisfying the finite expansion condition. (Theorem 3.2)

- **Reduction to OAG:** A HAG is transformed into a conventional AG by replacing NTAs with inherited attributes. If the reduced AG is Ordered (Kastens 1980), the HAG is ordered. (Theorem 4.1)

- **Visit-Sequences for HAGs (HVS):** Derived from OAG visit-sequences by mapping X.atree evaluations to expansion instructions. The expansion-then-visit discipline ensures that no descendant of a virtual non-terminal is visited before instantiation. (Definition 4.3)

- **Bounded Well-Definedness:** Allows recursive NTA expansion (factorial example), giving the power to define recursive functions in the AG, but finite expansion is no longer guaranteed. (S3.3)

- **Term Language / Signatures:** Structure trees are represented as terms in a signature-generated term language, providing the linear notation used in semantic functions to construct NTA values. (Definitions 2.1--2.3)

## Implementation Mapping

### Current Usage in Gen Ecosystem

**gen-scope (Major -- core implementation)**

gen-scope is described as a "hybrid HOAG/RAG evaluator" and directly implements Vogt's NTA concept in two forms:

- **`children` attribute as NTA (S2.4):** The `children` attribute on every scope node is a synthesized attribute whose value is a set of new nodes -- exactly the NTA concept. When `eval` processes a node, it evaluates `children self id`, which returns `{ childId = { id, type, parent, decls }; }`. Each returned child is wrapped with a co-located `_eval` cache (the `CachedAttribute` from Sloane 2010) and becomes a fully attributed node in the scope graph. This maps directly to S2.4.1 ("Part of the structure tree := attribute value"): the tree structure itself is a computable attribute, and evaluation expands the tree on demand.

- **`derived-children` as second-stage NTA (extends S2.4):** gen-scope introduces a stratified extension not in the original paper. `derived-children` is a second NTA evaluation stage that can read attributes of nodes produced by the first-stage `children`. In Vogt's formalism, the EDDP ensures synthesized attributes of an NTA's children are only available after expansion. gen-scope's two-stage design respects this by guaranteeing that `derived-children` runs after `children` nodes exist and their attributes are available. This is a practical refinement of the NTA stratification concept.

- **Demand-driven evaluation replaces visit-sequences:** Where the paper derives visit-sequences (HVS, Definition 4.3) for traversal order, gen-scope leverages Nix's native lazy evaluation as the scheduling mechanism. Nix's lazy attrset semantics automatically enforce the EDDP constraint: a synthesized attribute of a child node is only computed when demanded, which cannot happen before the child exists (i.e., before `children` has been evaluated for the parent). The `_eval` co-located cache ensures O(1) amortized access once computed, achieving the same efficiency as OAG visit-sequences without explicit traversal scheduling.

- **`parseParent` and finite expansion:** The paper's finite expansion condition (Lemma 3.2) requires that NTAs don't recur on paths. gen-scope's `parseParent` function (id -> parentId) provides O(depth) node resolution and implicitly encodes the tree structure. In practice, den's scope graph construction guarantees finite expansion because entity hierarchies (host -> user -> home) are bounded and non-recursive.

- **Concrete files/functions:** `eval` (entry point), `buildNodes` (root construction with algebraic graph primitives), `_eval` (memoization cache co-located on nodes), `inherit'` (inherited attribute combinator), `circular` (fixpoint attributes), `collectionAttr` (aggregation across tree structure).

### Relevance to Den v2 HOAG Pipeline

Den v2 is a demand-driven HOAG over scope graphs, where the Vogt (1989) formalism structures the entire evaluation architecture:

- **Tree structure is a computable attribute.** Den's `resolve.to` effects create new scope nodes -- this is NTA expansion. When a policy dispatches a `spawn` effect, a new scope node is synthesized as a child of the current scope, exactly as an NTA value expands the structure tree in Vogt S2.4. The scope graph grows during evaluation, not before it.

- **`synthesize` in scope-engine is a HOAG rule.** Each `synthesize` declaration in den v2 is a semantic function in the HOAG sense: it takes the current node's attributes (inherited and local) and computes synthesized attribute values, which may include children (NTAs) or derived-children (second-stage NTAs).

- **Parametrics resolved inline during recursive traversal.** Den's parametric aspects (those with `__args`) are analogous to the paper's bounded well-defined HAGs (S3.3): an aspect's body is only instantiated when its argument signature is satisfied by the current scope's context. This is demand-driven NTA expansion -- the subtree is latent until context provides the arguments, at which point it expands and participates in evaluation.

- **Subgraph latent, edges discovered on demand via Nix laziness.** The entire scope graph need not be materialized upfront. Nix's lazy evaluation means child nodes only exist when demanded, import edges only resolve when queried, and attribute values only compute when accessed. This maps directly to the paper's work-list algorithm (Figure 13) where virtual NTAs remain as leaves until their defining attributes are ready -- except Nix's laziness replaces the explicit work-list with implicit demand propagation.

- **EDDP enforced structurally.** The paper's EDDP (Definition 3.12) prevents NTAs from depending on their own synthesized attributes. In den v2, this is enforced by the scope graph topology: a parent scope's `children` attribute synthesizes child scopes, and child attributes can read parent attributes (inherited) but parents never read child-synthesized values as input to `children` itself. The structural guarantee replaces the static EDDP check.

- **Finite expansion via entity kind hierarchy.** Den's entity model (host, user, home) provides the non-recursive grammar property required by Lemma 3.2. Each entity kind spawns children of a different kind (host spawns users, users spawn homes), so no NTA recurs on any path. The finite expansion condition is satisfied by construction.

## Appendix: Follow-up Work

### Unexploited Ideas

- **Explicit visit-sequence derivation (S4.2, Definition 4.3).** gen-scope relies entirely on Nix laziness for evaluation order, which is correct but opaque. The paper's HVS derivation algorithm produces an explicit traversal schedule that could be used for: (a) static analysis of attribute dependencies before evaluation, (b) parallel evaluation scheduling (the paper's conclusion mentions parallel evaluation research at Utrecht), and (c) better error diagnostics when attribute cycles occur.

- **OAG orderedness checking (Theorem 4.1).** The paper provides a polynomial-time algorithm to check whether a HAG is ordered by reducing to an OAG and testing the reduced grammar. gen-scope currently discovers cycles at evaluation time via Nix's infinite recursion errors or `evalDebug`'s cycle tracing. A static orderedness check could detect problematic attribute configurations before evaluation begins.

- **Bounded well-definedness for recursive expansion (S3.3).** The paper shows that HAGs can express recursive functions (the factorial example) by allowing NTAs to recur, trading finite expansion guarantees for computational power. gen-scope currently assumes finite expansion. Bounded well-definedness could enable recursive aspect patterns -- an aspect that conditionally spawns instances of itself based on computed attributes, with a convergence guard.

- **Attribute value := part of the structure tree (S2.4.2).** The paper describes storing *existing* subtrees as attribute values (not just creating new ones). gen-scope implements the NTA direction (compute trees, expand into structure) but does not provide a first-class mechanism to capture and store an existing subtree as a reified attribute value for later re-attachment or analysis.

- **Semantic functions as attributed trees (S5, Conclusion).** The paper's conclusion sketches a unification where semantic functions themselves are defined by attributed trees, merging the tree and function formalisms. This would mean attribute rules are not opaque Nix functions but inspectable, analyzable tree structures -- enabling program transformation and optimization of the evaluation itself.

### Potential New Libraries or Features

- **gen-visit: Static dependency analysis.**
  A library that takes gen-scope attribute definitions and derives the dependency graph statically (without evaluating), following the HAG-to-reduced-AG transformation (Definition 4.1). Could check orderedness (Theorem 4.1), detect potential cycles, and produce visit-sequence metadata for debugging. Scope: medium. Would consume gen-scope attribute declarations as data, produce gen-graph-compatible dependency graphs.

- **gen-scope: Recursive NTA support with convergence guards.**
  Extend `children` to support bounded well-definedness (S3.3): a `recursive-children` combinator that allows self-referential child synthesis with an explicit termination predicate and iteration bound. Would enable patterns like "keep spawning monitoring sidecars until coverage threshold met." Scope: small extension to gen-scope. Interacts with `circular` attribute combinator for convergence semantics.

- **gen-scope: Subtree reification combinator.**
  A `captureSubtree self id` combinator that captures the subtree rooted at `id` as a serializable attribute value (S2.4.2 direction). Useful for den v2 scenarios like template instantiation -- capture an aspect's resolved subtree, store it, and re-attach it in a different scope context. Scope: small. Interacts with `buildNodes` for re-attachment.

- **gen-scope: Parallel attribute evaluation hints.**
  Following the paper's conclusion on parallel evaluation, annotate attributes as independently evaluable. gen-scope could emit parallelism metadata that a Nix evaluator extension (or future Nix with parallel evaluation) could exploit. Scope: speculative, depends on Nix runtime evolution.

### Research Directions

- **Incremental HOAG evaluation.** The paper's work-list algorithm (Figure 13) naturally supports incrementalism -- when the tree changes, only affected attribute instances need re-evaluation. Combined with Reps' work on incremental AG evaluation (cited by the paper), this could enable incremental den evaluation where changing one aspect only recomputes affected scope graph regions. The challenge in Nix is that lazy thunks cannot be selectively invalidated; this would require either external memoization or a modified evaluator.

- **Higher-order attribute grammars over scope graphs with custom edge labels.** The paper's NTAs operate on tree structures. Den v2 operates on scope graphs (Neron 2015) with import edges and custom edge labels (van Antwerpen 2018). The formal interaction between HOAG tree expansion and scope graph resolution is unexplored: when an NTA expansion adds a node with import edges, how does this affect the resolution calculus? Can the EDDP be extended to account for resolution-path dependencies?

- **Demand-driven NTA expansion with constraint propagation.** Statix (van Antwerpen 2016) uses constraint-based scope graph resolution. Combining Vogt's demand-driven NTA expansion with Statix-style constraints could yield a system where tree expansion is guided by constraint satisfaction -- expand an NTA only when a constraint requires a name that would be declared in the expanded subtree. This would be a lazy, constraint-driven variant of HOAG evaluation.

- **Formal verification of gen-scope's EDDP compliance.** gen-scope relies on structural properties of consumer-defined attribute functions to satisfy EDDP. A formal treatment could prove that gen-scope's two-stage children/derived-children protocol correctly implements EDDP under Nix's lazy evaluation semantics, providing a soundness guarantee for the ecosystem.
