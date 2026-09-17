---
title: Palmer et al. (2024) -- Intensional Functions
description: Our reading of palmer-2024-intensional-functions.
source:
  - den-ag-design:used/summaries/palmer-2024-intensional-functions.md
---

> Palmer, "intensional functions," 2024. *Citation not machine-verified — see the note below.*

Palmer, Zachary, Nathaniel Wesley Filardo, and Ke Wu. "Intensional Functions." Proc. ACM Program. Lang. 8, OOPSLA2, Article 274 (October 2024), 26 pages. https://doi.org/10.1145/3689714

## Paper Summary

Functions in functional languages are extensional: they support a single elimination form (application) and cannot be compared, hashed, serialized, or subjected to any non-application operation. When algorithms need to deduplicate continuations, cache function results keyed by function identity, or transmit closures across process boundaries, programmers resort to manual defunctionalization (Reynolds 1972) -- replacing functions with tagged first-order data and routing all calls through a dispatch function. This transformation is tedious, error-prone, far-reaching (transitively affecting all callers), and obscures program intent.

Palmer et al. introduce **intensional functions**, a language feature providing two new eliminators beyond application: **identify** (yielding the program point at which the function was defined) and **inspect** (producing the values captured in closure). Intensional functions carry a programmer-specified constraint function (e.g., `Eq`, `Ord`, `Hashable`) that bounds what operations can be performed on closure-captured values while simultaneously guaranteeing the function itself satisfies the same constraint. The syntax `\%Ord x -> x + y` creates an intensional function with `Ord` constraint; application uses `%$` or `%@`.

The paper's core formal contribution is the lambda-ITS calculus, a call-by-name lambda calculus with lazy substitution that makes closure environments explicit. Substitutions accumulate in the theta-position of lambda terms rather than being applied eagerly, making environments inspectable at runtime. The key formal result is **closure consistency** (Definition 5.6): for any two functions sharing the same program point (label l), if their substituted closures are equivalent, then their substituted bodies are equivalent. This is established through a chain of lemmas:

- **Lemma 4.3** -- function bodies are nonincreasing under evaluation (new environments appear but new code does not)
- **Lemma 5.8** -- initial programs (unique program points, canonical closures, empty substitutions) are closure consistent
- **Lemmas 5.9-5.12** -- closure consistency is preserved across evaluation steps
- **Theorem 1** -- any initial program remains closure consistent throughout execution
- **Theorem 2 (Soundness)** -- the lambda-ITS type system is sound, proven via encoding into System F with GADTs

The practical consequence: **conservative function equality** by comparing program points and (substituted) closure environments is sound -- functions deemed equal under this comparison always exhibit identical behavior. This is formally weaker than semantic equality (functions with different program points may still behave identically) but strong enough for deduplication.

Section 3 introduces **intensional monads** -- a reconstruction of the functor hierarchy using intensional Kleisli arrows. The motivating example is an idempotent Search monad with indexed state: `lookup` retrieves values from an index, `insert` adds entries, and continuations bound via `itsBind` are intensional functions subject to `Ord`. This enables the monad to deduplicate redundant continuations by comparing their captured closures, pruning redundant computation paths in deductive closure algorithms.

The implementation (Haskell+ItsFn, a GHC 9.2 extension) demonstrates a 25% reduction in code versus manual defunctionalization on the Plume program analysis, at the cost of ~3x runtime overhead attributable to the proof-of-concept encoding (duplicate closure storage, linked-list traversal, unfused constraint dispatch). The authors argue this overhead is an engineering concern addressable by runtime integration, not a theoretical limitation.

## Key Concepts

