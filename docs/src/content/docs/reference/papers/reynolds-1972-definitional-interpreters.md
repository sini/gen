---
title: Reynolds (1972) -- Definitional Interpreters for Higher-Order Programming Languages
description: Our reading of Definitional interpreters for higher-order programming languages.
source:
  - den-ag-design:used/summaries/reynolds-1972-definitional-interpreters.md
---

> J. Reynolds, "Definitional interpreters for higher-order programming languages," *the ACM annual conference*, vol. 2, pp. 717–740, 1972. doi: [10.1145/800194.805852](https://doi.org/10.1145/800194.805852) · [summary](/reference/papers/reynolds-1972-definitional-interpreters/).

Reynolds, John C. "Definitional Interpreters for Higher-Order Programming Languages." In Proceedings of the ACM Annual Conference, Vol. 2, 717-740. Boston, 1972. Reprinted with retrospective in Higher-Order and Symbolic Computation 11, 363-397 (1998). https://doi.org/10.1023/A:1010027404223

## Paper Summary

The problem Reynolds addresses is deceptively fundamental: when we define a programming language L by writing an interpreter in a metalanguage M, the interpreter implicitly inherits properties of M. If M is a higher-order language (one where functions are values), an interpreter for L written in M can use M's closures to implement L's closures, M's calling convention to implement L's calling convention, and M's variable binding to implement L's variable binding. This inheritance is convenient but dangerous -- it means the definition of L is entangled with implementation choices of M, and the interpreter does not actually specify how L's higher-order features work.

Reynolds identifies two orthogonal dimensions along which definitional interpreters vary: (1) whether the interpreter itself uses higher-order functions, and (2) whether the evaluation order (call-by-value vs. call-by-name) of the defined language L depends on the evaluation order of the defining language M. These two dimensions produce four classes of interpreters. Reynolds shows constructive transformations between all four classes, establishing that one can always move from a "parasitic" interpreter (which inherits M's properties) to a "self-contained" one (which explicitly specifies L's behavior).

The central technical contribution is **defunctionalization**: a systematic transformation that eliminates higher-order functions from a program by replacing them with first-order tagged data and an explicit dispatch function (called `apply`). Each lambda abstraction in the source program is replaced by a data constructor carrying the free variables of that lambda (its closure environment). All function application sites are replaced by calls to a single `apply` function that dispatches on the tag to execute the appropriate body. The transformation is global -- every closure-creating site produces a distinct tag, and the `apply` function has a branch for each tag.

Reynolds demonstrates this on a simple applicative language with `lambda`, `apply`, `let`, `letrec`, conditionals, and primitive operations. Starting from a direct (higher-order, order-dependent) interpreter, he derives:

1. A **higher-order, order-independent** interpreter by introducing explicit continuations (continuation-passing style, CPS), which disentangles L's evaluation order from M's.
2. A **first-order, order-dependent** interpreter by defunctionalizing the direct interpreter -- replacing environment closures with data records and the value domain with a tagged union of constants and closures.
3. A **first-order, order-independent** interpreter by applying both transformations: first CPS to expose control flow, then defunctionalization to eliminate all remaining higher-order functions (both closures and continuations become first-order data).

The first-order, order-independent interpreter is the paper's culminating artifact: it specifies L completely without inheriting any semantic property from M. It is essentially an abstract machine -- Reynolds notes its similarity to Landin's SECD machine, which was originally derived by different (less systematic) means.

The paper also discusses extensions for imperative features: assignment requires threading a store through the interpreter, and jumps (goto/labels) require first-class continuations in M or, after defunctionalization, explicit continuation data structures. The `J` operator (Landin's jump operator for non-local returns) receives particular attention as a test case for the CPS + defunctionalization methodology.

Reynolds' defunctionalization and CPS transformation became foundational techniques in programming language theory and compiler construction. Defunctionalization was later formalized by Danvy and Nielsen (2001) and connected to the broader theory of program transformations. The CPS transformation Reynolds introduces (building on work by Fischer, Plotkin, and others) became central to denotational semantics and compiler intermediate representations.

## Key Concepts

- **Definitional interpreter (S1-2)** -- An interpreter for language L written in metalanguage M. Serves as L's formal definition. The interpreter's structure implicitly determines whether L's semantics depends on M's evaluation order and higher-order features.

- **Higher-order vs. first-order interpreters (S2-3)** -- A higher-order interpreter uses M's functions to represent L's functions (closures are implicit in M). A first-order interpreter represents L's functions as data (closures are explicit records). The distinction determines whether L's closure semantics is defined or inherited.

- **Order-dependent vs. order-independent interpreters (S3-4)** -- An order-dependent interpreter inherits M's evaluation strategy (CBV or CBN) for L. An order-independent interpreter explicitly specifies L's evaluation order, typically via continuations or explicit sequencing.

- **Defunctionalization (S3)** -- The transformation from higher-order to first-order: replace each lambda abstraction with a data constructor carrying free variables, replace all application sites with calls to a dispatch function (`apply`) that branches on the constructor tag. The number of tags equals the number of syntactically distinct lambda forms in the program.

- **Closure as data (S3)** -- After defunctionalization, a closure is a record: `{ tag, env }` where `tag` identifies which lambda body to execute and `env` carries the captured free variables. This makes closure structure inspectable and comparable -- properties that higher-order closures in M lack.

- **Continuation-passing style (S4)** -- Transform the interpreter so every function takes an explicit continuation argument representing "what to do with the result." This disentangles L's control flow from M's call stack. After CPS, the interpreter specifies L's evaluation order regardless of M's.

- **Defunctionalized continuations (S5)** -- Continuations, being functions, can themselves be defunctionalized. Each continuation-creation site becomes a data constructor; the continuation dispatch function branches on tags. The result is a first-order abstract machine with an explicit continuation stack.

- **Environment representation (S3)** -- In the first-order interpreter, environments become explicit data structures (association lists or records mapping variable names to values) rather than being implicit in M's lexical scoping.

- **The four interpreter classes (S2-5)** -- The 2x2 matrix of {higher-order, first-order} x {order-dependent, order-independent}. Reynolds shows constructive transformations between all four quadrants, establishing their equivalence as language definitions.

- **Store threading for assignment (S6)** -- Imperative features require passing an explicit store parameter through the interpreter. After defunctionalization, the store becomes a first-class data structure (array or map) threaded through the abstract machine.

- **J-operator and non-local control (S7)** -- Landin's J-operator for non-local returns serves as a test case. In the CPS interpreter, J-continuations are just values. After defunctionalization, they become tagged data in the continuation stack -- demonstrating that the methodology handles non-trivial control operators.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-aspects (MAJOR) -- Guard function defunctionalization

Guard functions in gen-aspects are the direct realization of Reynolds' defunctionalization applied to Nix closures. A guard function like `{ host, ... }: { nixos = ...; }` is a Nix closure: it captures free variables, takes arguments, and is opaque to inspection. The gen-aspects pipeline needs to inspect guard functions without calling them -- it must determine what arguments they require, classify them as guard-vs-module functions, and dispatch them later when scope context provides the arguments.

The `functionTo` wrapper performs Reynolds' transformation on each guard function:

- **Tag**: `__isWrappedFn = true` marks the value as a defunctionalized closure (analogous to the constructor tag in Reynolds' `apply` dispatch).
- **Environment capture**: `__functionArgs` records the function's formal parameters via `builtins.functionArgs`, making the closure's interface inspectable without calling it. This is the explicit environment record from Reynolds S3 -- the closure's free variable structure is promoted from implicit (inside Nix's runtime) to explicit (as an attrset).
- **Dispatch**: `__functor` provides the explicit `apply` function -- when the pipeline later calls the defunctionalized guard with scope-computed arguments, `__functor` dispatches to the original function body.

The `canTake` utility (`canTake.upTo params fn`) performs the classification that Reynolds' `apply` function performs at dispatch time: it inspects the defunctionalized closure's argument signature to determine whether the available scope context satisfies all required parameters. This is inspection of first-order data rather than trial application of an opaque function -- precisely the capability that defunctionalization grants.

The `aspectType` trait dispatches on value shape in merge: attrsets and module functions merge directly into the submodule; guard functions are detected via `canTake` and routed through `functionTo` wrapping. This merge-time dispatch is Reynolds' `apply` function operating at the type level -- one dispatch site, multiple tags (attrset, module-fn, guard-fn), each routed to its handler.

**Key files**: `gen-aspects/nix/lib/types.nix` (aspectType, functionTo wrapping), `gen-aspects/nix/lib/canTake.nix` (argument introspection).

#### gen-bind (Minor) -- Partial application as closure manipulation

gen-bind's `wrap` function performs partial application: given a module function `{ host, config, lib, ... }: { ... }` and bindings `{ host = ...; }`, it produces a new function `{ config, lib, ... }: { ... }` with `host` pre-bound. This is closure manipulation in Reynolds' framework -- constructing a new closure whose environment includes the bound values.

`builtins.functionArgs` serves as Nix's analogue to Reynolds' formal parameter reflection. In a definitional interpreter, the interpreter knows the parameter names of each lambda form because it processes the abstract syntax tree. In Nix, `builtins.functionArgs` exposes the same information at runtime, enabling gen-bind to inspect a function's interface without calling it. This is a limited but native form of the inspectability that defunctionalization provides by construction.

The `signature` record (`{ requires, bound, unsatisfied, mergeStrategies }`) is the first-order representation of a module's binding state -- analogous to the environment record in a defunctionalized closure, but tracking which variables are bound vs. still free.

**Key files**: `gen-bind/nix/lib/wrap.nix` (core wrapping via `builtins.functionArgs` introspection), `gen-bind/nix/lib/signature.nix` (module signature inference).

### Relevance to Den v2 HOAG Pipeline

Defunctionalization is pervasive in den v2's demand-driven HOAG architecture, operating at three levels:

**Parametric aspects as defunctionalized closures**: Parametric aspects carry `__fn` (the original function body) and `__args` (the required scope-context parameters) as inspectable first-order data. The HOAG evaluator can examine `__args` to determine what scope context an aspect needs without evaluating the aspect body -- a direct application of Reynolds' insight that first-order representations enable pre-dispatch inspection. When the scope node provides sufficient context (all `__args` satisfied), the evaluator calls `__fn` with the computed values, completing the deferred application. This is Reynolds' `apply` function operating at the HOAG attribute level.

**Guard functions and scope-graph resolution**: Guard functions (`meta.guard`) are defunctionalized so the scope graph can inspect their argument signatures during resolution. The resolution calculus (Neron 2015 D < I < P specificity) needs to determine whether a guarded aspect is applicable in a given scope context without forcing evaluation of the aspect body. Defunctionalization makes the guard's requirements visible as data (`__functionArgs`), enabling the resolver to prune inapplicable guards during path-finding rather than after. This is the core practical payoff of Reynolds' transformation in den: it moves guard evaluation from runtime trial-and-error to compile-time structural matching.

**Policy dispatch via gen-derive**: Den v2 policies are rules dispatched via gen-derive's fixpoint loop. Each policy is a function `{ host, ... }: effects` whose argument signature determines when it fires. `gen-derive.fromFunction` defunctionalizes these policy functions: `builtins.functionArgs` extracts the condition (which entity-context keys must be present), and the function body becomes the action. The `apply` dispatch is gen-derive's `match` + `fire` sequence. Combined with Palmer's intensional identity (which Reynolds' defunctionalization makes possible -- tagged data supports equality where closures do not), identified policies fire at most once per scope, guaranteeing fixpoint convergence.

**Partial application bridging scope and modules**: gen-bind performs partial application to bridge scope-computed values into NixOS module functions. In the HOAG pipeline, attribute computation produces values (entity bindings, enrichment data, pipe outputs) that must flow into module functions written by users. gen-bind's `wrap` partially applies these scope-computed bindings, producing modules whose remaining arguments (`config`, `lib`, `pkgs`) come from `evalModules`. This is Reynolds' environment manipulation -- constructing a new closure with a richer environment -- applied at the interface between the scope graph and the NixOS module system.

## Appendix: Follow-up Work

### Unexploited Ideas

**Systematic CPS for pipeline control flow (S4-5)**: Reynolds' CPS transformation makes control flow explicit and first-order. The den v2 pipeline currently uses Nix's native call stack for attribute evaluation ordering. Applying CPS transformation to attribute computations would make the evaluation schedule inspectable and controllable -- enabling explicit scheduling policies (breadth-first vs. depth-first attribute evaluation), better error reporting (the continuation stack is data, not an opaque call stack), and potentially incremental re-evaluation (continuations can be checkpointed).

**Defunctionalized continuations as reified evaluation traces (S5)**: After both CPS and defunctionalization, the continuation stack is a list of tagged data records. In den v2, this would mean every pending attribute computation is represented as an inspectable record: what attribute, on which node, waiting for what. This reified evaluation trace could power debugging tools (show the user exactly why a particular attribute is being computed), cycle detection (inspect the continuation stack for duplicate entries), and profiling (count and categorize pending computations).

**Store-passing for mutable-like semantics (S6)**: Reynolds' store-threading technique for imperative features has not been exploited in the gen ecosystem. A store-passing interpretation could enable gen-scope attributes that accumulate side-channel state (counters, logs, warnings) threaded through the evaluation in a controlled manner, rather than relying on Nix's `builtins.trace` or throwing errors.

**Defunctionalization of collection fold functions**: Collection attributes in gen-scope use traversal functions (fold/map over children, imports, ancestors). These fold functions are currently opaque Nix closures. Defunctionalizing them into tagged traversal descriptors (e.g., `{ __traversal = "children"; __combine = "append"; }`) would make collection attribute semantics inspectable -- enabling optimization (skip traversal when no contributors exist), composition (merge two collection traversals without creating a new closure), and serialization (collection semantics as data for diagram generation).

**The four-quadrant framework applied to NixOS module evaluation (S2-5)**: NixOS `evalModules` is a higher-order, order-dependent evaluator -- it uses Nix closures for module functions and inherits Nix's lazy evaluation order. Reynolds' framework suggests three alternative evaluator designs: first-order (modules as data records), order-independent (explicit module evaluation scheduling), or both. A first-order, order-independent `evalModules` would make module evaluation fully inspectable and controllable -- relevant for debugging, optimization, and incremental evaluation of large NixOS configurations.

### Potential New Libraries or Features

**gen-aspects: defunctionalized traversal descriptors** -- Replace opaque traversal functions in collection attributes with tagged first-order descriptors. Scope: medium. The descriptor vocabulary is small (children, imports, ancestors, siblings, label:X, custom). Benefits: inspectable collection semantics for diagram generation, mergeable traversals for pipe composition, skippable traversals when no contributors exist. Interactions: gen-scope collection attributes would dispatch on descriptor tags rather than calling opaque functions.

**gen-algebra: reified continuation stacks** -- Extend the search monad with an inspectable continuation stack where each pending continuation is a tagged record (program point + closure data) rather than an opaque Nix thunk. Scope: medium. Enables: debugging of convergence behavior (show which continuations are pending and why), tighter convergence bounds (count distinct tagged continuations statically), and potential checkpointing of search state. Interactions: gen-derive fixpoint could expose its pending-rule state for diagnostic purposes.

**gen-bind: defunctionalized module shapes** -- Extend gen-bind to represent all three module shapes (function, imports-attrset, plain-attrset) as tagged first-order data before wrapping, rather than detecting shape at wrap time. Scope: small. The shape detection in `wrap.nix` already performs implicit defunctionalization (branching on shape); making it explicit would enable pre-wrap analysis (batch signature computation without wrapping), composition of unwrapped modules (merge two function-shape modules' parameter sets before constructing the wrapped closure), and better error messages (shape is data, not inferred at failure time).

### Research Directions

**Defunctionalization as a design methodology for Nix libraries**: Reynolds' transformation is typically applied to compiled programs. In the gen ecosystem, it is applied as a design pattern -- closures are manually defunctionalized into attrsets with `__functor`. Formalizing when and why Nix library designers should defunctionalize (inspectability requirements, comparison requirements, serialization requirements) could yield design guidelines for the broader Nix ecosystem, where opaque closures are a frequent source of debugging difficulty.

**Relationship between defunctionalization and Nix's `builtins.functionArgs`**: Nix provides limited native function inspection via `builtins.functionArgs` (formal parameter names and default-presence flags). This is a subset of what full defunctionalization provides (parameter names but not closure contents, not the function body). Characterizing exactly what `builtins.functionArgs` enables versus what full defunctionalization enables would clarify the theoretical position of gen-bind (which relies on native inspection) versus gen-aspects (which performs manual defunctionalization for fuller inspectability).

**Defunctionalization and the expression problem in Nix**: Reynolds' defunctionalization is closed -- the `apply` function must enumerate all tags. Adding a new lambda form requires modifying `apply`. In gen-aspects, adding a new aspect shape would require extending the `aspectType` dispatch. The expression problem (adding both new data variants and new operations without modifying existing code) is relevant here. Investigating how Reynolds' transformation interacts with Nix's open attrset model (where new keys can always be added) could yield patterns for extensible defunctionalization -- defunctionalized dispatch that is open to new tags without modifying the dispatch function.

**Partial defunctionalization and selective opacity**: Not all functions in a program need to be defunctionalized -- only those requiring inspection or comparison. Reynolds' transformation is all-or-nothing (all closures in a given type become first-order). A theory of partial defunctionalization that identifies which functions benefit from the transformation and which should remain opaque (for performance or encapsulation) would formalize the design decisions currently made ad hoc in the gen ecosystem: guard functions are defunctionalized (need inspection), module functions are not (evaluated eagerly, no inspection needed), collection fold functions are not (currently no inspection needed, but see above).
