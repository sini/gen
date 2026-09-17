---
title: Chitil (2012) — Practical Typed Lazy Contracts
description: Our reading of Practical typed lazy contracts.
source:
  - den-ag-design:used/summaries/chitil-2012-practical-typed-lazy-contracts.md
---

> O. Chitil, "Practical typed lazy contracts," *ICFP'12: ACM SIGPLAN International Conference on Functional Programming*, pp. 67–76, 2012. doi: [10.1145/2364527.2364539](https://doi.org/10.1145/2364527.2364539) · [summary](/reference/papers/chitil-2012-practical-typed-lazy-contracts/).

## Paper Summary

Chitil addresses a gap in the functional programming toolbox: prior to this work, no practical contract system existed for lazy functional languages. Contracts — pre- and post-conditions for functions — had become standard equipment for eager languages like Racket following Findler and Felleisen's seminal 2002 work, but three obstacles blocked their adoption in Haskell and similar lazy languages.

First, Racket's contract system relies on macros for ergonomic integration (e.g., automatic source location capture), and other languages lack equivalent metaprogramming facilities. Second, statically typed languages with Hindley-Milner type systems demand that contract combinators have simple parametrically polymorphic types — adding a contract should never change a function's type signature, yet prior approaches (e.g., HOOD's `observe`) introduced class constraints that propagated through entire programs. Third, and most critically, eager contracts are fundamentally incompatible with lazy evaluation: asserting `list nat` over `[4, -1, 2]` should yield `[4, error, 2]` (replacing only the violating element), not a monolithic error that prevents access to the valid prefix. Without this property, contracts on infinite data structures (e.g., the Fibonacci sequence) are impossible, and adding contracts anywhere in a program can change its semantics even when no contract is violated.

The paper's core contribution is a contract type `Contract a = a -> Maybe a` that supports both conjunction (`&`) and — critically — disjunction (`|>`), the combinator that prior lazy contract systems could not implement correctly. The `Maybe` wrapper allows a pattern contract to report "this constructor doesn't match" (returning `Nothing`) without raising an error, enabling the disjunction combinator to try the next alternative. This is the key insight: the earlier contract type `a -> a` suffices for all combinators except disjunction, because composition of partial identities cannot catch and recover from failures in a purely functional setting.

Chitil introduces **pattern contracts** — combinators like `pNil`, `pCons` that match on the outermost data constructor and attach sub-contracts to its fields. Pattern contracts compose via disjunction to define contracts that mirror algebraic data type definitions:

```
list c = pNil |> pCons c (list c)
```

This structural parallel between type definitions and contract definitions is not accidental — the paper identifies contracts as a practical subtyping system for algebraic data types, particularly useful for compiler passes that operate on overlapping AST variants.

The central theoretical result is that contracts are **projections** — they are both partial identities and (claimed) idempotent. Lemma 4.1 proves the partial identity property: `assert c <= id` in the information-theoretic ordering, meaning a contract can only reduce information (replace parts with bottom), never add it. Claim 4.2 asserts idempotence: `assert c . assert c = assert c`. The paper provides a proof appendix (Appendix A) establishing the partial identity property by structural induction on contract combinators, and shows that idempotence follows from idempotence of conjunction (`c & c = c`), which is claimed but left as requiring stronger proof methods than equational reasoning.

The algebra of contracts (Figure 4) is rich: conjunction is associative with `true` as identity and `false` as annihilator; disjunction is associative with `false` as identity; function contracts distribute with conjunction via `(c1 >-> c2) & (c3 >-> c4) = (c3 & c1) >-> (c2 & c4)`. Importantly, neither conjunction nor disjunction is commutative — paralleling the non-commutativity of `&&` and `||` on lazy Booleans, and the paper uses this parallel systematically to predict which lattice properties hold and which fail.

The paper extends the basic system with blame tracking (Section 5.1, following Findler-Felleisen's covariant/contravariant blame assignment), witness tracing (Section 5.2, reporting the path through the data structure to the violation point), Template Haskell code generation for pattern contracts (Section 6), IO monad contracts (Section 7.2), and treatment of strict data types where lazy contracts naturally degenerate to eager behavior (Section 7.3). The dependent function contract combinator `>>->` is presented as future work — it necessarily breaks laziness because the post-condition may force evaluation of the function argument.

## Key Concepts

- **Lazy contract semantics**: Asserting a contract over a data structure replaces only violating parts with bottom; unevaluated parts can never violate a lazy contract. This preserves the lazy evaluation semantics of the host language — adding contracts is a no-op when contracts are satisfied.

- **Contract type `a -> Maybe a`**: The `Maybe` wrapper is the minimal extension over `a -> a` that enables disjunction. `Just v` means the outermost constructor matches (with sub-contracts attached to fields); `Nothing` means mismatch at the top constructor; bottom means non-termination or deeper failure. The `Maybe` monad's `>>=` implements conjunction and `mplus` implements disjunction.

- **Pattern contracts**: Per-constructor combinators (`pNil`, `pCons`, `pAnd`, etc.) that test only the outermost constructor. This shallow inspection is what makes contracts lazy — they never look deeper than one constructor level before returning.

- **Contracts as projections (Lemma 4.1 + Claim 4.2)**: `assert c` is a partial identity (`assert c v <= v`) and is idempotent (`assert c . assert c = assert c`). This means applying a contract twice is the same as applying it once, and a contract can only remove information from a value.

- **The `false` contract and its blame direction**: `false` always blames the client (not the server), which is practically useful in contra-variant positions: `true >-> false >-> true` on `const` correctly blames the server (the function definition) if the second argument is demanded, because `false` is in a contra-variant position where blame is flipped.

- **Witness tracing (Section 5.2)**: Beyond binary blame, the contract system reports a *witness* — the path through constructors from root to the violation point. This is strictly more informative than Findler-Felleisen blame and is unique to this system.

- **Strict data types degenerate to eager contracts (Section 7.3)**: When all constructor arguments are strict, demanding the top constructor forces the entire structure, so lazy and eager contracts produce identical behavior. This is a pleasant property: the system adapts automatically.

- **Non-commutativity parallels lazy Booleans**: The contract algebra mirrors the algebra of `&&` and `||` over lazy Booleans — neither conjunction nor disjunction commutes, the standard distribution laws fail, but guarded commutativity and absorption laws hold. This parallel is both a proof technique and an intuition guide.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-bind — Module Binding (MAJOR)

gen-bind implements Chitil's central theorem (contracts as partial identities, S4.2) as the foundation of its lazy contract system for NixOS module argument injection.

**Concrete mapping:**

- `contract.mk { check; message; }` in `nix/lib/contract.nix` creates a contract record. The `check` predicate corresponds to Chitil's `prop` combinator for flat types (S2) — it tests a predicate on the value without forcing anything beyond what the predicate itself demands.

- `contract.apply contract value prov` in `contract.nix` implements `assert c` — the partial identity that returns the value unchanged if the check passes, or throws with blame information if it fails. The `prov` (provenance) parameter maps to Chitil's blame tracking (S5.1), carrying the source and scope through to error messages.

- `contract.hasFields`, `contract.isType`, `contract.nonEmpty` are pre-built flat-type contracts corresponding to specific `prop` instances.

- The wrapping pipeline in `wrap.nix` applies contracts via `applyContracts`, which wraps each binding value in a thunk: the assertion fires only when `evalModules` forces the bound argument. This is the direct implementation of Chitil's core guarantee — unevaluated parts never trigger violations (S2, the Fibonacci example). A module that declares `{ host, ... }:` but never accesses `host.system` will never trigger a contract on `system`.

- The `wrapAll` batch API pre-computes contracts once across a module list, which is sound because contracts are projections (applying the same contract to the same value is idempotent, Claim 4.2).

**Divergences from the paper:** gen-bind uses flat `assert`-style contracts rather than the full `a -> Maybe a` type with pattern contracts and disjunction. This is appropriate because Nix values at the binding boundary are almost always flat attrsets — there is no need for constructor-level pattern matching over algebraic data types. The `Maybe` wrapping and `|>` disjunction combinator are not implemented because Nix's type system does not have user-defined algebraic data types in the Haskell sense.

#### gen-schema — Typed Record Registries (MAJOR)

gen-schema implements Chitil's lazy contract semantics for refinement types, enabling deferred validation that preserves demand-driven evaluation.

**Concrete mapping:**

- `schema.types.refined` in `nix/lib/refined.nix` attaches predicate refinements to NixOS types. Each refinement record `{ check; message; lazy?; }` is a contract in Chitil's sense — a predicate that acts as a partial identity on the type's value space.

- The `lazy = true` flag on a refinement switches from eager validation (check runs during `applyPipeline`) to lazy validation: the value is wrapped with `builtins.addErrorContext`, deferring the check to access time. This directly implements Chitil's partial-identity semantics (Lemma 4.1): `assert c v <= v`, where the wrapped value behaves identically to the unwrapped value until the violating part is actually demanded.

- `schema.blame` in `blame.nix` implements field-level error attribution, combining Chitil's witness tracing (S5.2) with Findler's blame assignment (S5.1). The `{ field, message }` record identifies both *what* violated the contract and *where* in the structure it occurred.

- Composed refinements (passing a list to `schema.types.refined`) implement Chitil's conjunction combinator (`&`): all refinements must pass, and they are checked in sequence. The associativity and identity laws (Lemmas A.9-A.11) hold because `assert c2 . assert c1 = assert (c1 & c2)` (Lemma A.5).

**Divergences from the paper:** gen-schema uses `builtins.addErrorContext` as the laziness mechanism rather than constructing `Maybe`-wrapped values. This is the Nix-native equivalent — `addErrorContext` attaches an error message to a thunk without forcing it, achieving the same semantic guarantee: the check runs only when the value is demanded.

### Relevance to Den v2 HOAG Pipeline

Den v2's demand-driven Higher-Order Attribute Grammar pipeline is fundamentally lazy — scope graph attributes are computed only when demanded, and class content (NixOS modules) is packaged as `deferredModule` thunks that evaluate only when `evalModules` imports them. Chitil's lazy contracts are critical to this architecture in three ways:

**1. Contracts cannot break demand-driven evaluation.** In the HOAG pipeline, a host's attribute is computed only when something downstream demands it (e.g., a NixOS configuration builds and forces the `nixos` class output). If contracts were eager (Findler-style), attaching a contract to a binding would force evaluation of that binding's value, which would force evaluation of the attribute, which would force evaluation of the entire subtree — defeating the demand-driven model. Chitil's partial-identity guarantee (Lemma 4.1) ensures that `assert c v` is informationally no greater than `v`, so the contract cannot introduce new demands.

**2. Unbuilt hosts have zero contract cost.** Den's fleet model may declare hundreds of hosts, but a single `nix build` targets one. gen-bind's contracts, following Chitil's semantics, are thunks attached to binding values. For unbuilt hosts, the binding values are never demanded, the thunks are never forced, and the contracts never run. This is the lazy contract property from S2: "a computation may succeed without any contract violation error, if it only demands those data structure parts that meet the contract."

**3. Refinement contracts compose with the scope graph evaluation order.** gen-schema's lazy refinements on entity kinds (e.g., a `host` kind with `schema.types.refined port { check = p: p > 0 && p < 65536; lazy = true; }`) defer validation to the point where a host's port is actually accessed. In the HOAG pipeline, this means the refinement check integrates seamlessly with gen-scope's attribute evaluation — the check fires as part of the natural evaluation cascade, not as a separate validation pass that would require materializing the entire graph.

**4. Idempotence enables safe re-emission.** The HOAG pipeline may resolve the same aspect multiple times through different scope graph paths (diamond patterns). Chitil's idempotence claim (Claim 4.2) means that applying the same contract to a value that has already been contracted is a no-op. gen-bind's `wrapIdentity` dedup prevents redundant module emission, but when the same binding flows through multiple paths, the contract's idempotence ensures correctness regardless of dedup behavior.

## Appendix: Follow-up Work

### Unexploited Ideas

- **Dependent function contracts (Section 9, the `>>->` combinator).** Chitil defines `>>->` where the post-condition can reference the actual argument value, but notes it breaks laziness. In a Nix context, this would allow contracts like "the output module's `networking.hostName` must equal the input `host.name`" — a relational contract between binding input and module output. The challenge is the same as in the paper: such a contract forces evaluation of the argument to check the post-condition. However, in Den's pipeline, certain binding relationships are *known* to be forced eventually (e.g., the host entity context is always demanded by the host's NixOS configuration). For these statically-known-to-be-demanded bindings, dependent contracts would not introduce new evaluation costs.

- **Pattern contracts for algebraic data types (Sections 3-4).** gen-bind uses flat predicate contracts only. Pattern contracts with disjunction (`|>`) would enable structural contracts on nested attrsets: "this attrset is either `{ type = "host"; addr = ...; }` or `{ type = "user"; shell = ...; }`" — matching only the outermost constructor (top-level keys) and attaching sub-contracts to fields. This maps to Chitil's `pCons`/`pNil` with the attrset constructor replacing list constructors.

- **Witness tracing with path accumulation (Section 5.2).** gen-bind's blame messages include provenance (source, scope) but not a structural *witness* — the path through the data structure to the violation. Chitil's witness tracing accumulates `String -> String` context transformers along the path. In Nix, this could be implemented as attrpath accumulation: `host.users.tux.{shell}` indicating the violation is at `shell` within the `tux` user within `host.users`.

- **Algebra of contracts for optimization (Section 4, Figure 4).** The laws `true & c = c`, `c & true = c`, `true >-> true = true` enable compile-time simplification of contract expressions. gen-bind and gen-schema do not currently exploit these laws — every contract is checked independently. A contract composition layer could fuse `hasFields ["name"] & hasFields ["system"]` into `hasFields ["name" "system"]`, and `true >-> true` on pass-through bindings could be eliminated entirely.

- **IO/abstract type contracts (Section 7.2).** Chitil defines `io c = \io -> Just (io >>= return . assert c)` for the IO monad, noting that abstract types need their own contract combinators built from the type's `map` function. In Nix, the analogous abstract types are derivations and paths — values that are opaque until built. A derivation contract might wrap the derivation's output with a check that runs post-build, which would be a fundamentally different execution model but follows the same principle of type-directed contract combinators.

### Potential New Libraries or Features

- **gen-contract: a contract combinator library.** Scope: ~200 LOC. Provide `mk` (flat), `hasFields` (pattern-like for attrsets), conjunction `all`, disjunction `any` (try first, fall back), `not` (negated pattern), and `fn` (function contract: pre/post). Built on gen-algebra pure tier. Currently gen-bind and gen-schema each implement their own contract primitives — a shared library would unify the vocabulary and enable the algebraic laws from Figure 4 for optimization. Interaction: gen-bind and gen-schema would both consume gen-contract; gen-schema's `refined` would become a thin wrapper over `gen-contract.mk`.

- **Structural witness tracing for gen-bind blame messages.** Scope: ~80 LOC addition to `contract.nix`. Implement Chitil's `(String -> String)` context accumulator as attrpath prefix threading. When `contract.apply` is called on a nested attrset, each level of access appends to the path. Violation messages change from `"value must have fields: name, system"` to `"at host.users.tux: value must have fields: name, system"`. Interaction: requires gen-bind's `wrap` to pass path context through recursive wrapping of imports-attrset modules.

- **Dependent contracts for known-forced bindings.** Scope: ~60 LOC. For bindings where the consumer guarantees eventual evaluation (e.g., entity context bindings that are always destructured by every module), allow `contract.dependent { pre; post; }` where `post` receives both the input binding and the module's output. This is Chitil's `>>->` restricted to the safe case where the pre-condition value is known to be forced. Interaction: requires gen-bind to distinguish "always-forced" bindings (entity context) from "maybe-forced" bindings (enrichment, pipes) in its signature metadata.

### Research Directions

- **Completeness vs. meaning preservation tradeoff in Nix.** Degen, Thiemann, and Wehr (2012, cited as [8]) prove that no contract system can be both meaning-preserving and complete. Chitil's system is meaning-preserving but not complete — some contract violations are never detected because the violating part is never demanded. In Den's fleet model, this is a feature: unbuilt hosts silently pass contracts. But for fleet-wide validation tooling (e.g., `den check`), a user might want a *complete* mode that forces all contracts regardless of demand. The question is whether a single contract library can expose both modes cleanly, or whether completeness requires a fundamentally different mechanism (full-graph materialization + eager checking).

- **Contract inference from NixOS option types.** gen-schema requires manual refinement declarations. Chitil's type-directed contract combinators suggest an automatic approach: given a NixOS option type (`lib.types.int`, `lib.types.str`, `lib.types.enum`), mechanically derive a contract combinator. `lib.types.int` yields `contract.isType "int"`; `lib.types.enum vals` yields `contract.mk { check = v: lib.elem v vals; }`; `lib.types.attrsOf t` yields a recursive pattern contract. This would reduce the annotation burden for gen-schema kind definitions.

- **Contract-preserving mixin composition.** gen-schema's `mkMixin`/`composeMixins` operate on records. If records carry contracts (refinements), mixin composition should preserve the contracts from both the parent and the mixin, using Chitil's conjunction law: `(c1 >-> c2) & (c3 >-> c4) = (c3 & c1) >-> (c2 & c4)` (Lemma A.22). Currently, mixin application does not compose contracts — refinements from the parent and the mixin are independent. A contract-aware mixin combinator would ensure that the composed record carries the conjunction of both refinement sets, with the algebraic laws guaranteeing that the result is still a valid projection.
