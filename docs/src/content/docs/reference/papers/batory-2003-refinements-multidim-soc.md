---
title: Batory, Liu & Sarvela (2003) — Refinements and Multi-Dimensional Separation of Concerns
description: Our reading of Refinements and multi-dimensional separation of concerns.
source:
  - den-ag-design:reference-catalog/summaries/batory-2003-refinements-multidim-soc.md
---

> D. Batory, J. Liu, and J. N. Sarvela, "Refinements and multi-dimensional separation of concerns," *ESEC/FSE03: Joint 9th European Software Engineering Conference 2003*, pp. 48–57, 2003. doi: [10.1145/940071.940079](https://doi.org/10.1145/940071.940079).

## Paper Summary

This artifact — formerly misfiled under Tarr's 1999 paper; corrected 2026-08-20 — is Batory, Liu, and Sarvela (2003) "Refinements and Multi-Dimensional Separation of Concerns" (ACM SIGSOFT/ESEC-FSE 2003), which builds directly on and reinterprets Tarr et al.'s (1999) original Multi-Dimensional Separation of Concerns (MDSOC) through the lens of Feature-Oriented Programming (FOP) and the AHEAD (Algebraic Hierarchical Equations for Application Design) formalism. The Tarr 1999 contribution — multi-dimensional separation of concerns ("hyperspace" is Ossher & Tarr's later term; the word does not appear in the 1999 paper) — is the conceptual foundation that Batory 2003 operationalizes with algebraic machinery. This summary covers both.

Tarr et al. (1999) observe that traditional software decomposition privileges one dimension of modularity (typically classes or procedures) and treats all others as cross-cutting. This is the tyranny of the dominant decomposition. MDSOC proposes that modularity should be understood as a multi-dimensional space of primitive software artifacts called units, where each dimension represents a different modularization (by class, by feature, by aspect, by function). That no dimension is privileged is *Batory 2003's reading* ("no preference is given to a dimension", its l.103-104); Tarr 1999 itself *retains* the dominant decomposition and supplements it — "hyperslices are intended to encapsulate concerns in dimensions other than the dominant one" (§3.2). A program can be decomposed along any dimension, and each decomposition cross-cuts every other. The hyperspace approach — Ossher and Tarr's implementation of MDSOC — provides composition rules that specify how units from different dimensions are integrated.

Batory 2003 connects this to step-wise refinement (SWR). In AHEAD, programs are algebraic constants and features are functions that transform programs: `app = i(j(f))` synthesizes a program with features i, j, and f by functional composition. An AHEAD model is a set of constants and functions; the set of legal compositions defines a product-line. Each function (refinement) encapsulates a cross-cut — fragments of multiple classes that collectively implement one feature. Composition merges these fragments into their target classes.

The paper's central contribution is the Origami matrix — a multi-dimensional abstraction of a one-dimensional AHEAD model. In a 2D case, rows represent one feature dimension (e.g., data structure variants: singly-linked, doubly-linked) and columns represent another (e.g., operations: insert, delete). Matrix entries are refinements. A program is synthesized by folding the matrix: composing entries along each dimension via dimensional equations. The linked list micro-example (Section 3.1) demonstrates that the four refinements {sgl, dbl, sgldel, dbldel} in the 1D model L abstract into a 2x2 matrix where rows are structure variants and columns are operations. The constraint that structural upgrades must consistently update all operations — the lock-step requirement — is enforced by the matrix structure: folding first composes columns (yielding a base program plus a consistent refinement per row), then composes rows. Invalid compositions like `dbl . sgldel . sgl` (doubly-linked insert with singly-linked delete) cannot be derived by folding.

The scalability theorem (Section 3.1.2) establishes the key quantitative result: given an n-dimensional matrix with k units per dimension, a program specified in the 1D model requires O(k^n) terms, while the same program specified via n dimensional equations requires only O(kn) terms. Multi-dimensional models provide exponentially more compact specifications.

Section 4 reinterprets Origami within AHEAD using the Principle of Uniformity — the assertion that all artifacts (code and non-code: UML, makefiles, performance models) can be given a class structure and refined. File types become classes with tool methods; refinements extend both the type's structure and its tools. An Origami matrix maps to a standard AHEAD model where each row is a unit (constant or function), and a special `toolset` unit encodes the column-folding equations. Additional dimensions (Section 4.4) map to additional feature sets refined in lock-step — extra dimensionality requires no new AHEAD machinery.

Section 4.5 provides the definitive interpretation: MDSOC is a design abstraction process. A low-level 1D model M can express huge numbers of equations, many nonsensical. An n-dimensional model D is a higher-level view where all interesting equations derivable from M are derivable from D, but D has far fewer units, each easier to explain, compose, and constrain. D generates equations for M; it is not a replacement but an abstraction.

The macro examples — the Bali matrix (2D, 4x4, programs of ~14K LOC, Section 3.2) and the Jak matrix (3D, 8x6x8, programs of ~30K LOC, Section 3.3) — demonstrate that the same ideas scale across three orders of magnitude in program size, from 30-line list implementations to 30K-line compiler tools.

## Key Concepts

- **Tyranny of the dominant decomposition** — Traditional software privileges one modularization dimension (classes, procedures). All other concerns cross-cut it. Batory 2003 reads MDSOC as eliminating this privilege by treating all dimensions equally; Tarr 1999's own construct keeps the dominant dimension and adds hyperslices for the others (§3.2 — equality language measures 0 in that paper, `dominant` fires 19 times).

- **N-dimensional concern space** — Software artifacts are points in an N-dimensional space. Each dimension is a modularization: classes, features, aspects, operations, structure variants. No dimension is inherently primary.

- **Origami matrix** — Multi-dimensional matrix where entries are refinements, dimensions are orthogonal feature sets. Folding the matrix composes entries along each dimension to synthesize a target program. Named "origami" because the matrix is folded into progressively lower dimensionality until a single expression remains.

- **Dimensional equations** — One equation per dimension specifying how to fold (collapse) that dimension. Each equation is a "projection" of the target program; their intersection uniquely identifies the program to be synthesized.

- **Lock-step refinement** — When features along one dimension (e.g., structural variant) affect multiple features along another dimension (e.g., operations), they must be applied atomically. The matrix structure enforces this — you cannot fold a row without composing corresponding entries in all selected columns.

- **Scalability theorem** — O(kn) dimensional specifications vs O(k^n) flat specifications. The exponential compression makes large product-lines tractable.

- **Principle of Uniformity** — All artifacts can be given class structure and refined. Code, UML, makefiles, performance models — the same algebraic formalism applies uniformly. File types are classes; tools are methods; refinements extend both.

- **MDSOC as abstraction of AHEAD** — An n-dimensional model D is not a separate formalism but a higher-level view of a 1D model M. D generates equations for M with fewer, more comprehensible units. The space of correct D-derivable equations is a subset of M-derivable equations containing all interesting ones.

- **Cross-cuts as refinement packages** — A feature refinement encapsulates fragments of multiple classes that collectively implement one cross-cutting concern. Composition merges fragments into their targets. This is the FOP realization of aspect-oriented cross-cutting.

- **Subjectivity** — An object does not have a single interface; the interface given to it is specific to the task at hand (Harrison and Ossher 1993). In Origami, refinement F means different things to different tools — there is no single definition of F, only per-tool interpretations.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-aspects (aspect type system)

gen-aspects realizes the MDSOC model at the type level. The connection is conceptual but structurally precise:

- **Classes as dimensions** — gen-aspects' registered classes (`nixos`, `darwin`, `homeManager`) are dimensions in Tarr's N-dimensional concern space. An aspect's content is classified into these dimensions via key classification (class key, collection key, nested key). This trifecta mirrors the Origami matrix structure: classes are one dimension, and aspects cut across all of them. The `cnf.classes` configuration parameter (passed to `aspectsType`) registers the dimensions, making the set of output targets extensible — new classes are new dimensions added to the matrix.

- **Aspects as cross-cuts** — Each aspect in gen-aspects encapsulates fragments targeting multiple classes and multiple entity contexts simultaneously. The `networking` aspect might contribute `nixos.networking.hostName` and `homeManager.programs.ssh.enable` — fragments of two different class outputs bound together as one composable unit. This is Batory's AHEAD refinement encapsulating a cross-cut (Section 2): one feature, implemented by fragments scattered across multiple classes, composed atomically.

- **Lock-step via aspect atomicity** — gen-aspects enforces that an aspect's contributions to different classes are composed as a unit. You include an aspect or you don't; you cannot include only its `nixos` fragment while excluding its `homeManager` fragment. This is the lock-step constraint from Origami matrices (Section 3.1.1) — folding a dimension composes corresponding entries in all rows.

- **Key classification as dimensional folding** — When gen-aspects processes an aspect, key classification partitions content into class keys (dimension-specific output), collection keys (data aggregation), and nested keys (sub-aspects that recurse). This partitioning is the structural equivalent of recognizing which matrix dimension each entry belongs to before folding.

- **`deferredModule` as dimension boundary** — Class content in gen-aspects is wrapped as `deferredModule` — a lazy constructor inspectable before forcing (Lorenzen 2025). This boundary marks where content transitions from the multi-dimensional aspect space into a single dimension's evaluation context (NixOS evalModules, darwin evalModules, etc.). In MDSOC terms, the `deferredModule` boundary is where the folded matrix entry exits the concern space and enters its target evaluation domain.

#### gen-algebra (conceptual substrate)

gen-algebra's record composition primitives provide the algebraic machinery that makes MDSOC's folding operations concrete in Nix:

- **`record.combine`** — The base combination operator used when folding entries within a dimension. Left-biased merge mirrors Batory's composition operator (the bullet in Section 2).

- **`record.compose`** — Mixin composition (Bracha 1990) provides the associative composition operator needed for dimensional equations. When folding a dimension's units, the order within each composition step follows `record.compose`'s associativity guarantees.

### Relevance to Den v2 HOAG Pipeline

Den v2's architecture is fundamentally an operationalization of N-dimensional separation of concerns over a demand-driven scope graph.

**Three orthogonal dimensions.** Den's concern space has (at minimum) three dimensions: classes (nixos/darwin/homeManager — the output target), entities (host/user/home — the structural identity), and aspects (networking/desktop/shell — the functional concern). Each dimension cross-cuts the others: the `networking` aspect applies to hosts and users, targeting both nixos and homeManager classes. A specific configuration point (e.g., "set the hostname on igloo") lives at the intersection of all three dimensions — it is a point in the 3D concern space.

**Scope graph as N-dimensional substrate.** The HOAG scope graph provides the structural backbone for MDSOC. Each scope node carries declarations from all dimensions simultaneously. When gen-scope's resolution follows P (parent/lexical) and I (import) edges, it is traversing the N-dimensional space. The specificity ordering D < I < P (from Neron 2015) provides the folding discipline — declarations shadow imports shadow inherited values, giving each dimension's contributions a principled priority.

**Entity-class orthogonality.** In den v2, entities spawn scope nodes (`spawn "host" { ... }`, `spawn "user" { ... }`), and aspects contribute class content at those scopes. The entity dimension and the class dimension are orthogonal — the same aspect can contribute `nixos` modules at the host level and `homeManager` modules at the user level. This is precisely Tarr's insight that no dimension should be privileged. Traditional NixOS configuration privileges the class dimension (you write NixOS modules directly); den v2 de-privileges it by placing classes as one dimension among equals, all accessed through the same aspect mechanism.

**Dimensional equations as scope operations.** Den v2's domain vocabulary maps to dimensional equations:

- `spawn "kind" { ... }` — Select a point along the entity dimension (create a host scope, user scope).
- `edge aspect` — Include an aspect's contributions (select along the aspect dimension).
- `drop aspect` — Exclude an aspect (restrict the aspect dimension).
- `reroute { from, to }` — Redirect content between classes (transform the class dimension).
- The final output assembly — collecting all class modules per entity and passing them to `evalModules` — is the complete folding of the matrix into a 1x1 result.

**Collections as inter-dimensional data flow.** Den's collections (declared via `den.collections`) carry data between dimensions. A collection aggregation gathers contributions from aspects (the aspect dimension) scoped to entities (the entity dimension) and delivers the merged result to other aspects. This is data flow across the concern matrix — not folding, but lateral communication between matrix entries. The paper does not address inter-entry communication (entries in an Origami matrix are composed, not queried), making den's collections an extension beyond the paper's model.

**Policies as dimensional constraints.** Den v2's policies (gen-derive rules) fire based on context and produce effects. In MDSOC terms, policies are design rules (Section 2, reference [5]) — constraints on legal compositions. Batory 2003 explicitly defers design rules to separate work; den v2 implements them via gen-derive's stratified dispatch with conflict resolution, realizing the constraint mechanism the paper only mentions.

## Appendix: Follow-up Work

### Unexploited Ideas

**Explicit dimensional equation syntax (Section 3.1.2).** The paper's notation — separate equations per dimension, each specifying a folding strategy — has no direct counterpart in den's user API. Users declare entities and aspects, and the pipeline implicitly folds the concern space. An explicit dimensional equation syntax would let users specify folding order and strategy per dimension, potentially enabling optimizations (fold the entity dimension first for fleet-scale builds, fold the class dimension first for single-host debugging). The paper's observation that different folding orders yield the same result (when refinements are independent) could be verified as an invariant.

**Subjectivity as per-consumer aspect interpretation (Section 5).** The paper inherits Harrison and Ossher's (1993) observation that an object's interface is subjective — specific to the task. In den, aspects currently have a single definition regardless of who consumes them. Subjectivity would mean the `networking` aspect presents different content depending on the consuming entity's kind: a host sees firewall rules; a microVM sees network namespace configuration; a container sees none. This is partially addressed by guard functions (`{ host, ... }: { ... }`) and meta.guard, but the mechanism is coarse — guards are boolean (include or exclude), not interface-reshaping.

**Origami matrix visualization (Section 3.1.1, Tables 1-5).** The paper's matrix notation — with row/column labels, entries showing refinement names, and folded versions showing composed expressions — is a powerful communication tool. Den v2's diagram generation (nix/lib/diag/) produces C4, Mermaid, and DOT outputs but does not produce Origami-style matrix views. A matrix visualization showing entity kinds as one axis, classes as another, and aspect contributions as cells would directly realize the paper's notation for den configurations.

**Tool suite synthesis via file type models (Section 4.1-4.3).** The Principle of Uniformity and the file type / method / tool model (Section 4.2) describe synthesizing families of tools from shared designs. Den's template system (`templates/`) provides example configurations but does not synthesize tool variants from shared infrastructure. The paper's model — where file types are classes, tools are methods, and refinements extend both — could apply to den's CI/CD tooling, documentation generators, and diagram tools.

**Higher-dimensional matrices (Section 4.4).** The paper describes a 3D (8x6x8) Jak matrix with Frontal and Horizontal sub-matrices for feature-feature interactions. Den currently models three dimensions implicitly (entity, class, aspect), but feature-feature interactions (e.g., the `desktop` aspect's behavior changes when `wayland` is also included) are handled ad-hoc via guards and includes. The paper's explicit encoding of interactions as a separate matrix dimension — with lock-step folding against the primary dimensions — offers a more principled approach.

### Potential New Libraries or Features

**gen-aspects: origami matrix introspection** — Expose the implicit N-dimensional structure of a configured aspect set as an explicit matrix. Given `cnf.classes` (one dimension) and a set of entity kinds (another dimension), produce a matrix whose entries are the aspect fragments contributing to each (entity-kind, class) cell. Scope: moderate, requires traversing classified aspect content and grouping by dimension. Interactions: gen-scope provides the graph structure; gen-graph's `materialize` could build the cell index. Output: attrset `{ rows = [...]; cols = [...]; cells = { "host/nixos" = [ aspect-fragments ]; }; }`. Useful for diagnostics, visualization, and validating lock-step completeness.

**gen-aspects: dimensional folding order control** — An API allowing consumers to specify which dimension to fold first. For a 3D concern space (entity x class x aspect), folding entity first produces per-host aspect bundles; folding class first produces per-class module sets across all hosts; folding aspect first produces per-aspect cross-entity summaries. Scope: small addition to `cnf` configuration. The paper proves folding order does not affect the result when refinements are independent (Section 3.1.1, equations 4 and 5); gen-aspects could verify this invariant in tests.

**gen-scope: matrix-aware attribute definitions** — Extend gen-scope's attribute definition mechanism to be aware of dimensional structure. Currently attributes are functions `self id -> value`; a matrix-aware variant would be `self id dimension -> value`, allowing per-dimension attribute computation with cross-dimension queries. Scope: significant — requires gen-scope API changes. Interactions: gen-select's `adapters.scope.mkContext` would need dimension-aware context construction.

**den: subjective aspect interfaces** — Implement Harrison and Ossher's subjectivity: an aspect presents different content depending on the consuming scope's properties. Beyond boolean guards, this would allow per-consumer interface reshaping — the `networking` aspect exposes different options to a bare-metal host vs. a microVM vs. a container. Scope: medium-large. Implementation: extend gen-aspects' guard mechanism from `pred -> bool` to `pred -> interface-transform`, where the transform reshapes the aspect's visible content. Interactions: gen-derive's rule dispatch could select transforms; gen-select's selectors could specify consumer properties.

### Research Directions

**Verifying dimensional independence.** The paper's key optimization — O(kn) vs O(k^n) — depends on refinements along different dimensions being independent. In den's concern space, this independence is assumed but not verified. Aspects can contain guards that depend on entity context, breaking dimensional independence. A static analysis (via gen-derive's condition inspection or gen-select's selector analysis) could identify aspects whose contributions violate dimensional independence, flagging potential composition-order sensitivity.

**Category-theoretic folding.** The paper's folding operation is algebraically characterized but not given a category-theoretic treatment. Formalizing origami folding as a functor from the product category of dimension categories to the output category could connect MDSOC to the pushout-based rewriting in Ehrig 2006 (already used by gen-derive). This might yield a unified framework where aspect composition (MDSOC folding), graph rewriting (Ehrig pushouts), and scope-graph resolution (Neron path-finding) are all instances of the same categorical construction.

**Incremental re-folding.** When one aspect changes, den v2 currently re-evaluates the entire scope graph (modulo Nix's lazy evaluation memoization). The paper's dimensional structure suggests incremental re-folding: if a change only affects one dimension (e.g., a new operation column), only that dimension's folding needs to be recomputed. Formalizing which scope-graph attributes depend on which dimensions could enable demand-driven incremental re-evaluation — connecting to Mokhov 2018's build-system traces and gen-scope's `_eval` memoization.

**MDSOC for fleet configuration.** The paper's examples are single programs. Den manages fleets — many programs (hosts) with shared structure. The fleet dimension (which hosts get which configurations) is not well-modeled by Origami matrices. Extending the matrix model to include a fleet dimension — where entries are host-specific overrides and folding produces per-host configurations — could formalize den's host/user/home entity model as a dimensional decomposition rather than a tree structure.
