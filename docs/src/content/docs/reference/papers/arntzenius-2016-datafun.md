---
title: 'Arntzenius & Krishnaswami (2016) -- Datafun: A Functional Datalog'
description: 'Our reading of Datafun: a functional Datalog.'
source:
  - den-ag-design:used/summaries/arntzenius-2016-datafun.md
---

> M. Arntzenius and N. R. Krishnaswami, "Datafun: a functional Datalog," *ICFP'16: ACM SIGPLAN International Conference on Functional Programming*, pp. 214–227, 2016. doi: [10.1145/2951913.2951948](https://doi.org/10.1145/2951913.2951948) · [open access](https://www.repository.cam.ac.uk/bitstreams/9adb9a24-14d3-4156-9e2a-ea26626e167b/download).

## Paper Summary

Datalog is a carefully restricted subset of Prolog that trades Turing-completeness for decidability: all queries terminate. This restriction enables bottom-up (forward-chaining) evaluation, making transitive closure and reachability queries natural to express -- unlike Prolog's depth-first top-down strategy, which struggles with such computations. Datalog has proven remarkably successful in practice: pointer analysis (Whaley & Lam), source code analysis (Semmle/.QL), business analytics (LogicBlox/LogiQL), distributed programming (Bloom), and authorization (Microsoft SecPAL). However, every real deployment extends Datalog in application-specific ways, and each extension requires re-establishing the metatheory from scratch.

Datafun addresses this by identifying the semantic essence of Datalog and embedding it into a higher-order functional language. The central insight is that Datalog's three restrictions (constructor-freeness, range-restriction, stratified negation) collectively enforce one property: the database transformer defined by a Datalog program is a **monotone function on a finite-height semilattice**. Datafun makes this explicit by tracking monotonicity in its type system.

The language is a simply-typed lambda calculus extended with: (1) finite set types `{A}` ordered by inclusion; (2) monotone function types `A +-> B` distinguished from discrete (unconstrained) function types `A -> B`; (3) a fixed-point operator `fix x is e` restricted to finite semilattice eqtypes, ensuring termination; and (4) semilattice types with least element and join, generalizing empty set and union. Two variable contexts -- discrete and monotone -- track which variables may appear in monotone positions. The typing rules enforce monotonicity structurally: discrete function application clears the monotone context from the argument; monotone case elimination requires branches monotone in the introduced variable; the `if+` rule restricts the else-branch to the semilattice bottom.

The paper demonstrates Datafun's expressiveness through examples that span and exceed Datalog's reach: relational algebra operations (map, filter, cross product), transitive closure (both bounded and generic), CYK parsing (impossible in Datalog due to compound data as arguments), and dataflow analyses (liveness analysis, reaching definitions). The CYK parser is particularly notable -- it takes a grammar as a first-class value, something Datalog's constructor-freeness prohibits.

The denotational semantics interprets Datafun types through three categories (Set, Poset, SemiLat) connected by two adjunctions. Types denote posets; the discrete context maps through the `Disc` comonad (discretizing the order), while the monotone context preserves order structure. The key decomposition `Set <-> Poset <-> SemiLat` via `Disc`/`|-|` and `F`/`U` is novel: the intermediate Poset category gives access to the comonad that distinguishes monotone from non-monotone computation. Fixed-point denotation uses Lemma 4: any monotone map on a finite-height pointed poset has a least fixed point computable by iterated application from the bottom element.

**Formal results:**

- **Lemma 1-3:** Semilattice types denote semilattices; finite eqtypes denote finite posets; any element of a semilattice eqtype induces a finite-height sub-poset below it.
- **Lemma 4:** Monotone maps on finite-height pointed posets have least fixed points computed by iteration from bottom.
- **Theorems 1-3:** Weakening, exchange, and both discrete and monotone substitution are admissible, with compositional semantic equations.
- **Theorems 4-5:** The logical relation `a <= b | A` is a preordered PER (partial reflexivity + transitivity).
- **Theorem 6 (Termination):** If `a | A` (the value is in the logical relation at its type), then `a` evaluates to a value.
- **Theorem 7 (Fundamental theorem):** Every well-typed term inhabits the logical relation, yielding total correctness as a corollary.

