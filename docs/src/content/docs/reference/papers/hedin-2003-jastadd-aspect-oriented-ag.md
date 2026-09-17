---
title: 'Hedin & Magnusson (2003) -- JastAdd: An Aspect-Oriented Compiler Construction System'
description: Our reading of JastAdd—an aspect-oriented compiler construction system.
source:
  - den-ag-design:used/summaries/hedin-2003-jastadd-aspect-oriented-ag.md
---

> G. Hedin and E. Magnusson, "JastAdd—an aspect-oriented compiler construction system," *Science of Computer Programming*, vol. 47, no. 1, pp. 37–58, 2002. doi: [10.1016/s0167-6423(02)00109-0](<https://doi.org/10.1016/s0167-6423(02)00109-0>) · [open access](https://www.sciencedirect.com/science/article/pii/S0167642302001090/pdf) · [summary](/reference/papers/hedin-2003-jastadd-aspect-oriented-ag/).

## Paper Summary

Hedin and Magnusson present JastAdd, a Java-based compiler construction system that combines two historically separate concerns: aspect-oriented modular extension and declarative attribute grammar evaluation. The central problem is the **cross-cutting decomposition dilemma** in compiler construction. An AST class hierarchy naturally decomposes by language constructs (expressions, statements, declarations), but compiler phases (name analysis, type checking, code generation) cut across all constructs. Neither the Visitor pattern nor traditional class hierarchies alone can cleanly separate both dimensions.

JastAdd's first contribution is **aspect-oriented imperative modules** (Jadd modules, S3). Each Jadd module declares fields and methods that are woven into AST classes at generation time, following the inter-type declaration mechanism of AspectJ. Unlike the Visitor pattern, Jadd modules can introduce both fields and methods with fully-typed parameters and return values. The paper demonstrates this advantage concretely: a type-checking aspect can declare a `typeError` boolean field on expression nodes while simultaneously defining the `typeCheck()` method that computes it -- impossible with visitors, which can only add methods with a uniform `Object visit(C, Object)` signature (S3.1). The class weaver reads all Jadd modules and generates complete AST classes, permitting free inter-module dependencies (e.g., an unparsing module accesses `typeError` computed by a type-checking module).

JastAdd's second contribution is **Reference Attributed Grammars** (RAGs, S4) as the declarative formalism. Classical AGs allow only synthesized (upward) and inherited (downward) attribute propagation along the tree spine. RAGs extend this with **reference attributes** -- attributes whose values are references to arbitrary AST nodes -- establishing cross-tree connections that bypass the parent-child hierarchy. The canonical use is name analysis: an `IdUse` node has a synthesized reference attribute `myDecl` pointing to the `Decl` node of its binding declaration (S4.1, lines 37). Once `myDecl` links are established, subsequent aspects (type checking, code generation) access declaration-site information directly through these references, using the AST itself as the symbol table (S3.3). This eliminates separate symbol table data structures.

RAG specifications are written in Jrag modules -- aspect-oriented declarative modules that declare attributes (with `syn`/`inh` modifiers) and equations (S4). The Jrag-to-Java translation (S5) is the paper's formal core:

- **Synthesized attributes** become abstract Java methods, with equations translated to concrete method implementations in subclasses (S5.1). A `syn String type` on `Decl` becomes `abstract String type()` on `Decl`, with `String type() { return "int"; }` on `IntDecl`.

- **Inherited attributes** use an interface-based dispatch mechanism (S5.2). For a class `Stmt` with inherited attribute `env`, a `ParentOfStmt` interface is generated with method `Block Stmt_env(Stmt theStmt)`. Every class containing `Stmt` components must implement this interface. The `theStmt` parameter disambiguates when a parent has multiple children of the same type with different equations. The `env()` accessor on `Stmt` delegates upward: `((ParentOfStmt) getParent()).Stmt_env(this)`.

The third contribution is **demand-driven evaluation** (S1, S4.2, S5.3). Rather than scheduling attribute evaluation in a fixed pass order, JastAdd uses an **optimal recursive evaluator**: accessing an attribute triggers a function call that computes the attribute's semantic function, caches the result, and returns it. A cache flag prevents recomputation; a cycle flag detects circular dependencies at evaluation time. This scheme handles arbitrary acyclic dependency patterns, supporting general multi-pass compilation without explicit pass ordering. The paper notes this evaluation strategy was established by Madsen (1980), Jalili (1983), and Jourdan (1984), but JastAdd's contribution is implementing it cleanly using Java's virtual method dispatch, where synthesized attributes map to methods overridden in subclasses and inherited attributes map to interface methods implemented by parent classes.

The fourth contribution is **seamless combination of declarative and imperative aspects** (S4.2). Imperative Jadd modules can freely access declaratively-defined attributes, and declarative Jrag modules can (with care) access imperatively-computed fields. The paper recommends a core of declarative aspects defining fundamental attributes (name analysis, type analysis), consumed by imperative aspects for output-oriented tasks (code generation, error reporting). This hybrid approach allows each sub-problem to be solved by whichever paradigm is most natural.

The paper also discusses interface injection (S3.4), where Jadd modules add interface implementations to AST classes, enabling cross-cutting relationships orthogonal to the class hierarchy (e.g., an `Env` interface shared by `Block`, `Method`, and `Class` nodes for name lookup). The Null pattern for reference attributes (replacing null with sentinel objects implementing Declaration interfaces) demonstrates the practical utility of this mechanism.

## Key Concepts

- **Inter-type declarations / Class weaving (S3.2):** Separate aspect modules declare fields and methods for AST classes. A class weaver generates complete classes by merging all aspects. This is the static aspect mechanism from AspectJ applied to compiler construction, providing a safer and more powerful alternative to the Visitor pattern.

- **Reference Attributed Grammars (S4, based on Hedin 2000):** Extension to AGs where attribute values can be references to arbitrary AST nodes. Enables cross-tree information flow (name analysis: `myDecl` linking use-sites to declaration-sites) without separate symbol table structures.

- **AST as symbol table (S3.3):** Once reference attributes establish use-to-declaration links, the AST itself serves as the symbol table. Other aspects extend declaration nodes with new fields (type, activation record offset) and access them via the reference links. No external lookup structures needed.

- **Demand-driven evaluation with caching (S5.3):** Attribute access triggers computation, caches the result, and detects cycles. Handles arbitrary acyclic dependencies without explicit pass scheduling. Implemented via Java methods (synthesized) and interface dispatch (inherited).

- **Synthesized-to-method, inherited-to-interface translation (S5.1-5.2):** Synthesized attributes become overridable methods on the declaring class. Inherited attributes generate `ParentOf<X>` interfaces with disambiguation parameters. This maps declarative AG specifications to standard OO dispatch.

- **Aspect modularization for both declarative and imperative code (S3, S4):** Jadd modules add imperative behavior (fields, methods, interface implementations). Jrag modules add declarative behavior (attributes, equations). Both are aspect-oriented: they specify additions to classes in separate files, woven together at generation time.

- **Interface injection for cross-cutting concerns (S3.4):** Aspect modules can add interface implementations to AST classes, relating syntactically unrelated classes. Enables patterns like a shared `Env` interface for all block-like constructs, or the Null pattern for reference attributes.

- **Composition of visitors with aspects (S3.5):** JastAdd supports both techniques simultaneously. Visitors remain useful for regular traversals; aspects handle everything else. The two interoperate: visitor methods access aspect-defined fields and attributes.

## Implementation Mapping

### Current Usage in Gen Ecosystem

**gen-scope (Minor -- demand-driven evaluation pattern, aspect-oriented extension model)**

gen-scope's evaluation architecture parallels JastAdd's demand-driven evaluator, though gen-scope implements this via Nix's native lazy evaluation rather than explicit cache-flag methods:

- **Demand-driven attribute evaluation.** JastAdd's optimal recursive evaluator (S5.3) computes an attribute only when accessed, caches it, and returns cached values on subsequent access. gen-scope's `_eval` cache co-located on each node is the same pattern implemented in Nix: each entry in the `_eval` attrset is a lazy thunk that computes on first access and is memoized by Nix's native thunk forcing semantics. The cache flag from JastAdd (S5.3) is implicit in Nix's lazy evaluation -- a forced thunk IS the cached value. The cycle flag maps to Nix's infinite recursion detection (or gen-scope's `evalDebug` for structured cycle traces). Relevant code: `eval` entry point, `_eval` attrset construction during node wrapping.