- **Program-point identity (S2.2)** -- each intensional function carries a unique label l corresponding to its definition site in the source program. Two functions with the same l were defined at the same syntactic location.
- **Closure inspection (S2.3)** -- the `inspect` eliminator yields the function's captured environment as a list of type-tagged existential values, each carrying proof of the constraint function.
- **Conservative equality (S2.3, S5.3)** -- two intensional functions are equal if they share the same program point AND their closures are element-wise equal. Sound but incomplete (false negatives possible, false positives impossible).
- **Constraint functions (S5.1)** -- single-method typeclasses (`Eq`, `Ord`, `Hashable`) that bound closure-captured values. Both a requirement (all captured values must satisfy) and a guarantee (the function itself satisfies).
- **Lazy substitution (S4)** -- substitutions accumulate in lambda terms' theta-position rather than being applied eagerly. Bisimilar to traditional substitution but simplifies proofs about closure structure.
- **Closure consistency (Def. 5.6)** -- the invariant that same-program-point functions differ only by substitutions, and equivalent substituted closures imply equivalent substituted bodies. Preserved throughout evaluation (Lemma 5.13).
- **Intensional monads (S3)** -- monads whose bind takes intensional Kleisli arrows, enabling the monad implementation to compare, deduplicate, or otherwise inspect continuations.
- **Intensional Search monad (S3)** -- indexed state with continuation dedup. Continuations watching the same index key with equal closures fire only once, pruning redundant computation in deductive closure algorithms.
- **Saturation-aware application (S6.2)** -- fully-applied intensional functions need not construct closures, avoiding unnecessary constraint obligations at saturated call sites.
- **Canonical closure (Def. 5.5)** -- a deterministic representation of a function's free variables and free type variables as a packed list, ensuring closure representations are comparable across function instances.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-algebra (MAJOR) -- Search monad and intensional identity

**Search monad** (`pure/search.nix`): Directly implements the intensional Search monad from S3. The `search.empty` / `search.insert` / `search.lookup` / `search.on` / `search.converge` API mirrors the paper's `insert`/`lookup`/`itsBind` operations. `search.converge` is the fixed-point loop that fires continuations on unprocessed values and repeats until stable -- the exact convergence protocol described for the intensional Search monad. Continuations created with `mkIntensional` watching the same index key are deduplicated **by name only** (`keyOf = "${indexKey}:${fn.name}"`), NOT by name+closure. This does not transfer Theorem 1's soundness guarantee — which requires equal closures *and* assumes the closure is the function's actual captured environment, whereas gen's `closure` is programmer-declared inspect data. Name-only dedup is sound under the naming-discipline convention (callers fold distinguishing data into the name).

**Intensional functions** (`pure/intensional.nix`): `mkIntensional name closure fn` creates a callable attrset with three fields corresponding to the paper's three eliminators -- `__functor` (application), `name` (identify, S2.2 program-point identity), and `closure` (inspect, S2.3 closure inspection). `intensionalEq a b` compares only `.name` fields (program-point equality), treating same-name functions as equal. This is NOT Palmer's conservative equality, which requires same program point AND element-wise equal closures (S2.3, Fig. 5). Comparing name alone is a *superset* of that relation -- it declares strictly *more* pairs equal (any two functions sharing a name, regardless of closure), so it is MORE aggressive, not more conservative. Name-only equality is sound only under the discipline that program-point names are made closure-discriminating: callers must fold any distinguishing closure data into the name string (e.g., `"myPolicy:${hostName}"`). Without that discipline it can declare behaviorally-distinct functions equal, which the paper's name+closure equality would not.

**Standalone identity** (`pure/identity.nix`): `mkIdentity` produces deterministic SHA-256 hashes from named fields, extending the paper's program-point concept to data identity beyond functions.

#### gen-aspects (MAJOR) -- Flat dispatch, diamond dedup, guard defunctionalization

**One-type dispatch in merge (S2)**: `aspectType` implements Palmer's flat typing -- one type dispatches by value shape. Attrsets and module functions merge into the submodule; guard functions wrap into `functionTo`. This is the paper's insight that intensional functions can carry enough metadata for dispatch without requiring a separate type hierarchy.

**Guard functions as callable first-order data (S5.1)**: Guard functions like `{ host, ... }: { nixos = ...; }` are wrapped via `functionTo` with explicit metadata (`__isWrappedFn`, `__functionArgs`), paralleling the paper's intensional function representation where functions carry inspectable metadata alongside their callable behavior. `canTake` performs function arg introspection (analogous to `inspect` + constraint checking) to classify functions.

**Diamond dedup in fold-based collect (S5.3, Lemma 5.12)**: Aspect identity computed from `key`, `aspectPath`, `pathKey` serves as program-point identity for aspects. When the same aspect is included through multiple paths (diamond dependency), identity comparison deduplicates emissions -- directly applying Lemma 5.12's guarantee that same-identity entities with equivalent environments produce equivalent results.