The operational semantics introduces `iter` forms that model fixed-point computation as iterative application with convergence checking, along with bounded variants (`iter<=`) that clamp to an upper bound. The termination proof uses a logical relations argument where semantic types are PERs equipped with a preorder -- the syntactic counterpart of the order structure needed in the denotational semantics.

## Key Concepts

- **Monotonicity tracking via types.** Two function types (`A -> B` discrete, `A +-> B` monotone) with separate variable contexts. The type system statically guarantees that fixed-point bodies are monotone, ensuring well-definedness and termination.

- **Semilattice types as the convergence substrate.** Types with a least element and join operator generalize sets. Fixed-point iteration starts from bottom and ascends monotonically through finite-height lattices. The bounded variant (`fix x <= e_top is e`) extends this to infinite types by clamping — ★ **and the clamp is silent**: on exceeding `e⊤` the value is *"clamped to the upper bound"* and *"may not have the value you expect"* (§3.4.1, markdown 515–523). **`FIX` is citable; `FIX≤` is not** — see the rejection under "Potential New Libraries or Features".

- **Stratified negation as post-fixpoint testing.** After a fixed-point computation completes, negative information can be tested (membership negation, absence checks). This corresponds directly to Datalog's stratified negation -- non-monotone operations are permitted only on fully-computed strata.

- **Higher-order abstraction over relations.** Generic transitive closure (`trans`), parameterized parsers, and reusable dataflow analysis frameworks become possible because relations are first-class set values and functions over them are first-class.

- **Three-category denotational semantics (Set, Poset, SemiLat).** The novel decomposition through Poset as an intermediate category provides the `Disc` comonad that distinguishes monotone from non-monotone computation, enabling the fixed-point semantics.

- **Convergence by finite height.** Termination is guaranteed not by restricting term structure (as Datalog does) but by restricting the type of the iterated value to have finite ascending chains. The bounded fixed-point operator extends this to infinite base types.

- **Iteration-based operational semantics.** Fixed points are computed by literal iteration from bottom, with convergence detected by equality testing. The `iter` forms make the computation state explicit.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-derive (MAJOR)

