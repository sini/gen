---
title: Van Antwerpen et al. (2016) — A Constraint Language for Static Semantic Analysis Based on Scope Graphs
description: Our reading of A constraint language for static semantic analysis based on scope graphs.
source:
  - den-ag-design:used/summaries/van-antwerpen-2016-statix-constraint-scope-graphs.md
---

> H. van Antwerpen, P. Néron, A. Tolmach, E. Visser, and G. Wachsmuth, "A constraint language for static semantic analysis based on scope graphs," *POPL '16: The 43rd Annual ACM SIGPLAN-SIGACT Symposium on Principles of Programming Languages*, pp. 49–60, 2016. doi: [10.1145/2847538.2847543](https://doi.org/10.1145/2847538.2847543) · [open access](http://dl.acm.org/ft_gateway.cfm?id=2847543&type=pdf) · [summary](/reference/papers/van-antwerpen-2016-statix-constraint-scope-graphs/).

## Paper Summary

Van Antwerpen, Neron, Tolmach, Visser, and Wachsmuth address a fundamental tension in language tooling: name resolution and type checking are conceptually separate concerns but practically interdependent. In languages with record field projection (`r.x`) or module imports, resolving a name requires knowing a type, which itself requires resolving other names. The paper's contribution is a constraint language that unifies name binding and typing into a single declarative framework built on the scope graph formalism of Neron et al. (2015).

The architecture follows a clean two-phase design (Fig. 1): a language-specific **extractor** produces constraints from the AST, and a language-independent **solver** resolves them. Three constraint categories partition the problem: scope graph constraints (CG) define binding structure, resolution constraints (CRes) express name resolution requirements and uniqueness/completeness properties, and typing constraints (CTy) express type consistency via term equality and type assignment.

The key technical innovation is support for **incomplete scope graphs** — scope graph constraints may contain variables (particularly scope variables as targets of direct edges), allowing the solver to incrementally resolve constraints even when the full graph structure is not yet known. This is critical for type-dependent name resolution: when resolving `e.x`, the scope to search for `x` depends on the type of `e`, which may not yet be determined. The paper models this with scope variables (`varsigma`) that act as placeholders in import edges, resolved as type information becomes available.

The resolution calculus (Section 3.3, Fig. 9) extends Neron 2015 with two significant generalizations. First, edge labels are generalized beyond the fixed P (parent) and I (import) labels, with a parameterizable label set L. Second, the well-formedness predicate WF and visibility ordering < are now parameters rather than fixed: WF is defined by a regular expression E over label sequences (tested via Brzozowski derivatives), and < defines a lexicographic ordering on paths. Section 3.4 and Figure 10 demonstrate several instantiations: lexical scope alone (P\*, D < P), non-transitive imports (P\*.I?, D < P, D < I, I < P), transitive imports (P\*.TI\*, D < P, D < TI, TI < P), and combinations thereof.

The resolution algorithm (Section 4, Fig. 11) operates on incomplete scope graphs, returning either a set of declarations or U (unknown) when insufficient information exists. Environment functions return pairs of (result flag, declarations) where the flag is T (total — all visible declarations computed) or P (partial — scope variables still unresolved). The constraint solver (Fig. 12) is a non-deterministic rewrite system over tuples (C, G, psi), applying six rules: S-RESOLVE (name resolution via the algorithm), S-ASSOC (scope association lookup), S-EQUAL (unification), S-UNIQUE (uniqueness checking), S-SUBNAME (name collection subset), and S-TYPEOF (type assignment).

The paper proves three formal results. Lemma 1 establishes soundness and completeness of the resolution algorithm on ground scope graphs. Lemma 2 extends soundness to incomplete scope graphs: any resolution returned on an incomplete graph is valid in all ground instances. The stability property (G down-arrow o) ensures that if a resolution is found, it is the same across all ground completions. Lemma 4 proves the constraint solver sound: any solution it produces satisfies the constraint semantics. Completeness of the solver is explicitly left as future work.

The model language LMR (Language with Modules and Records) demonstrates the framework's expressiveness across declarations, lexical scoping, module imports (transitive and non-transitive), associated scopes, record field declarations, field access with type-dependent name resolution, record initialization completeness checking, and Pascal-style `with` expressions.

## Key Concepts

- **Constraint-based scope graph specification**: Scope graphs are defined declaratively via constraints (CG) rather than constructed imperatively. The graph emerges from constraint satisfaction, enabling incomplete graphs during solving.

- **Three-category constraint taxonomy**: CG (scope graph structure), CRes (resolution and collection properties), CTy (typing) — cleanly separating concerns while allowing interdependence through shared variables.

- **Incomplete scope graphs with scope variables**: Direct edge constraints may target scope variables (S --l--> varsigma), enabling incremental resolution as type information fills in placeholders. The algorithm signals U (unknown) when resolution depends on unresolved variables.

- **Parameterized resolution calculus**: The well-formedness predicate (regular expression E over label sequences) and visibility ordering (< on labels) are parameters, not hardcoded. This enables the same calculus to express lexical scope, non-transitive imports, transitive imports, includes, and arbitrary combinations (Fig. 10).