**`deferredModule` as lazy constructor**: Class content wrapped as `deferredModule` is inspectable before forcing (structural keys readable without evaluating content), paralleling the paper's distinction between identification/inspection (non-forcing) and application (forcing).

#### gen-derive (MAJOR) -- Rule identity via mkIntensional detection

**`fromFunction` with mkIntensional detection**: `fromFunction` converts Nix functions into rules, detecting `mkIntensional`-wrapped functions via a three-field check (`name`, `__functor`, `closure`) -- the exact three eliminators from the paper. When detected, the `name` field becomes the rule's identity for dedup across fixpoint iterations.

**Fixpoint dedup via fired set**: The `fixpoint` convergence loop tracks identified rules in a `fired` set. Rules with identity fire at most once across iterations, directly implementing the paper's continuation dedup principle: same identity = same computation = safe to skip on subsequent rounds. Anonymous rules (no `mkIntensional` wrapping) re-fire each iteration, corresponding to extensional functions that cannot be compared.

#### gen-select (MAJOR) -- selectorEq and isIdentified

**`sel.when` with intensional identity**: `sel.when` wraps lambdas as selectors. When the wrapped function is an intensional function (created via `mkIntensional`), the selector gains identity -- it can be compared and deduplicated.

**`isIdentified`**: Returns true when a `when` selector wraps an intensional function, checking for the three-field signature (`name`, `__functor`, `closure`). This is a direct realization of the paper's ability to distinguish intensional from extensional functions at runtime.

**`selectorEq`**: Structural equality for selectors, delegating to `intensionalEq` for identified `when` selectors. For non-identified `when` selectors, returns false (cannot compare extensional functions) -- matching the paper's treatment where only intensional functions support equality.

### Relevance to Den v2 HOAG Pipeline

Den v2 replaces the ~7000-line handler chain with a demand-driven Higher-Order Attribute Grammar over scope graphs, using 10 attributes and `lib.fix`. Palmer's paper is foundational to several aspects of this architecture:

**Scope node identity and dedup**: Each scope node carries identity derived from its declaration context. When the same aspect is reachable through multiple scope graph paths (diamond imports via I-edges), identity comparison prevents duplicate attribute computation and duplicate class emission. This is the HOAG equivalent of gen-aspects' diamond dedup, now operating at graph-node granularity.

**Policy rule convergence**: Den v2 policies fire as gen-derive rules on node context. The fixpoint loop that dispatches policies, extracts feedback (spawn, enrich), widens context, and re-dispatches relies on identified rules firing at most once. Without Palmer's intensional identity, the convergence loop would require explicit bookkeeping of which policies have fired in which scopes -- the exact manual defunctionalization burden the paper eliminates.

**Collection pipe dedup**: Pipe stages that gather data from matching scopes may encounter the same contributing scope through multiple traversal paths. Intensional identity on pipe stage functions enables dedup at the collection level, preventing duplicate contributions without requiring the consumer to manually track visited scopes.

**Attribute memoization soundness**: gen-scope's `_eval` cache assumes that the same attribute computed on the same node always yields the same value. For parametric attributes (those taking arguments), intensional identity on the argument functions provides the cache key -- two calls with intensionally-equal argument functions can safely share cached results.

## Appendix: Follow-up Work

### Unexploited Ideas