> ★★★ **STRUCK 2026-08-06 — THE ATTRIBUTION IS FALSE, AND THE LIBRARY NAME IS STALE.** Expert-witness
> reading of the primary, coordinates below.
>
> **1. Datafun's stated contributions are NEITHER of the two named here.** Its contribution is **tracking
> monotonicity with TYPES** — abstract (line 23), contributions (lines 134–138).
>
> **2. Worse, "stratified phase ordering" is the thing Datafun positions itself as REPLACING.** A phase
> DAG is Datalog-style stratification; lines 1717–1721 present typing and stratification as *alternative*
> routes to one effect — *"These two approaches achieve the same effect, albeit in different ways.
> Datalog's approach has the benefit that no type discipline is needed to ensure finiteness."* This
> paragraph therefore credits gen with implementing Datafun by exhibiting the mechanism Datafun was
> written to do without. The "Stratified phases" paragraph below describes **Datalog** — correctly — and
> mislabels it Datafun.
>
> **3. `gen-derive` DOES NOT EXIST.** The library is `gen-dispatch` (13 occurrences of the stale name in
> this file; live control `gen-` ⇒ 23, same file same run). The archive is stale on names as well as claims.
>
> **4. Recorded because a partial strike already failed once.** An earlier pass struck only this file's
> *recommendation* lines (importing `FIX≤`'s silent clamping); this paragraph survived it and is the
> load-bearing one — **a false ATTRIBUTION licenses design, where a false RECOMMENDATION merely proposes
> it.**.
>
> ~~gen-derive implements Datafun's two core contributions: stratified phase ordering and monotonic
> fixpoint convergence.~~

> ★★ **STRUCK 2026-08-06 — THE STRIKE ABOVE NAMED THIS PARAGRAPH; THIS EXECUTES IT.** Point 2 of the
> attribution strike identified this paragraph as describing **Datalog** while labelled Datafun, and left
> the paragraph itself unmarked — the same too-narrow scoping the strike was written to stop.
>
> Measured at the primary, same file same run: **every** occurrence of "stratified" in the paper is about
> **Datalog** — 3 occurrences under the ligature-aware predicate `strati(f|ﬁ)`, while ASCII `stratif`
> returns a **false zero** because this corpus preserves U+FB01 (live control `Datalog` ⇒ 55).
> Lines 81–84 are the list of **Datalog's** restrictions; §3.5 line 649 reads *"corresponds to a use of
> stratiﬁed negation **in Datalog**"*; §7 lines 1717–1721 present the two as *alternatives* —
> *"These two approaches achieve the same effect, albeit in different ways."*
>
> ⇒ The citation *"(Datafun S3.5, S7 — stratified negation)"* pointed at the sections that say the
> **opposite**. gen's phase DAG is a faithful implementation of **Datalog-style stratification**; it is
> **not** an implementation of Datafun, whose contribution is tracking monotonicity with **types**
> (abstract line 23, contributions 134–138). The paragraph's own last clause already said so.
> .

**Stratified phases with DAG ordering** (**Datalog**-style stratified negation — Datafun §2 lines 81–84 describe it as one of *Datalog's* restrictions, §3.5 line 649 as what a post-fixpoint membership test *corresponds to in Datalog*; Datafun's own route to the same effect is type-tracked finiteness, §7 lines 1717–1721). gen-derive's `entryAnywhere`, `entryAfter`, `entryBefore`, `entryBetween` constructors and `topoSort` implement phase stratification as a DAG. This directly parallels **Datalog's** stratified negation: each stratum (phase) can test negative information about results from prior strata, but not from its own or later strata. In gen-derive, rules in later phases see the accumulated context from earlier phases but cannot fire until those phases complete. The `classify` function routes actions to phases, and `topoSort` determines execution order -- the exact analogue of Datalog's stratification ordering.

**Monotonic fixpoint with convergence check** (Datafun S2, S4.5, Lemma 4, Theorem 7). `fixpoint` in `gen-derive` iterates: dispatch rules, extract feedback via `extract`, widen context via `combine`, check stability via `eq`. This is the operational realization of Datafun's `fix x is e`: the context is the semilattice value, `combine` is the monotone body, and `eq` is the convergence test. Monotonicity is enforced structurally: context widens monotonically (new keys are added, existing values only grow), and identified rules fire at most once across iterations (the `fired` set, analogous to Datafun's finite-height guarantee -- once every rule has fired, no new information can be produced). ~~The `maxIter` safety bound corresponds to Datafun's bounded fixed-point `fix x <= e_top is e`.~~ ★★ **STRUCK 2026-08-06** — this asserts as *already implemented* the very construct rejected below under "Bounded fixpoint" (*"`FIX` is citable; `FIX≤` is not"*), and it survived that strike because the strike was aimed at the recommendation. **The two are not the same construct:** `e⊤` bounds the **value** in the semilattice and on exceeding it the result is **silently clamped** (§3.4.1, markdown 515–523), whereas `maxIter` bounds the **iteration count**. Whether gen's behaviour on reaching `maxIter` is loud or silent is **not verified here** — but either way it is not `FIX≤`, and `FIX≤` is not citable..

**Concrete mapping:**

- `fixpoint` function = Datafun `fix x is e` (S4.5, FIX rule)
- `eq` parameter = convergence test from Datafun's `iter` operational semantics (Figure 11, `v1 === v2 : eqA`)
- `extract` + `combine` = the monotone body of the fixed-point equation
- `fired` set = finite-height guarantee (each identified rule fires at most once, bounding the ascending chain)
- ~~Phase DAG = stratified negation ordering (S3.5, S7)~~ → **Datalog's** stratification ordering, which Datafun §7 (1717–1721) positions itself as *replacing* — see the strike above
- ~~`maxIter` = bounded fixed-point `fix x <= e_top is e` (S3.4.1)~~ → **STRUCK**, `FIX≤` is not citable — see the strike above and the rejection under "Bounded fixpoint"

#### gen-graph (MAJOR)

**Monotone fixpoint iteration** (Datafun S2, Lemma 4). `graph.fixpoint { seed, step, maxIter? }` directly implements Datafun's iteration strategy: start from `seed` (the bottom element), apply `step` (the monotone function), check convergence (edge map equality). The monotonicity enforcement is explicit: gen-graph throws if the step produces a result that shrinks (fewer edges), enforcing the semilattice ordering invariant (set inclusion on edge maps). This is a direct encoding of Lemma 4's ascending chain argument.

