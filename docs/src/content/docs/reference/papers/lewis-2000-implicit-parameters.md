---
title: 'Lewis, Shields, Meijer & Launchbury (2000) — Implicit Parameters: Dynamic Scoping with Static Types'
description: Our reading of Implicit parameters.
source:
  - den-ag-design:reference-catalog/summaries/lewis-2000-implicit-parameters.md
---

> J. R. Lewis, J. Launchbury, E. Meijer, and M. Shields, "Implicit parameters," *POPL00: Symposium on Principles of Programming Languages 2000*, pp. 108–118, 2000. doi: [10.1145/325694.325708](https://doi.org/10.1145/325694.325708) · [open access](https://dl.acm.org/doi/pdf/10.1145/325694.325708) · [summary](/reference/papers/lewis-2000-implicit-parameters/).

*POPL 2000: 27th ACM SIGPLAN-SIGACT Symposium on Principles of Programming Languages,
Boston MA, January 2000, pp. 108–118. Lewis, Shields and Launchbury at Oregon Graduate
Institute; Meijer at University of Utrecht.*

**The archived markdown is an OCR scan and its four figures — the typing rules, the inference
algorithm, the axiomatic semantics and the translation — are destroyed. Read any rule from
`pdf/lewis-2000-implicit-parameters.pdf`. Prose, section numbers, theorem numbers and Haskell
examples in the markdown are sound.**

## Paper Summary

The paper introduces **implicit parameters**: dynamically scoped variables that live inside a
statically-typed Hindley-Milner framework, with their presence *inferred* from use rather than
declared. The motivating scenario (§1) is a pretty printer with a hard-coded display width
checked on "line 478 of one thousand lines of code, and it is 5 levels deep in the recursion".
The two conventional options — a global, or an extra parameter threaded through every function
— are both unsatisfactory, "especially annoying because the change that you wish to make is
conceptually rather small, yet implementing it will require a significant change to the
program". The proposal is to change only line 478, writing `?width` instead of `78`. The `?`
is an annotation marking an identifier as an implicit parameter, and the inferred type becomes

```haskell
pretty :: (?width :: Int) => Doc -> String
```

Three behaviours follow, and the paper leans on all three. **Propagation is automatic**: "when
a function with implicit parameters is called, its implicit parameters are inherited by the
caller", so a helper `worker :: (?width :: Int) => …` gives `pretty` the parameter "without
lifting a finger". **Uses merge**: two calls to `pretty` in one term yield one `?width`, not
two. **Binding is by `with`**, whose scope is *dynamic* where `let`'s is static —
`pretty d with ?width = 78`. `with` bindings are not recursive and can be rebound, and
merging is escaped by renaming (the `beside` example binds `?width = ?xwidth` on one side and
`?width = ?ywidth` on the other, yielding `beside :: (?xwidth :: Int, ?ywidth :: Int) => …`).

**§2 gives the type system** for λ^ip, a call-by-name lambda calculus with let-bound
polymorphism, implicit variables and `with`. The system is Hindley-Milner extended with a new
**implicit-parameter context `C`** tracking which implicit parameters a term uses; type schemes
carry these contexts, so generalization now abstracts implicit parameters as well as type
variables, written `gen(C,Γ,τ)`. Figure 1 gives the rules MVAR, PVAR, IVAR, APP, ABS, LET,
WITH.

The design decisions in §2.1 are the substance:

- **Implicit parameter bindings are monomorphic.** Unlike `let`, "we get to see both what the
  variable is bound to, and everywhere it is used; hence, we can generalize. Since this is a
  luxury that we are not afforded with dynamic scoping, we must restrict implicit parameters to
  be monomorphic." From the type system's perspective implicit parameters "are thus very much
  like lambda-bound variables, whose binding sites just happen to be far removed from their
  usages."
- **There are no APP or ABS rules for implicit parameters, and `⇒` types appear only in type
  schemes.** Together these make it "clear that functions can't take implicitly parameterized
  arguments" — the same reason lambda-bound variables are not generalized: otherwise "we would
  have to either abandon type inference, or abandon type safety." This is what defuses the
  Lisp downward-funarg problem (§6.1).
- **IVAR and WITH are the only rules that add and remove context elements**; `C\?x` denotes `C`
  with any binding for `?x` removed. IVAR corresponds to MVAR, and "WITH corresponds to a LET
  writ backwards".
- **In LET, the dynamic context `D` used on `u` is completely independent of the context `C` of
  the consequent.** "The independence of `D` and `C` assures us that all implicit parameters
  arising in `u` end up being associated with" the let-bound variable.
- **PVAR** is modified only to insist that the instantiated implicit parameters of the variable
  be included in the judgement's context.

**§2.2 principal types.** The extension preserves principal types. "More general" is extended
to mean, in addition, *with fewer implicit parameters*: `C ⇒ τ` is more general than `D ⇒ υ`
iff some substitution θ satisfies `θC ⊆ D` and `θτ = υ`. A term may be given more implicit
parameters than it uses — both `Int` and `(?z :: Bool) => Int` are valid typings of `1`.

**§2.3 type inference** (Figure 2, in the deductive style of Rémy [15]). `mgu(C₁,C₂)` on
implicit parameter contexts returns `(θ,C)` with `C` the smallest context containing both
`θC₁` and `θC₂`, built by unifying the types of each label common to both. Substitutions form
a semi-lattice and the algorithm takes least upper bounds. **Theorem 1 (Soundness)** and
**Theorem 2 (Completeness)** relate algorithm and system; Theorem 2 implies the inferred type
is principal.

**§3 gives two semantics.** §3.1 works the intuition through examples and finds the crux:
because `let`-bound terms are generalized over their implicit parameters, "each occurrence of
`p` should be evaluated with its own local environment", so `let p = ?y + 2 in (p + (p with ?y = 1)) with ?y = 2` is 7, not 8. Under β-reduction of a lambda the situation is different —
`x` is monomorphically typed, so an argument's implicit parameters must be supplied by the
*surrounding* context. "Just as we must take care to avoid static name capture by renaming
bound variables, we must also avoid **dynamic name capture** by rebinding implicit variables."
The mechanism is rerouting through a **fresh implicit variable** `?z`.

**§3.2 axiomatic semantics** (Figure 3) gives β-, η- and α-rules with **three substitution
operators, one per binding form and hence per variable class** — λ-vars, let-vars, implicit
vars. The load-bearing clauses:

- `(t with ?y = v)[x ↦ u]` rebinds via a fresh `?z` "to ensure that if `u` has an implicit
  parameter `?y`, its binding will bypass the binding of `?y` to `v`".
- The `let` case of λ-substitution similarly bypasses all implicit parameters of `u` "lest they
  become captured by `q`". This rule **changes the type of `q`** — `q` gains dependence on the
  fresh `?z` — though "the overall term's type remains unchanged".
- **β-reduction of a `let` performs no such rebinding**: a let-bound term is always generalized
  on all its implicit parameters, so `t[p ↦ u]` "is essentially λ-calculus substitution".
- For `with`, "since implicit variables are lexically distinct from static variables, there is
  never a danger of a name capture", and "since implicit parameters are immutable, the dynamic
  environment need not be threaded state-like through the program" — so `(t v)[?x ↦ u]` simply
  propagates `u` into both `t` and `v`.
- η-rules include `?x with ?x = t = t`.

**§3.3 translation semantics** (Figure 4) is a **type-directed translation into ordinary
call-by-name lambda calculus with let-bound polymorphism and tuples**, by induction over a
typing derivation. It "borrows the technique of **dictionary passing** [16], used to give a
semantics for overloading in Haskell": `C ⇒ τ` is encoded as `C → τ` and implicit parameter
contexts become **tuples of explicit parameters**. In the target, `?x` is an ordinary variable
— the `?` is retained only to keep introduced identifiers distinct. Coherence holds because
the only variation between derivations is additional unused parameters. **Lemma 3** and
**Theorem 4** establish that the axiomatic semantics is sound with respect to the translation.
This translation is the basis of the implementation in Hugs.

**§4 examples**, from the Hugs implementation. §4.1 **auxiliary parameters in recursive
definitions**: the worker-wrapper idiom hides the worker in a `where`, which means it cannot be
tested or typed separately — "because standard Haskell lacks the ability to express scoped type
variables, we cannot even give a type signature for `prepend`". Implicit parameters let the
worker be top-level with a real type. §4.2 **environments**: shell-style environments, where
"the far more common idiom is to make changes to the environment that only scope over
sub-processes, but do not propagate forward" — which is exactly `with`. Also cited: GUI
graphics contexts, and numerical-method tolerance parameters. §4.3 **file IO**: redefining
`getLine`/`putStr` with `?stdIn`/`?stdOut` so a session can be redirected without touching its
code. §4.4 **JNI**: making the `JNIEnv` pointer implicit across every primitive so that "all
functions which use them automatically get the `jnienv` as an implicit argument as well".

**§5 in-the-large.** §5.1 **call-by-need**: a let-bound term with implicit parameters cannot
share evaluation — `(let x = fib ?y in (x,x)) with ?y = 10` computes `fib 10` twice.
Semantically this is fine ("such a term is a value, and there's no computational cost to
share"); the problem is that "a programmer is accustomed to being able to distinguish a value
from a computation by looking at its syntax alone, whereas in our system the type is also
important". Haskell's **monomorphism restriction** is the wrong fix here — applying it would
statically bind `?y` and put the language "in stark disagreement with our axiomatic semantics".
"To address sharing, the programmer must be given either knowledge or control, and not be
subject to editorial distinctions that the language designers might make": either programming
environments where type information is available while editing, or **two `let`s** — a
non-generalizing one that promises sharing and a generalizing one that does not. §5.2
**call-by-value**: no technical difficulty, translation unchanged, axiomatic semantics weakened
as usual; with effects the dual surprise appears — a duplicated side effect instead of
duplicated work, "but again, there is no surprise if the programmer knows the type of `x`".
ML's value restriction "may be somewhat relaxed in our system without compromising soundness"
since any term requiring implicit parameters is semantically a value. §5.3 **overloading**:
implicit parameters and Haskell-style overloading coexist happily (both are dictionary
passing), but implicit parameters **cannot replace type classes** — all instances of an implicit
parameter must have the same type, so `map` used at two types would be ill-typed. "So clearly
our programme remains unfinished." §5.4 **signatures**: the low-impact promise is undercut by
existing type annotations, which all change; the proposed mitigation is **partial contexts** —
an ellipsis, `pretty :: ... => Doc -> String`.

**§6 related work.** §6.1 Lisp introduced dynamic scoping "albeit as a bug that took decades to
stamp out"; MIT Scheme's `fluid-let` binds dynamically by side effect. The **downward funarg
problem** is avoided here because implicitly parameterized functions are not first-class:
"implicit parameters always float towards outer contexts, they don't enter inner ones". The
authors claim this is "the first type system that we know of that records the use of dynamic
parameters in the types". §6.2 λ^ip is close to the syntax-directed variant of **Jones' OML**,
differing in two ways: all instances of an implicit parameter are assumed to be the same, and
implicit parameters have a **local binding construct**. That local construct is what forces the
conservative LET rule — the permissive Haskell-style rule that lets unresolvable predicates
escape would cost principal types, shown by `let p = ?x in (p with ?x = 1)`, which gets the two
**incomparable** typings `Int` and `(?x :: α) ⇒ α` whose lub is not a type for the term. "This
problem doesn't affect Haskell, because there is no local binding mechanism corresponding to
`with`. All instance declarations in Haskell are global." §6.3 notes Odersky-Wadler-Wehr
overloading of individual identifiers (similar constraints, no local binding) and the
Garrigue–Aït-Kaci label-selective lambda calculus (changes λ-abstraction itself).

**§7 future work** conjectures that **comonads** are the structure underlying implicit
parameters: "monads model the effect of performing a computation, and are thus associated with
outputs … Comonads, on the other hand, model the structure of environments, and are thus
associated with inputs, or the left-hand sides of judgements." The goal stated is to show the
translation represents "the term language of a family of coKleisli categories within the term
language of the base category".

## Key Concepts

- **Implicit parameter (§1, §2.1).** A `?`-annotated identifier, lexically distinct from
  ordinary variables, whose presence in a type is *inferred from use*, not declared.

- **Implicit parameter context `C` (§2.1).** A new context alongside `Γ`, carried in type
  schemes; generalization `gen(C,Γ,τ)` abstracts implicit parameters as well as type variables.

- **`with` (§1, §2.1).** The binding construct. Dynamic scope where `let` is static; not
  recursive; freely rebindable; associates to the left. "WITH corresponds to a LET writ
  backwards."

- **Automatic propagation and merging (§1).** Callers inherit callees' implicit parameters; two
  uses of the same name in one context merge into one parameter. Renaming at the `with` is the
  escape hatch.

- **Monomorphic implicit bindings (§2.1).** Forced by the absence of a visible binding site;
  makes implicit parameters behave like lambda-bound variables with distant binders.

- **No APP/ABS rules for implicit parameters; `⇒` only in schemes (§2.1).** Functions cannot
  take implicitly parameterized arguments. This is the deliberate restriction that buys type
  inference *and* type safety together, and it is what avoids the Lisp downward funarg problem.

- **Independence of `D` and `C` in LET (§2.1).** The context under which a let-bound term is
  typed is unrelated to the context of the surrounding judgement; this is what makes all of
  `u`'s implicit parameters attach to the let-bound name.

- **Principal types with a "fewer implicit parameters" ordering (§2.2).** `C ⇒ τ ≤ D ⇒ υ` iff
  some θ gives `θC ⊆ D` and `θτ = υ`. Terms may be typed with unused implicit parameters.

- **`mgu` on contexts (§2.3).** Unification lifted to implicit parameter contexts: smallest
  context containing both, unifying types at shared labels. Substitutions form a semi-lattice;
  the algorithm takes lubs. **Theorem 1** soundness, **Theorem 2** completeness.

- **Dynamic name capture and fresh-variable rerouting (§3.1, §3.2).** The dual of static name
  capture. Substituting into a term under a `with` must not let the argument's implicit
  parameters be captured by that `with`; the fix routes the correct binding through a fresh
  implicit variable `?z`.

- **Three substitution operators (§3.2, Fig. 3).** One per binding form — λ-var, let-var,
  implicit var. Only the λ-var and implicit-var cases rebind; **let-var substitution needs no
  rebinding** because let-bound terms are already generalized over their implicit parameters.

- **Dictionary-passing translation (§3.3, Fig. 4).** `C ⇒ τ` becomes `C → τ`; contexts become
  tuples of explicit parameters; type-directed over the derivation; coherent. This is both the
  second semantics and the implementation strategy — it is how the feature was added to Hugs.

- **The sharing problem (§5.1, §5.2).** A let-bound term with implicit parameters is a value,
  so work (call-by-need) or effects (call-by-value) are duplicated per use. Detectable only
  from the type. The monomorphism restriction is explicitly rejected as the remedy; the
  proposals are better tooling or two `let` forms.

- **Cannot subsume type classes (§5.3).** All uses of an implicit parameter must have one type,
  so overloading at multiple types is out of reach. Implicit parameters and classes coexist
  (both are dictionaries) but the deconstruction programme is unfinished.

- **Partial contexts (§5.4).** `pretty :: ... => Doc -> String` — an ellipsis permitting
  unconstrained additional context elements, so adding an implicit parameter does not force a
  global edit of type signatures.

- **The local-binding / principal-types tension (§6.2).** Because `with` is local, the
  permissive Haskell LET rule (let unresolved predicates escape) would produce incomparable
  typings and destroy principal types. Haskell escapes this only because all its instances are
  global.

- **Comonads (§7).** Conjectured structure: monads for outputs/effects, comonads for
  inputs/environments. Stated as a programme, not a result.

## Ecosystem Relevance

### Why acquired

Acquired 2026-08-05 as source material for a **gen-bind redesign spike**, paired with
`jones-1993-partial-evaluation-automatic-program-generation`. **No gen library currently cites
this paper, and none of the contact points below has been through the architecture-alignment
gate.** Treat them as review candidates.

### Applicable insights (candidates, not validated)

- **A dynamically-scoped parameter can be tracked in a type without being declared.** That is
  the paper's whole claim, and §6.1 asserts it was the first type system to record the use of
  dynamic parameters in types. Wherever a framework threads ambient context through a call
  chain, this is the formal account of doing it without threading.

- **The restriction is the design, not a limitation.** No APP/ABS rules and `⇒` confined to
  schemes together yield: parameters float *outward* only, never inward; functions cannot
  accept implicitly parameterized arguments; inference and safety survive. Any relaxation of
  this shape should be checked against §2.1's argument and §6.1's funarg discussion.

- **The `let` rule is where the design fork lives (§6.2).** Bind every implicit parameter at
  the let (conservative, principal types preserved) or let unresolved ones escape to the
  enclosing scope (Haskell-like, principal types lost *when a local binding construct exists*).
  The counterexample `let p = ?x in (p with ?x = 1)` with its two incomparable typings is the
  concrete falsifier.

- **Dynamic name capture is a real hazard with a stated remedy (§3.1, §3.2).** Substitution
  under a dynamic binder must reroute through a fresh name. A framework that substitutes or
  inlines under an ambient-context binder inherits this obligation.

- **Merging is the default and renaming is the escape (§1).** Two uses of one name in one scope
  become one parameter. That is convenient and occasionally wrong; the paper's answer is
  explicit renaming at the binding site, not a merge policy.

- **Dictionary passing is the implementation (§3.3).** Contexts compile to tuples of explicit
  parameters via a type-directed translation over the derivation. The implicit surface is
  eliminable — which also means an implicit-parameter design has a checkable
  explicit-equivalent.

- **The sharing problem is a genuine cost (§5.1).** A value carrying implicit parameters is
  re-evaluated per use, and the syntax does not reveal it. In an evaluator where re-evaluation
  is expensive this is the first question to ask of any implicit-context design, and §5.1
  argues the language-designer's usual fix (monomorphism restriction) *changes the semantics*
  rather than repairing it.

- **Signature churn and partial contexts (§5.4).** The honest admission that "low impact" fails
  against annotated code, and the ellipsis-context proposal as the mitigation.

## Appendix: Follow-up Work

### Unexploited ideas

- **Partial contexts / ellipsis (§5.4).** Proposed, not developed in the paper. A way to write
  a signature that constrains part of an inferred context and admits the rest.

- **Two `let` forms — sharing vs. generalizing (§5.1).** The authors' preferred remedy for the
  sharing problem, sketched in one sentence and never elaborated: let the programmer choose,
  and let the type checker validate the choice.

- **`mgu` on contexts as a semi-lattice lub (§2.3).** Context unification is presented
  operationally; its lattice structure is noted in passing and not exploited.

- **The comonadic account (§7).** Explicitly future work in 2000. Whether the translation
  really is "the term language of a family of coKleisli categories within the term language of
  the base category" is left open by this paper.

### Research directions

- **Does the no-APP/no-ABS restriction survive a first-class-modules or higher-order setting?**
  The paper buys inference and safety by making implicitly parameterized functions non-first-
  class. A host where such values *are* passed around does not automatically inherit the
  guarantee, and §6.1's funarg argument would need redoing.

- **Sharing under a lazily-evaluated, heavily-memoized host (§5.1).** The paper's analysis
  assumes call-by-need with per-let updating. An evaluator that memoizes on a different key —
  or that has no notion of "let-bound term" at all — may not exhibit the duplication, or may
  exhibit it somewhere else. This premise should be tested rather than assumed either way.

- **Relation to scope graphs and to the archived name-resolution corpus.** Implicit parameters
  are resolution along a *dynamic* chain with the resolvable set recorded in the type, where
  Neron 2015 / van Antwerpen 2018 resolve along a *static* graph with explicit visibility
  policies. Whether an implicit-parameter context is a degenerate scope-graph query, or a
  genuinely different mechanism, is unexamined and is the natural question given what else is
  in this archive.

- **The unfinished deconstruction (§5.3).** Lewis et al. set out to break Haskell's type-class
  system into orthogonal features and got one of them. Jones' functional dependencies [6,7]
  are cited as the next step toward encoding both implicit parameters and overloading in one
  system. Whether *both* are needed, or whether a design that never wanted overloading can
  stop at implicit parameters, is a fork the paper leaves open.