**Full closure comparison (S2.3, Theorem 1)** — *evaluated and declined (2026-05-30).* A closure-aware `intensionalEqStrict` (name + closure) was designed (den-architecture archived spec `gen-specs/gen-algebra/archived/2026-05-30-gen-algebra-closure-aware-intensional-eq-design.md`) but **not** implemented, for two reasons: (1) gen's `closure` is *programmer-declared* inspect data, not the compiler-extracted environment Theorem 1 assumes — so a name+closure form would not transfer the theorem's soundness anyway (it implements the *structure*, not the result); (2) a demo survey found no consumer needs closure discrimination (`selectorEq`, `search.dedupContinuations`, and gen-derive's `fired` set are all name-only, operating on bare lambdas / empty closures), so it would be dead code, while `toJSON`-based closure equality adds real fragility (uncatchable eval-abort on a function in the closure, store-copy on a path, serialization-≠-value equality for `1` vs `1.0`). A1 is resolved as **documentation honesty**: name-only is the deliberate, documented over-approximation; gen implements the structure of Palmer's intensional functions, not Theorem 1. (This also supersedes the earlier "less conservative … while remaining sound" framing here, which mis-stated the direction — name-only is a *superset*, i.e. more aggressive.)

**Constraint function polymorphism (S2.4)**: The paper supports polymorphic constraint functions (`\%c x y -> ...` where `c` is a type variable). The gen ecosystem uses a single implicit constraint (structural equality via `==`). Parameterizing `mkIntensional` over different constraint strategies could enable domain-specific equality (e.g., hash-based dedup for performance-critical paths, deep structural equality for correctness-critical paths).

**Intensional monads beyond Search (S3)**: The paper's intensional monad reconstruction applies to any monad, not just Search. Intensional State, intensional Writer, or intensional Reader monads could enable inspection and dedup of monadic computations in contexts beyond index-based search -- e.g., inspectable configuration transformations or deduplicated logging pipelines.

**Saturation-aware application (S6.2)**: The paper's optimization avoids constructing closures when all arguments are applied simultaneously. In Nix, this maps to avoiding the overhead of `mkIntensional` wrapping when a function is immediately called rather than stored for later comparison. A `callIntensional` primitive could skip identity/closure construction at saturated call sites.

**Runtime type comparison for heterogeneous closures (S5.1, E-Like/E-Unlike rules)**: The paper's `tyrep t1 ~ tyrep t2 ? e3 : e4` enables branch-aware type comparison of closure elements. This could enable comparing closures containing heterogeneous Nix values (functions, attrsets, strings) where current structural `==` fails on function values.

### Potential New Libraries or Features

**gen-algebra: closure-aware intensionalEq** -- Extend `intensionalEq` to optionally compare `.closure` fields when both are present and structurally comparable. Scope: small (modify `pure/intensional.nix`). Low risk -- strictly more precise than current name-only comparison while remaining sound per Theorem 1. Benefits gen-derive fixpoint (fewer redundant rule firings) and gen-select (more selector equalities detected).

**gen-algebra: intensional hash** -- Add `intensionalHash` that produces a deterministic hash from `name` + `closure`, enabling intensional functions as keys in index structures beyond the search monad. Scope: small. Enables gen-scope parameterized attribute caching keyed by intensional function arguments.

**gen-algebra: typed closure items** -- Wrap closure values in tagged containers (analogous to the paper's `ClosureItem` GADT, Fig. 20) that carry type information for heterogeneous comparison. Scope: medium. Would enable gen-derive to compare rule closures containing mixed value types, improving fixpoint precision.

**gen-memo: intensional memoization library** -- A standalone memoization library where cache keys are intensional functions. `mkMemo fn` wraps a function; cache lookups use `intensionalEq` on the function argument. Scope: medium, new library. Directly implements the paper's motivating caching example (Fig. 1-4). Benefits gen-scope attribute memoization for parameterized attributes.

### Research Directions

**Nix as an intensional language**: Nix's `builtins.functionArgs` already provides a limited form of function inspection (formal parameter names and defaults). Investigating whether Nix's evaluation model (lazy, pure, with attrset-based closures) could support a deeper form of intensional function support -- where closures are naturally inspectable as attrsets -- without language modification.

**Intensional identity and incremental evaluation**: The paper's Theorem 1 proves that identity is stable across evaluation steps. In an incremental evaluation context (where inputs change between evaluations), understanding which intensional identities remain valid across incremental steps could enable sound cache reuse across nix evaluations -- connecting Palmer's work to Mokhov et al. (2018) build systems.

**Convergence bounds from intensional structure**: The search monad's convergence depends on the index growing monotonically and continuations being finite. Intensional identity provides a static bound on the number of distinct continuations (one per program point). Formalizing this could yield tighter convergence guarantees for gen-derive fixpoint loops -- proving termination within N iterations where N is bounded by the number of identified rules.

**Composition of intensional identity**: When intensional functions are composed (f . g), what is the identity of the composition? The paper does not address this. A theory of compositional identity could benefit gen-derive's `chain` combinator and gen-scope's attribute combinators, where composed functions currently lose identity.