**Transitive closure** (Datafun S3.4, the `ancestor = fix X is parent | (X . X)` example). `graph.transitiveClosure` materializes the edge map and iterates relational composition to fixpoint -- structurally identical to Datafun's `trans E = fix X is E | (X . X)` using `compose` as relational composition (Datafun S3.3, the `(.)` operator).

**Reverse reachability** (Datafun reverse-query pattern). `dependents`/`dependentsOf` compute reverse reachability by transposing the graph and querying forward. This follows Datafun's pattern where backward analyses (like liveness, S3.6) are expressed as forward fixed-point computations over the reversed flow graph.

**Concrete mapping:**

- `graph.fixpoint` = Datafun `fix x is e` with explicit monotonicity check
- `graph.compose` = Datafun relational composition `(.)` (S3.3)
- `graph.transitiveClosure` = Datafun `trans` (S3.4, `fix X is E | (X . X)`)
- `graph.unionEdges` = Datafun `|` (semilattice join on set-typed relations)
- Monotonicity enforcement (throw on shrinking) = type-level monotonicity guarantee (S4.5)

#### gen-select (Minor)

**Composable selector predicates over lattice-structured data** (Datafun S2, S4). gen-select's `sel.and`, `sel.or`, `sel.not` compose predicates that respect structural ordering. The `and [] = true` (top) and `or [] = false` (bottom) identities mirror semilattice structure on boolean predicates. While gen-select does not implement Datafun's type system, its design ensures that selector composition is monotone with respect to the structural ordering of the data being queried -- a selector that matches a node's ancestors cannot "un-match" when the ancestor set grows.

#### gen-scope (Minor)

**Stratification for derived-children** (**Datalog**-style stratification — Datafun §2 lines 81–84, §3.5 line 649; *not* a Datafun contribution, see the strike above). gen-scope's two-stage evaluation -- `children` first, then `derived-children` -- is a two-stratum stratification. `derived-children` can read attributes of nodes produced by `children`, but not vice versa. This mirrors **Datalog's** stratified negation: the second stratum can observe results fully computed by the first. The `circular` attribute combinator implements local fixed-point iteration (Sloane 2010), but the convergence model -- iterate monotone function until stable -- is the same mechanism Datafun formalizes.

### Relevance to Den v2 HOAG Pipeline

Den v2's demand-driven HOAG over scope graphs uses stratified dispatch via gen-derive, where policies are rules that fire on scope context and produce typed effects (spawn, edge, drop, reroute, inject). ~~The pipeline's convergence relies directly on Datafun's contributions:~~ ★★ **STRUCK 2026-08-06** — same false attribution as the struck paragraph above: Datafun's stated contribution is **tracking monotonicity with types** (abstract line 23, contributions 134–138), and stratified dispatch is the **Datalog** mechanism Datafun positions itself as replacing (§7, 1717–1721). The pipeline's convergence relies on **monotonicity over a finite semilattice**, which Datafun *formalizes* and Datalog also achieves — a shared foundation, not an implementation of Datafun's contribution.. The mechanisms below are stated on their own terms:

**Two-layer fixed-point as nested stratification.** Den v2's `neededBy` + recursive expansion works via: forward expand (resolve includes, fire policies) -> neededBy scan (reverse edges inject aspects) -> expand additions -> repeat until stable. This is a two-layer nested fixed-point where each layer is a monotone function on a semilattice (the set of resolved aspects and emitted modules). ~~The outer loop corresponds to Datafun's bounded fixed-point; the inner forward/neededBy alternation corresponds to stratified phases within a single iteration.~~ ★★ **STRUCK 2026-08-06** — both halves are wrong in the two ways this file has already been struck for. "Datafun's bounded fixed-point" is `FIX≤`, the **silent clamp**, which is **not citable**; the outer loop is an unbounded ascending chain, i.e. `FIX` (887–891). And "stratified phases" is the **Datalog** mechanism, not Datafun's..