- **Aspect-oriented modular extension of attributes.** JastAdd's inter-type declarations allow separate modules to contribute attributes to the same AST class (S3.2). gen-scope's `attributes` parameter to `eval` serves an analogous role: independent attribute definitions are composed into a single attribute map, and each attribute can access any other attribute on any node via `self.get`. The key difference is timing: JastAdd weaves at code generation time (static), while gen-scope composes at evaluation time (dynamic, via the `self` accessor). This dynamic composition is more flexible -- attributes added by the consumer don't require regenerating the evaluator.

- **Inherited attribute propagation.** JastAdd's `ParentOfX` interface pattern (S5.2) propagates inherited attributes via parent delegation. gen-scope's `inherit'` combinator implements the same pattern: walk the parent chain until `resolve` returns non-null. The disambiguation parameter (`theStmt`) from JastAdd's translation is unnecessary in gen-scope because nodes are identified by unique IDs rather than positional children. Relevant code: `inherit'` combinator.

**gen-derive (Minor -- open action types with framework-owned dispatch)**

gen-derive's architecture mirrors a specific JastAdd design principle: the framework owns dispatch while actions/behavior are open for extension:

- **Framework-owned dispatch with open action types.** JastAdd's class weaver dispatches to the correct method implementation via Java's virtual method table -- the framework (weaver) owns the dispatch mechanism, while users contribute implementations in aspect modules. gen-derive follows the same separation: `dispatch` and `fixpoint` own the dispatch protocol (NAC check, condition match, override, priority, fire, classify, group), while action types are opaque -- consumers define them via `mkActions` and the consumer-provided `classify` function routes them. The consumer contributes the "aspect modules" (rules); the framework weaves them into a coherent dispatch. Relevant code: `dispatch`, `fixpoint`, `mkActions`, `classify`.

- **Aspect-as-rule modularity.** JastAdd modules are independently authored and the weaver resolves their interactions. gen-derive rules are independently authored and dispatch resolves their interactions through conflict resolution (override suppression, priority sort, specificity). The `fromFunction` pattern -- where a Nix function's argument signature IS the condition (analogous to how a Jrag equation's position in a class IS its applicability) -- directly parallels JastAdd's declarative style where the equation's class context determines where it applies.

### Relevance to Den v2 HOAG Pipeline

JastAdd's three core ideas -- demand-driven evaluation, aspect-oriented modular extension, and AST-as-symbol-table -- directly structure den v2's architecture:

- **Demand-driven evaluation is Nix laziness.** JastAdd's optimal recursive evaluator (cache flag + cycle flag + demand triggering) is exactly what Nix provides natively. Den v2's scope graph is a lazy structure: nodes exist only when demanded, attributes compute only when accessed, import edges resolve only when queried. JastAdd had to build this machinery in Java; den v2 gets it for free from the host language. The `_eval` cache on gen-scope nodes is the Nix-native version of JastAdd's per-attribute cache flag.

- **Inter-type declarations parallel `neededBy`.** JastAdd's Jadd modules add fields and methods to classes they don't own -- a type-checking aspect can extend `Decl` with a `type` attribute without modifying the name analysis module. Den v2's `neededBy` declarations serve the same role: an aspect declares that it needs to be injected into scope nodes it doesn't own, adding its content as an import edge (reverse I edge) on the target. Both mechanisms achieve the same thing: modular, after-the-fact extension of a node's behavior by independently authored units.

- **Scope graph as symbol table.** JastAdd uses the AST itself as the symbol table (S3.3): reference attributes (`myDecl`) link use-sites to declaration-sites, and subsequent aspects access declaration data through these links. Den v2's scope graph serves the identical role: scope nodes carry declarations in `decls`, reference attributes (import edges) link scopes to other scopes, and resolution via `query` (Neron 2015 D < I < P) finds declarations through these links. The scope graph IS the "symbol table" of the configuration.

- **Hybrid declarative/imperative aspect composition.** JastAdd's recommendation (S4.2) of a declarative core consumed by imperative modules maps to den v2's architecture: gen-scope provides the declarative evaluation substrate (attributes, equations as attribute functions), while gen-derive provides the imperative dispatch layer (rules, effects, fixpoint). Policies in den v2 are the imperative aspects -- they access declaratively-computed attributes on scope nodes and produce effects (spawn, edge, inject) that modify the graph.

- **Interface injection maps to class dispatch.** JastAdd's interface injection (S3.4) allows aspects to add shared interfaces to unrelated AST classes (e.g., `Env` on `Block`, `Method`, `Class`). Den v2's class system (gen-aspects) achieves a similar cross-cutting capability: a single aspect can emit content into multiple classes (`nixos`, `darwin`, `homeManager`), and classes are the "interfaces" that different output systems implement. The key classification trifecta (class key, collection key, nested key) is den's version of JastAdd's determination of which aspect contributions go where.

## Appendix: Follow-up Work

### Unexploited Ideas

- **Explicit synthesized/inherited attribute classification (S4, S5.1-5.2).** JastAdd formally distinguishes synthesized attributes (computed locally, propagated up) from inherited attributes (defined by parent, propagated down), with different translation strategies for each. gen-scope makes this distinction informally: `inherit'` is explicitly inherited, but other attributes are just `self: id:` functions with no formal classification. Formalizing synthesized vs. inherited could enable static dependency analysis and better error messages when attribute dependencies are misconfigured.