- **Brzozowski derivative for path well-formedness**: The algorithm uses Brzozowski derivatives (l^{-1} re) to incrementally check whether a path prefix remains in the language of the well-formedness regular expression, avoiding repeated full-path checks.

- **Shadowing operator on declaration sets**: The operator D1 triangle-right D2 keeps declarations from D1, plus declarations from D2 whose name does not appear in D1. Extended to pairs with result flags for the incomplete case.

- **Stability on incomplete graphs**: A resolution on an incomplete graph G is stable (G down-arrow o) when all ground instances yield the same resolution set. The algorithm guarantees stability for any resolution it returns (Lemma 2).

- **Name collections with uniqueness and completeness**: D(S) (declarations in scope), R(S) (references in scope), V(S) (visible declarations from scope). Constraints !N (uniqueness) and N1 subset N2 (subset) express properties like "no duplicate field names" and "all record fields initialized."

- **Type-dependent name resolution via association constraints**: D --assoc--> S links a declaration to its associated scope. For field access, a chain of constraints connects the expression type to a declaration variable to an associated scope variable, threading name resolution through type resolution.

- **Non-deterministic constraint solver**: The solver (Fig. 12) branches when a reference resolves to multiple declarations, exploring all possibilities. Each branch maintains its own substitution state.

## Implementation Mapping

### Current Usage in Gen Ecosystem

**gen-scope (Minor influence)**

The INDEX.md records this paper as a minor influence on gen-scope, specifically for "Statix-style constraint patterns for structural subtyping queries." gen-scope's resolution is fundamentally traversal-based (Neron 2015), not constraint-solving, so the core algorithm (Fig. 11) and solver (Fig. 12) are not implemented. However, specific design patterns from the paper appear:

- **Parameterized visibility policies** (Section 3.4, Fig. 10): gen-scope's `query` combinator accepts `localShadowsImport`, `importShadowsParent`, and `transitiveImports` parameters, which correspond to instantiations of the paper's label ordering and well-formedness regex. The default D < I < P policy matches the paper's "non-transitive imports" row. The `followEdge` function (from van Antwerpen 2018, but prefigured here in the generalized label set L) enables custom edge labels beyond P and I.

- **Well-formedness as a structural constraint**: gen-scope's `_seen` tracking in `query` (preventing import self-resolution) corresponds to the seen-imports set I in rule (N) and the seen-scopes set S in rule (T) of the resolution calculus. The paper formalizes what gen-scope implements operationally.

- **Structural subtyping queries**: gen-scope's `subtypeOf` combinator expresses "are all declarations in scope A also in scope B?" — which maps to the paper's V(S) visible name collection and the subset constraint N1 subset N2 (Section 2.4). The Statix pattern is: if the visible declarations of one scope are a subset of another's, structural subtyping holds.

**gen-aspects (indirect, via TERMINOLOGY.md)**

The TERMINOLOGY.md lists "Constraints" as a core term with provenance "van Antwerpen 2016 (constraint-based scope graphs)." In gen-aspects, constraints are pruning rules that restrict resolution or composition and propagate via graph ancestry — a conceptual borrowing of the paper's constraint vocabulary applied to aspect composition rather than name resolution.

### Relevance to Den v2 HOAG Pipeline

Den v2's demand-driven HOAG over scope graphs shares the paper's graph structure but diverges at the resolution mechanism: den resolves eagerly via traversal (Neron 2015 calculus, implemented in gen-scope) where Statix solves constraints. The paper's contributions inform den v2 in several ways:

**Specification vocabulary**: The paper provides a precise language for describing resolution policies. Den v2's `drop`, `reroute`, `edge`, and `inject` effects (TERMINOLOGY.md, Den v2 Vocabulary) can be understood as constraint-like declarations that modify the scope graph structure — `drop` corresponds to restricting reachability (removing edges from the well-formedness language), `reroute` corresponds to label substitution, `edge` corresponds to adding import edges (CG constraints), and `inject` corresponds to direct declaration emission.

**Parameterized policies via label ordering**: Den v2's per-query visibility policies (inherited from gen-scope via van Antwerpen 2018) trace back to this paper's Section 3.4. The regular expression parameterization (E) and label ordering (\<) provide the formal foundation for den's class-specific resolution: different classes (nixos, darwin, homeManager) may use different visibility policies when resolving aspects.

**Incomplete graph handling as a design pattern**: The paper's incremental solving over incomplete scope graphs (Section 4.2) validates den v2's demand-driven approach. In den, the scope graph is also "incomplete" at any given point during lazy evaluation — not all nodes and edges are materialized. The paper's stability property (Lemma 2) provides theoretical confidence that resolving against a partially-evaluated graph yields results consistent with full evaluation, which is exactly what Nix's lazy evaluation guarantees operationally.

**Name collections for pipe/collection aggregation**: Den v2's collections (named data aggregation points) parallel the paper's name collections N. The `pipe.gather pred` operation (traverse and collect from matching scopes) is analogous to computing V(S) with a filter predicate. The `pipe.source pred` (only matching scopes contribute) mirrors the paper's scope-bounded collection semantics.

