---
title: Findler & Felleisen (2002) — Contracts for Higher-Order Functions
description: Our reading of Contracts for higher-order functions.
source:
  - den-ag-design:used/summaries/findler-2002-contracts-higher-order.md
---

> R. B. Findler and M. Felleisen, "Contracts for higher-order functions," *ICFP02: International Conference on Functional Programming*, pp. 48–59, 2002. doi: [10.1145/581478.581484](https://doi.org/10.1145/581478.581484) · [summary](/reference/papers/findler-2002-contracts-higher-order/).

## Paper Summary

Findler and Felleisen address a fundamental gap in assertion-based programming: while Design by Contract (Meyer's Eiffel philosophy) was well-established for first-order procedural and object-oriented languages, no principled mechanism existed for enforcing contracts on higher-order functions. The difficulty is twofold: (1) predicates on function values are undecidable in general, so a contract on a function-typed argument cannot be checked at the call site; and (2) blame assignment — identifying which party violated a contract — becomes entangled when functions pass through multiple boundaries.

The paper's central insight is that contract enforcement for higher-order values must be **deferred**: rather than checking a function contract when a higher-order argument is received, the contract system wraps the function so that its domain contract is checked when the function is eventually applied, and its range contract is checked when it returns. This wrapping can cascade — each arrow in a contract type induces a distribution step at the corresponding application site during evaluation.

The formal vehicle is **lambda-CON**, a typed lambda calculus with first-class contracts. The calculus introduces obligation expressions `e^{c,p,n}` where `c` is the contract, `p` is the positive party (value producer), and `n` is the negative party (value consumer). Two reduction rules are central: the **flat** rule checks a predicate contract on a first-order value and blames the positive party on failure; the **hoc** (higher-order contract) rule distributes a function contract `(C_D -> C_R)` at an application by moving `C_D` to the argument and `C_R` to the result, while **swapping** the blame labels on the domain portion. This swap is the formal encoding of **contravariance** in blame assignment.

The paper establishes the **even-odd rule** for blame: a base predicate appearing an even number of times to the left of an arrow is in covariant (positive) position — the function itself is responsible. An odd number of nestings puts it in contravariant (negative) position — the caller is responsible. This directly parallels the variance of function types in subtyping theory.

The authors prove **type soundness** for lambda-CON (Theorem 6.2) via standard preservation and progress lemmas, and then prove **compiler correctness** (Theorem 6.7): the compiled implementation (using the `wrap` meta-function that recursively wraps values according to their contracts) produces the same observable results as the instrumented calculus semantics. The proof introduces an intermediate semantics (`wrap`-reduction) and shows `E = E_fw = E_fh` — the three evaluators (compiled, wrap-based, and hoc-based) agree on all programs.

Section 7 extends the calculus with **dependent contracts** — range contracts that are functions of the input value. The dependent contract reduction applies the range function to the actual argument before wrapping the result, enabling stateful pre/post-condition patterns (e.g., checking that a callback preserves invariants by capturing state before the call and comparing after).

Section 8 discusses the interaction with **tail recursion**: post-condition checking inherently breaks tail-call optimization for contracted functions. The authors argue this is acceptable because contracts are most valuable at module boundaries, which are rarely in tight loops — a conjecture supported by experience in the DrScheme codebase.

Throughout, the paper grounds its contributions in real examples from DrScheme's implementation: preferences panel callbacks, mixin contracts for IDE extensions, and thread-safety contracts for plugin thunks. These examples demonstrate that the contract system captures invariants that no existing type system (including OCaml's and OML's) could express statically.

## Key Concepts

- **Deferred enforcement**: Higher-order contracts cannot be checked at the call site; they must be deferred until a first-order value is produced or consumed. Each arrow in a contract type induces a wrapper that distributes checking to the appropriate application.

- **Blame labels and the even-odd rule**: Every obligation carries two labels (positive/negative). Flat contract failures blame the positive party. At each arrow distribution, labels swap on the domain side — encoding covariant (even depth) and contravariant (odd depth) blame assignment.

- **The `wrap` function**: A recursive contract compiler that case-splits on flat vs. function contracts. For flat contracts, it tests the predicate and blames the positive party on failure. For function contracts, it builds a wrapper lambda that recursively wraps both the argument (with swapped blame) and the result.

- **lambda-CON calculus**: Typed lambda calculus with obligation expressions, two contract reduction rules (flat and hoc), and a type system that ensures contracts match the types of their subjects. Type soundness proved via Wright-Felleisen method.

- **Compiler correctness (Theorem 6.7)**: The compiled form (using `wrap`) is observationally equivalent to the instrumented calculus. Proved via an intermediate `wrap`-reduction semantics that bridges the two.

- **Dependent contracts**: Range contracts parameterized by input values, enabling pre/post-condition patterns with captured state. Formally, `C_D ->d (lambda(arg) C_R)` where the range contract is computed from the actual argument.

- **First-class contracts**: Contracts are values — they can be abstracted, composed, and passed to functions. This enables reusable contract patterns (e.g., `mixin-contract/intf` in DrScheme).

- **Contravariance as blame inversion**: The fundamental connection between type-theoretic variance and runtime blame assignment. Domain position is contravariant; each nesting inverts who is responsible.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-bind (MAJOR)

gen-bind implements the core Findler concepts — blame tracking and covariant/contravariant blame assignment — in the context of NixOS module binding.

**Provenance as blame labels (S2.3, S4).** gen-bind's `provenance` records (`{ source; scope?; }`) serve the role of Findler's blame labels in obligation expressions. Every `wrap` call can attach provenance metadata to each binding. When a contract fires or a collision is detected, the error message identifies the guilty party by name and scope — directly analogous to how lambda-CON's `blame("p")` names the responsible definition. Implementation: `provenance.nix` (`provenance.format`), threaded through `wrap.nix` and surfaced in `contract.nix` and `merge-strategy.nix`.

**Covariant/contravariant blame in collision detection (S2.3).** gen-bind's merge strategy system implements a simplified version of Findler's blame variance. When a binding name collides with a module-system arg:

- `bindWins` (binding shadows system) — the binding source is in covariant (positive) position; if the value is wrong, blame the binding provider.
- `systemWins` (system shadows binding) — the module system is in positive position; the binding is dropped.
- `error` — neither party accepts the collision; throw with full blame attribution.

The `mkMergeValidator` function (`merge-strategy.nix`) constructs a validator that, given module args, checks for collisions and attributes blame to the correct party based on the merge strategy — the same even-odd logic applied to a two-party system (binding source vs. module system).

**Lazy contract wrapping (S5, cf. also Chitil 2012).** gen-bind's `contract.mk` creates assertion wrappers that fire on demand, not at wrap time. This mirrors the `wrap` function's structure (Figure 9): for a flat contract, test the predicate and blame the positive party on failure. The key difference from Findler's system is that gen-bind operates in a lazy language (Nix), so the "deferred" nature is provided by Nix's evaluation strategy rather than by explicit wrapper lambdas. Functions: `contract.mk`, `contract.hasFields`, `contract.isType`, `contract.nonEmpty`, `contract.apply` in `contract.nix`.

**Signatures as contract interfaces (S3-4, cf. also Cardelli 1997).** gen-bind's `buildSignature` produces a static record of `{ requires, bound, unsatisfied, mergeStrategies }` — a lightweight analogue of the obligation expression's contract component. The signature declares what values a module expects (its contract domain) and what was provided (bound). Unsatisfied entries are potential blame targets. Implementation: `signature.nix`.

#### gen-schema (MAJOR)

gen-schema implements Findler's predicate contracts and blame records for typed record registries.

**Refinement contracts (S1-2, S3).** `schema.types.refined` in `refined.nix` attaches predicate contracts to NixOS type declarations. A refinement `{ check = self: self > 0; message = "must be positive"; }` is directly analogous to Findler's `contract(lambda x. x >= 0)` — a flat predicate contract that guards a base type. The `check` function is the predicate; the `message` is the blame annotation. Multiple refinements compose (all must pass), paralleling conjunction of flat contracts. Refinements validate during `applyPipeline` in `instance.nix`.

**Lazy refinements (S5, cf. Chitil 2012).** Setting `lazy = true` on a refinement defers validation to access time via `builtins.addErrorContext`. This matches the `wrap` function's behavior for higher-order contracts — the check is installed as a wrapper but only fires when the value is demanded. In Findler's terms, the obligation travels with the value until a first-order observation occurs.

**Blame records (S2.3, S4).** `schema.blame` in `blame.nix` creates structured blame records `{ __blame = true; field = "fieldName"; message = "error message"; }`. These are gen-schema's version of Findler's blame labels — they carry field-level attribution so that when a contract violation occurs, the error identifies not just that something failed, but which field and what the violation was. The `field` component parallels Findler's variable names in obligation expressions (`e^{c,p,n}` where `p` identifies the responsible definition).

**Validator collection (S2.1-2.2).** Schema validators (`mkValidator`, `validateInstances`) implement a bulk-contract-checking pattern. Each validator is a named predicate with an error message — a flat contract in Findler's taxonomy. The `validateInstances` function returns `Either` rather than throwing, allowing consumers to handle violations structurally. The error accumulation (not short-circuit) is an extension beyond Findler's fail-fast semantics, suited to configuration validation where users want all errors at once.

### Relevance to Den v2 HOAG Pipeline

Den v2 builds a demand-driven Higher-Order Attribute Grammar over scope graphs. gen-bind bridges scope-computed values into NixOS module system boundaries. Findler's contract/blame framework structures this bridge:

**Binding validation at scope boundaries.** When a policy or aspect produces a value that will be injected into a NixOS module via gen-bind, the value crosses a trust boundary — from the scope graph (where the value was computed) into the module system (where it will be consumed). gen-bind contracts guard this boundary exactly as Findler's contracts guard module boundaries in lambda-CON. The provenance record carries the scope identity (`"host=igloo,user=tux"`) so that blame traces back to the producing scope node.

**Contravariant blame in policy dispatch.** Den v2 policies fire when their argument signature matches scope context. When a policy produces a faulty binding, the blame is covariant — the policy is the positive party. When a policy requires a value from the scope context and receives an invalid one, the blame is contravariant — the entity declaration that populated the scope is responsible. gen-derive's rule dispatch combined with gen-bind's provenance implements this two-directional blame.

**Deferred contracts in the HOAG.** gen-scope's demand-driven evaluation means attribute values are computed lazily. gen-bind's lazy contracts align with this — a contract on a binding value is installed when the scope graph emits the value, but the assertion only fires when the consuming NixOS module actually demands the arg. Unbuilt hosts (hosts whose NixOS configurations are never evaluated) pay zero contract cost, matching Findler's principle that contract overhead should be proportional to actual usage.

**Dependent contracts for stateful validation.** Findler's dependent contracts (Section 7) — where the range contract captures the input value — map to gen-bind's config thunks. A `mkThunk` binding defers resolution until `evalModules` provides `config`, enabling pre/post-condition patterns: the thunk can capture scope state at definition time and compare against module system state at resolution time.

## Appendix: Follow-up Work

### Unexploited Ideas

**Dependent contracts for cross-entity invariants (S7, Figure 12).** Findler's dependent contract constructor `C_D ->d (lambda(arg) C_R)` allows the range contract to be a function of the input. gen-bind's current contracts are flat — each contract checks one binding value in isolation. Dependent contracts would allow expressing invariants like "if the host binding has `role = "web"`, then the `port` binding must be in range 80-443". The dependent contract would capture the host value and produce a port-specific range contract. This would require extending `contract.mk` to accept a function from binding context to contract.

**First-class contract composition (S2.4, Figure 3).** The paper demonstrates contracts as first-class values — abstracted, parameterized, and composed. gen-bind's contract constructors (`hasFields`, `isType`, `nonEmpty`) are individual predicates with no combinator layer. A contract algebra with `and`, `or`, `not`, `implies` combinators would allow expressing complex binding contracts compositionally, mirroring Findler's `mixin-contract/intf` pattern where contract factories produce specialized contracts.

**Contract monitoring across module boundaries (S2.2, S4).** Findler's system tracks contracts through evaluation from establishment to discovery, potentially across distant call sites. gen-bind currently checks contracts at a single point (when the binding value is demanded). A monitoring mode that tracks a value's journey — from scope graph emission through gen-bind wrapping through `evalModules` consumption — would provide richer debugging for deep configuration pipelines. This would require instrumenting the value with obligation-style wrappers that survive Nix's lazy evaluation.

**Blame assignment for nested function contracts (S2.3, S4 hoc-reduction).** gen-bind handles flat contracts (predicate on a value) but not function contracts. Aspects can contain guard functions (`{ host, ... }: { nixos = ...; }`) that cross scope boundaries. A contract on a guard function's behavior — e.g., "when given a host with `system = "x86_64-linux"`, the guard must produce a `nixos` key" — would require the full hoc-reduction with blame label swapping at each application boundary.

### Potential New Libraries or Features

**gen-contract: A standalone contract algebra.** Scope: ~200 lines. A pure library providing contract constructors (flat, function, dependent), combinators (and, or, not, implies), blame label management, and a `wrap` function that works on Nix attrsets and functions. Would unify gen-bind's `contract.nix` and gen-schema's `refined.nix` under a shared contract foundation. Interactions: consumed by gen-bind for binding contracts, gen-schema for refinement contracts, and potentially gen-aspects for aspect-level invariants.

**Dependent contracts in gen-bind.** Scope: ~50 lines extending `contract.nix`. Add `contract.dependent` that takes a context function returning a contract. The context function receives the full binding attrset, enabling cross-field predicates. Example: `contract.dependent (bindings: contract.mk { check = v: v.port > 0 || !bindings.host.isPublic; message = "public hosts need valid ports"; })`. Minimal — no new library, just an extension to the existing contract API.

**Contract monitoring mode for gen-bind.** Scope: ~100 lines. A debug-only wrapper that instruments bound values with obligation metadata (source scope, contract, establishment site). When a contract fires, the error message includes the full provenance chain — not just where the value was bound, but where it was originally produced and every intermediate scope it passed through. Useful for debugging deep policy chains in den v2.

### Research Directions

**Contract inference from NixOS types.** gen-schema's `refined.nix` requires explicit refinement declarations. An inference pass could automatically derive flat contracts from NixOS type declarations — `types.int` implies a contract checking `builtins.isInt`, `types.enum values` implies membership, `types.port` implies range 0-65535. This would provide a baseline contract layer for all gen-bind bindings without explicit annotation, analogous to Findler's observation that contracts and types play "synergistic roles" (Section 3).

**Blame propagation in scope graph resolution.** When gen-scope resolves a name (D < I < P specificity), the resolution path determines which scope contributed the value. This path could be reified as a blame chain — if the resolved value later violates a contract, the blame traces through the resolution path to the declaring scope. This connects Findler's blame tracking to Neron's scope graph resolution, creating a unified accountability model for the HOAG pipeline.

**Contracts for parametric aspects.** Den's parametric aspects (`__args`) are higher-order in Findler's sense — they are functions that accept scope arguments and produce configuration. A contract on a parametric aspect would need the full hoc-reduction: the domain contract checks the scope arguments, and the range contract checks the produced configuration. Blame assignment would follow the even-odd rule: if the aspect's output violates its range contract, blame the aspect; if the scope provides bad arguments, blame the entity declaration. This would formalize aspect correctness in den v2.