- **Equation-based attribute specification (S4).** JastAdd's Jrag equations define attributes declaratively: `type = "int"` rather than `type = self: id: "int"`. The equation notation makes the data flow explicit (which attribute of which child is being defined). gen-scope's `attributes` parameter uses opaque functions, which are more flexible but less analyzable. An equation-based layer on top of gen-scope could provide both analyzability and flexibility.

- **ParentOf interface pattern for type-safe inherited attributes (S5.2).** JastAdd generates `ParentOf<X>` interfaces that statically ensure every parent of an X node provides its inherited attributes. gen-scope has no equivalent static guarantee -- if a `children` attribute creates a node whose `inherit'` attribute walks to a parent that doesn't resolve the attribute, the error surfaces at evaluation time, not at definition time.

- **Composition of grammar modules (S7, Conclusion).** The paper's conclusion identifies grammar composition -- separately authored abstract grammar modules composed into a unified grammar -- as future work. This maps to gen-scope's lack of schema-level composition: multiple consumers cannot independently extend the set of node types and attributes with composition guarantees. gen-schema's kind extension mechanism addresses this partially, but the formal grammar composition theory from JastAdd's subsequent work (Ekman & Hedin 2007, JastAdd II) has not been exploited.

- **Dynamic aspect modularization via joinpoints (S6).** JastAdd uses only static aspects (inter-type declarations). The paper notes interest in dynamic aspects from AspectJ's joinpoint model -- inserting code at dynamically selected execution points. gen-derive's rule dispatch is conceptually similar (rules fire at dynamically determined positions in the scope graph), but a formal joinpoint model could enable more precise control over when and where aspects contribute their content.