**Constraint vocabulary for neededBy**: Den's `neededBy` (reverse I edges) can be formally understood as the paper's import constraints with inverted directionality. Where the paper writes S --I--> x_R (scope S imports the associated scope of x's resolution), neededBy declares the inverse: "aspect A should be imported by any scope matching a selector." The constraint framework provides the formal vocabulary even though den doesn't use constraint solving.

## Appendix: Follow-up Work

### Unexploited Ideas

**Non-deterministic branching in resolution (Section 4.5, Fig. 12, S-RESOLVE)**: The solver branches when multiple declarations match. gen-scope's `query` returns a single result (most specific), and `queryAll` returns all results, but there is no branching exploration of alternatives. For den v2 policies that need to reason about ambiguity (e.g., "if this reference is ambiguous, apply a tiebreaker"), a structured branching mechanism could be useful.

**Uniqueness and completeness constraints (Section 2.1, 2.4)**: The !D(S) uniqueness constraint and V(S) approximately-equal R(S) completeness constraint have no direct gen-scope analogue. gen-scope can detect ambiguity via `ambiguous`, but cannot declaratively assert "no duplicate declarations in this scope" or "all expected references are present." These would be valuable for den's configuration validation.

**Scope graph constraints as a specification language (Section 2, Fig. 6)**: The full constraint extraction framework — where an AST walk produces constraints rather than directly building a graph — is not implemented. gen-scope builds graphs directly via `buildNodes` and algebraic constructors. A constraint-based specification layer would enable more declarative graph construction, potentially simplifying den's entity declaration processing.

**Brzozowski derivatives for path validation (Section 4, algorithm)**: The technique of using regular expression derivatives to incrementally validate resolution paths during traversal is not implemented. gen-scope's `query` uses hardcoded path logic (local -> imports -> parent). A derivative-based approach would enable arbitrary path well-formedness policies without per-policy code.

**Association constraints for type-scope bridging (Section 2.4)**: The D --assoc--> S mechanism for connecting declarations to associated scopes via type resolution is not directly used. gen-scope has `followEdge` for explicit custom edges, but not the type-driven dynamic edge discovery that association constraints enable.

### Potential New Libraries or Features

**gen-scope: Declarative constraint layer**
A thin constraint DSL over gen-scope's graph construction, allowing users to declare scope structure via constraints rather than imperative `buildNodes` calls. Scope: moderate (200-400 lines). Would consume gen-scope and gen-algebra. The constraint extraction pattern (Fig. 6) provides the template: each user declaration produces constraints, a simple solver (without unification — den doesn't need type inference) resolves scope variables and validates well-formedness.

**gen-scope: Completeness checking combinator**
A new combinator `complete { expected; actual; } self id` that checks V(S) approximately-equal R(S) style properties. Useful for den v2 to validate that all declared entity fields are initialized, all required aspects are present, etc. Scope: small (50-100 lines). Direct implementation of Section 2.4's completeness constraints.

**gen-scope: Regular expression path policies**
Replace the boolean parameters (`localShadowsImport`, `importShadowsParent`, `transitiveImports`) with a `policy = { wellFormedness = "P*.I?"; ordering = { D = 0; I = 1; P = 2; }; }` parameter that accepts the paper's formal parameterization directly. Would enable expressing all policies from Fig. 10 and arbitrary custom policies. Scope: moderate (150-300 lines). The Brzozowski derivative implementation is straightforward in Nix.

### Research Directions

**Incremental constraint resolution**: The paper notes incremental evaluation as an open problem (Section 5, "many applications for semantic analysis require efficient incremental computation"). In the Nix context, where evaluation is batch (not interactive), the question becomes: can Nix's lazy evaluation be leveraged as a form of incremental computation, where only demanded constraints are solved? gen-scope's `_eval` memoization already achieves this for attributes; extending it to constraint satisfaction would require tracking which constraints contributed to which resolutions.

**Constraint-based configuration validation**: The paper's constraint framework could inform a declarative validation language for den configurations. Rather than imperative assertions ("throw if X"), users would declare constraints ("!D(S) for scope S" meaning "no duplicate declarations"), and the framework would check satisfiability and produce targeted error messages. This aligns with the paper's vision of constraint-based analysis producing partial solutions with residual unsolvable constraints translatable to error messages (Section 5, "Prototype Implementation").

**Completeness guarantees for scope graph resolution**: The paper proves soundness but not completeness of the constraint solver. For den, the analogous question is: does gen-scope's traversal-based resolution find all resolutions that a constraint-based approach would? Since gen-scope implements the Neron 2015 calculus directly, and this paper proves the calculus sound and complete on ground graphs (Lemma 1), the answer is yes for fully-evaluated graphs. The open question is whether Nix's lazy evaluation introduces incompleteness by not forcing all edges — a formal treatment would require characterizing which evaluations are "sufficiently forced" for resolution completeness.