**Policy dispatch as stratified Datalog.** Policies fire based on scope context (entity kind, available attributes). gen-derive's phase DAG ensures that structural effects (spawn, enrich) execute before resolution effects (edge, drop, reroute), which execute before emission effects (inject). This is stratified negation: later phases can test for the absence of structural changes (convergence of earlier phases) before making resolution decisions.

**Monotonic context widening.** As policies fire, they enrich scope context (adding attributes, spawning children, establishing edges). This context only grows -- no policy can retract a previously emitted fact. This is precisely Datafun's semilattice monotonicity invariant: the "database" of scope graph facts grows monotonically across iterations.

**Convergence guarantee.** The combination of monotonic context widening and finite entity declarations (hosts, users, aspects are finite sets declared by the user) ensures den v2's pipeline terminates. Each iteration can add at most finitely many new facts; identified rules fire at most once; the ascending chain through the lattice of scope graph states is bounded. This is Datafun's Lemma 4 applied to the configuration domain.

## Appendix: Follow-up Work

### Unexploited Ideas

**~~Bounded fixed-point with explicit upper bounds (S3.4.1, `fix x <= e_top is e`).~~ ★★★ REJECTED 2026-08-06 — DO NOT BUILD.** *(This is the second, surviving copy of the rejected proposal. The 2026-08-05 strike removed its twin under "Potential New Libraries"; **this one was left standing**, and it is the sentence the rejection below quotes as the inversion.)*

~~gen-derive's `maxIter` provides a coarse safety bound, but not Datafun's semantic bound where the fixed-point value is clamped to a meaningful upper bound `e_top`. A semantic bound in gen-derive would express: "the set of possible actions is bounded by X" -- enabling earlier termination detection and tighter convergence guarantees without relying on iteration counting.~~

★★ **Why rejected:** "clamped to a meaningful upper bound" is the paper's **silent** clamp (§3.4.1, markdown 515–523) — the value is *"clamped to the upper bound e⊤"* and *"may not have the value you expect"*, with **no error, no tag, no partiality**. Presenting it as *"enabling earlier termination detection and tighter convergence guarantees"* **inverts the paper's own caveat**, which is precisely what made the proposal read as cheap and safe. See the full rejection under "Potential New Libraries or Features" below: **`FIX` is citable; `FIX≤` is not.**.

**Monotone function types in the type system (S2, S4).** Datafun's distinction between `A -> B` and `A +-> B` has no analogue in the gen ecosystem. Nix has no type system to embed this in, but gen-schema's refinement types could potentially express monotonicity constraints: `schema.types.refined { base = functionTo ...; pred = isMonotone; }` -- validating at definition time that a function preserves ordering.

**Higher-order relations as first-class values (S3.3-3.5).** Datafun's ability to abstract over relations (generic transitive closure, parameterized parsers) is only partially exploited. gen-graph's `fixpoint` works on edge maps, not on abstract relations. A higher-order graph combinator that takes "relation transformers" as arguments -- paralleling Datafun's `trans : {finA x finA} +-> {finA x finA}` -- would enable user-defined closure operations without implementing the iteration loop.

**Semilattice aggregation beyond sets (S9, aggregation discussion).** Datafun's `W` operator generalizes set union to arbitrary semilattice joins. gen-derive's `combine` and gen-scope's `collectionAttr` both hardcode specific merge strategies (attrset merge, list concatenation). A generic semilattice-parameterized aggregation combinator would unify these.

**Loop reordering optimization (S9, termination discussion).** Datafun notes that `W(x in e1) W(y in e2) e = W(y in e2) W(x in e1) e` when variables are independent. gen-derive dispatches rules in declaration order within a phase; reordering based on independence analysis could improve convergence speed.

### Potential New Libraries or Features

**gen-lattice: Semilattice algebra for Nix.** A small library providing: `mkSemilattice { type, bottom, join, eq }` with verification that join is commutative, associative, and idempotent. Would replace ad-hoc `combine`/`eq` pairs in gen-derive's `fixpoint` and gen-graph's `fixpoint` with a single algebraic structure. Scope: ~200 lines, 20 tests. Interacts with gen-algebra (pure tier), consumed by gen-derive and gen-graph.