### Potential New Libraries or Features

- **gen-scope: Formal attribute classification layer.**
  A declarative layer where attributes are explicitly classified as `synthesized`, `inherited`, or `reference`, following JastAdd's S4 formalism. `synthesized` attributes would be constrained to access only the current node and children; `inherited` attributes would be constrained to parent-provided values; `reference` attributes would be validated to point to existing nodes. This layer sits atop gen-scope's existing `attributes` parameter as a validation/documentation wrapper. Scope: small. Would consume gen-scope, produce enhanced error messages and enable static dependency analysis.

- **gen-aspects: Equation-based aspect content specification.**
  A declarative notation for aspect content inspired by JastAdd's Jrag equation syntax. Instead of opaque functions (`nixos.services.foo.enable = true`), aspects would declare equations with explicit data flow annotations. This would enable gen-scope to analyze aspect contributions statically -- detecting conflicts between aspects that define the same attribute on the same class without merge strategies. Scope: medium. Interacts with gen-aspects' classification and gen-scope's attribute system.

- **gen-scope: ParentOf-style inherited attribute contracts.**
  Extend `inherit'` with a contract mechanism (leveraging gen-bind's contract system) that declares what the parent chain MUST provide. When a node is synthesized by `children`, the contract checks that the parent node (or its ancestors) can satisfy the inherited attribute. Surfaces errors at node-synthesis time rather than attribute-access time. Scope: small. Bridges gen-scope and gen-bind.

### Research Directions

- **Formal relationship between JastAdd class weaving and NixOS module merge.** JastAdd weaves aspect contributions into classes at generation time; NixOS merges module contributions into options at evaluation time. Both are modular composition mechanisms with conflict potential (two aspects defining the same method vs. two modules setting the same option). A formal comparison could characterize when NixOS module merge provides the same guarantees as JastAdd's weaving, and where it diverges (NixOS has `mkForce`/`mkDefault` priority; JastAdd has no conflict resolution -- last-definition-wins is an error).

- **Incremental aspect weaving for configuration drift detection.** JastAdd's class weaving is a batch operation. In a fleet management scenario, changes to one aspect should only recompute affected scope graph regions. Combining JastAdd's modular aspect tracking (which classes each module touches) with gen-scope's demand-driven evaluation could yield an incremental recomputation strategy: when an aspect module changes, only nodes whose `_eval` cache includes contributions from that module need invalidation.

- **Aspect interaction analysis via dependency graph extraction.** JastAdd's translation (S5) produces a concrete dependency graph between attributes. Extracting an analogous graph from gen-scope attribute functions -- which attributes does each attribute access, and on which nodes -- could enable automatic detection of aspect interactions: two aspects that both contribute to the same class and access overlapping attributes are potential conflicts. This extends the OAG orderedness check (Theorem 4.1 via the Vogt 1989 reduction) to the scope graph setting.