**~~Bounded fixpoint for gen-derive.~~ ★★★ REJECTED 2026-08-06 — DO NOT BUILD.** *(Recorded with its reason, because a rejected design that leaves no trace gets re-proposed — and this one was labelled "~50 lines, backward-compatible".)*

~~Extend `fixpoint` with an optional `bound` parameter … Mirrors Datafun's `fix x <= e_top is e` clamping semantics.~~

**Why rejected — verified at source, §3.4.1 (markdown 515–523):** *"what if the fixed point … is trying to compute exceeds e⊤? … In that case, the value … is **clamped to the upper bound** e⊤. This ensures Datafun programs terminate even in the presence of sloppy programmers, and although they **may not have the value you expect**, that value is at least predictable."*

★ **The clamp is silent and total.** A clamped result has the **identical type** to a correct one — no error, no tag, no partiality; the paper's defence is *predictability*, not detectability. Failure is **non-local**: one stray atom in the seed silently truncates the whole closure. This is precisely the defect class the project exists to remove.

★ **And it is not an implementation artifact.** It is formalized in the **denotational** semantics (Fig 10: `lfp (x ↦ if Je2K ≤ Je1K then Je2K else Je1K)`) and again operationally (Fig 11: `v⊤ otherwise`), with §5 stating the denotational semantics is primary. ⇒ **No conforming implementation can make `FIX≤` loud.**

★ **This summary dropped the paper's own caveat**, presenting clamping as a desirable *"semantic bound … enabling earlier termination detection and tighter convergence guarantees"*. That inversion is why the proposal read as cheap and safe. Treat it as evidence that **a summary is not a substitute for the paper**.

★★ **The safe half of the same paper.** Datafun's **unbounded `FIX`** (887–891) has **no clamping at all** — denotation `lfp(…)` full stop, termination from the carrier being a *structurally finite* semilattice eqtype (`finA ::= 2 | {finA} | finA + finA | finA × finA` — no `N`, no `str`), via Lemma 2 + Lemma 4. **`FIX` is citable; `FIX≤` is not.**

**What to do instead if a bound is genuinely wanted:** `gen-resolve`'s `cascade` already faces this and resolves it the other way — `semilattice-set` admitted **only** with a declared `acc = true`, since *"ACC … is undecidable from an arbitrary combine, so it is a declared carrier property, not an inferred one."* That trades the guarantee for a **loud** failure (non-termination) rather than a silent wrong answer.

**Monotonicity validation in gen-schema refinements.** A refinement combinator `schema.types.monotoneFunction { domain, codomain, ordering }` that validates (via sampling or structural analysis) that a function preserves the ordering relation. Would enable early detection of non-monotone policy functions in den v2 before they reach the fixpoint loop. Scope: ~150 lines in gen-schema, depends on gen-algebra validators.

### Research Directions

**Incremental fixpoint (semi-naive evaluation).** Datafun's S9 discusses magic sets and optimization. Semi-naive evaluation -- computing only the delta (new facts) each iteration rather than recomputing from scratch -- would dramatically improve gen-derive's fixpoint performance for large rule sets. The challenge is that Nix's lazy evaluation already provides some incrementality (unchanged thunks are not re-forced), but explicit delta tracking could further reduce work. This connects to Mokhov 2018's demand-driven build systems.

**Linear Datafun for deletion/retraction (S9, deletion discussion).** Den v2's `drop` effect removes an aspect from resolution -- a non-monotone operation. Currently this is handled outside the fixpoint (as a constraint, not a retraction). A "linear Datafun" model where certain effects consume rather than produce facts could formalize drop/substitute within the convergence framework, potentially simplifying the constraint propagation model.

**Convergence diagnostics.** Datafun's type system guarantees termination statically. gen-derive enforces it dynamically (`maxIter`). A middle ground: static analysis of rule dependency graphs to prove termination before evaluation, or to identify minimal iteration bounds. gen-graph's cycle detection applied to the rule dependency graph could detect non-terminating rule sets at definition time.

**User-defined semilattices for collection merge (S9, user-defined posets).** Den v2's collections use caller-defined merge strategies. Formalizing these as semilattice instances (with verification of the semilattice laws) would bring Datafun's termination guarantees to the collection aggregation layer, which currently relies on convention rather than enforcement.
