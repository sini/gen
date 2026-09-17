---
title: 'Forgy (1982) -- Rete: A Fast Algorithm for the Many Pattern/Many Object Pattern Match Problem'
description: 'Our reading of Rete: A fast algorithm for the many pattern/many object pattern match problem.'
source:
  - den-ag-design:used/summaries/forgy-1982-rete.md
---

> C. L. Forgy, "Rete: A fast algorithm for the many pattern/many object pattern match problem," *Artificial Intelligence*, vol. 19, no. 1, pp. 17–37, 1982. doi: [10.1016/0004-3702(82)90020-0](<https://doi.org/10.1016/0004-3702(82)90020-0>) · [summary](/reference/papers/forgy-1982-rete/).

## Paper Summary

Production system interpreters spend up to nine-tenths of their execution time on pattern matching: given a set of productions (If-Then rules) and a set of working memory elements (attribute-value objects), the interpreter must find every element that matches each production's left-hand side (LHS) conditions. Naive approaches iterate over both the production set and the working memory on every cycle. Forgy observes that between any two successive cycles, working memory changes only slightly -- typically one or a few elements are added, modified, or removed. The Rete Match Algorithm exploits this temporal redundancy to avoid both iterations entirely.

The algorithm has two key strategies. First, it avoids iterating over working memory by maintaining persistent state: each pattern stores a list of the elements that currently match it, updating these lists incrementally as elements enter or leave working memory. The pattern matcher becomes a stateful black box that receives *tokens* (tagged descriptions of working memory changes: `+` for additions, `-` for deletions) and outputs changes to the *conflict set* (the set of all satisfied production instantiations). Second, it avoids iterating over the production set by compiling all LHS patterns into a single discrimination network -- a tree-structured sorting index. Tokens enter at the root and flow through the network; only the patterns they actually match are ever reached.

The Rete network contains several node types. *One-input nodes* test intra-element features: properties of a single working memory element, such as whether its class is `Expression` or its operator attribute equals `*`. These nodes form linear sequences, one per pattern, filtering tokens against constant tests and intra-element variable consistency (two occurrences of a variable within one pattern must bind the same value). *Two-input nodes* (also called join nodes) test inter-element features: constraints arising from variables shared across multiple patterns, such as requiring the `Object` attribute of a `Goal` element to equal the `Name` attribute of an `Expression` element. Each two-input node has left and right memories storing tokens that arrived from each input path. When a new token arrives on one side, the node compares it against all stored tokens on the opposite side, outputting combined tokens for consistent bindings. *Terminal nodes* sit at the bottom and signal that a production's LHS is fully satisfied, adding or removing instantiations from the conflict set.

A critical optimization is *structural sharing*: when two or more productions require identical tests, the compiler generates those nodes only once, routing both paths through the shared sub-network. In Forgy's running example, the productions `PlusOx` and `TimeOx` share the entire `Goal` pattern test sequence and differ only in the operator test on the `Expression` pattern. This sharing extends naturally across large production sets, because many rules test similar features (same element classes, same attribute constraints). The shared prefix structure gives the network its tree (or more precisely, DAG) topology and is the primary source of the algorithm's efficiency.

For negated patterns (conditions preceded by `-`), a second kind of two-input node maintains a count with each left-memory token indicating how many right-memory tokens allow consistent bindings. Tokens pass only when their count is zero -- meaning no working memory element satisfies the negated condition.

The paper describes a concrete implementation in a PASCAL-like language, linearizing the network into a sequence of instructions analogous to von Neumann machine code. Seven node types (FORK, MERGE, TEQA, TEQS, AND, NAND, TERM) are encoded in 32-bit words. Tokens are represented on a stack, and a depth-first interpreter traverses the network using a separate state stack for backtracking through FORKs and suspending two-input nodes. The instruction sequences are short enough to be microcoded.

The analytical complexity results (Table 1) establish sharp bounds. Space: the number of tokens is O(1) in working memory size in the best case, O(W^C) in the worst case (W = working memory size, C = patterns per production). The number of nodes is O(P) in production memory size (P = number of productions). Time per firing: O(1) in working memory size best case, O(W^(C-1)) worst case; O(log2 P) in production memory size best case (from the tree indexing), O(P) worst case. All bounds are shown to be sharp -- pathological production systems achieving each bound exist. Forgy notes three preconditions for the algorithm's applicability: patterns must be compilable into feature tests, objects must be constant (no variables), and the object set must change slowly between cycles.

## Key Concepts

- **Incremental match via state preservation.** The Rete network stores partial match results between cycles rather than recomputing from scratch. Each two-input node maintains left and right memories holding all tokens that have arrived from each input. When working memory changes, only the delta is processed -- new tokens flow through the network, and only the nodes they reach are activated. This transforms the match cost from proportional to total working memory size to proportional to the size of the change.

- **Compiled discrimination network.** Patterns are compiled into a tree-structured network of simple feature-testing nodes, eliminating the need to iterate over productions. The compiler examines each LHS, determines its required intra-element and inter-element features, and builds a node chain for each. The network functions as a precomputed index: a token entering at the root is sorted to exactly the terminal nodes whose patterns it satisfies.

- **Structural sharing across productions.** When multiple productions require identical tests, the compiler generates those nodes once and shares them. This is the algorithm's most distinctive feature: the network size grows as O(P) in the number of productions, not as the sum of all pattern lengths, because common prefixes are merged. Sharing also reduces runtime work -- a test evaluated once for a shared prefix need not be repeated for each production that uses it.

- **Two-phase feature testing.** Features are divided into intra-element (properties of one element: class, attribute values, intra-element variable equality) and inter-element (cross-element variable bindings). One-input nodes handle intra-element tests; two-input join nodes handle inter-element tests. This decomposition keeps individual nodes simple and allows the intra-element tests to filter heavily before the more expensive joins.

- **Token-based delta propagation.** All communication in the network uses tokens: tagged pairs of a `+`/`-` tag and a list of working memory elements. The tag propagates through joins and terminal nodes, determining whether to add or remove from memories and the conflict set. Modification of an element is modeled as deletion of the old form followed by addition of the new form.

- **Negated patterns via counted joins.** The NAND node variant maintains a count per left-memory token. The count tracks how many right-memory tokens allow consistent bindings. Only zero-count tokens pass -- no matching element exists for the negated condition. This is an efficient implementation of universal quantification over the absence of a match.

- **Sharp complexity bounds.** The algorithm's worst-case time per firing is O(W^(C-1)) in working memory size and O(P) in production memory size, but the best case is O(1) and O(log2 P) respectively. The tree indexing gives logarithmic best-case production memory cost. All bounds are proven sharp, meaning pathological systems achieve them.

## Implementation Mapping

### Current Usage in Gen Ecosystem

#### gen-derive (MAJOR)

gen-derive is a production rule system directly modeled on the Rete paper's condition-action architecture. The mapping is structural: Forgy's productions become gen-derive's rules, LHS conditions become gen-derive's `condition` field, RHS actions become gen-derive's `produce` function, and the conflict set becomes the grouped `actions` output.

**Condition-action rule model** (Forgy S1, S2). A Rete production is `(LHS, RHS)` where the LHS is a conjunction of patterns and the RHS is a sequence of actions. gen-derive's `mkRule { condition; produce; ... }` is the direct analogue: `condition` is the LHS (an opaque predicate tested by the `match` function), and `produce id ctx` generates the RHS (a list of opaque tagged actions). The `dispatch` function plays the role of the Rete interpreter's recognize-act cycle (S1: Match -> Conflict Resolution -> Act -> Goto 1). `dispatch` evaluates all rules' conditions against the current context, applies conflict resolution, fires matching rules, and returns grouped actions.

**Shared condition evaluation** (Forgy S2.2.1, Fig. 1 -- structural sharing). The Rete network's defining optimization is sharing test nodes across productions with common pattern prefixes. In gen-derive, `fromFunction` uses `builtins.functionArgs` to extract the condition from a Nix function's formal parameters. When multiple rules destructure the same arguments (e.g., `{ host, ... }:`), the `fromFunctionMatch` implementation evaluates the presence test once per context key, effectively sharing the intra-element tests. The `fired` set in `fixpoint` further reduces redundant evaluation: once an identified rule has been matched and fired, it is never re-tested in subsequent iterations -- analogous to how Rete's state preservation avoids re-evaluating patterns that haven't changed.

**Conflict resolution** (Forgy S1, step 2 -- "Select one production with a satisfied LHS"). Forgy's interpreter selects one instantiation from the conflict set; the selection mechanism is the conflict resolution strategy. gen-derive generalizes this to a three-tier resolution pipeline: override suppression (rules can explicitly replace others via `overrides`), priority sorting (numeric `priority`, with optional `exclusive` mode selecting only the highest-priority group), and specificity via the gen-select adapter. Forgy's paper leaves conflict resolution as a language-dependent operation (S4, TERM node: `UPDATECONFLICTSET(SELF(25:0))`); gen-derive makes it a first-class, extensible mechanism.

**Negative application conditions** (Forgy S2.3 -- negated patterns). Rete's NAND nodes implement negated patterns: conditions that must NOT be satisfied. gen-derive's `nac` field on rules is the direct analogue. The NAC is checked before the condition (dispatch sequence: NAC check -> condition match -> ...), exactly as Rete's negated pattern nodes filter before join nodes pass tokens downstream.

**Incremental state between cycles** (Forgy S2.1, S2.2.3 -- saving information in the network). The Rete network's two-input nodes store tokens between cycles, avoiding re-evaluation of unchanged patterns. gen-derive's `fixpoint` maintains the `fired` set across iterations: identified rules that have already fired are recorded, and on subsequent iterations they are skipped without re-evaluating their conditions. This is the same principle -- state preservation eliminates redundant work when most of the "working memory" (context) is unchanged between cycles. The `fixpoint` loop models Rete's outer recognize-act cycle: dispatch (match), apply conflict resolution, fire (act), extract feedback (working memory changes), and repeat.

**Token-like delta propagation** (Forgy S2.1.1 -- tokens as change descriptors). Rete processes deltas: `+` tokens for additions, `-` tokens for deletions. gen-derive's `fixpoint` similarly processes deltas: `extract` pulls new information from actions, `combine` merges it into the context (addition), and `eq` checks stability (no further deltas). The monotonic widening guarantee (context only grows) corresponds to a system where only `+` tokens are generated -- context keys are added but never removed, ensuring convergence.

**Concrete function-to-section mapping:**

- `mkRule` = Rete production (S1 production definition: LHS + RHS)
- `condition` = Rete LHS patterns (S1, S2.2.1 intra/inter-element features)
- `produce` = Rete RHS actions (S1: MAKE, MODIFY, REMOVE working memory)
- `nac` = negated patterns / NAND node (S2.3)
- `dispatch` = one cycle of the recognize-act loop (S1 steps 1-3)
- `fixpoint` = the outer loop (S1 step 4: Goto 1) with state preservation (S2.2.3)
- `fired` set = Rete's two-input node memories (S2.2.3: information stored between cycles)
- `fromFunction` / `fromFunctionMatch` = compiled pattern matching (S2.2.1: compiling patterns into network)
- `mkActions` / `classify` = conflict set management (S2 -- instantiations as tagged pairs)
- Three-tier conflict resolution = generalization of Forgy's conflict resolution step (S1 step 2)

### Relevance to Den v2 HOAG Pipeline

Den v2 replaces hand-rolled policy dispatch with gen-derive. Policies are the production rules; entity context (host kind, user presence, platform) is the working memory; effects (spawn, edge, drop, reroute, inject) are the RHS actions.

**Policies as condition-action productions.** A den v2 policy like `({ host, ... }: [ fx.spawn "user" { } ])` is exactly Forgy's production: the function signature `{ host, ... }` is the LHS (pattern to match against entity context), and the body `[ fx.spawn ... ]` is the RHS (actions modifying the configuration graph). The `fromFunction` bridge in gen-derive compiles these into rules, and `fromFunctionMatch` evaluates them -- the policy's `builtins.functionArgs` become the intra-element feature tests of the Rete network.

**Shared condition evaluation across policies.** In a typical den configuration, many policies test the same context keys: `host` is checked by nearly every host-level policy, `user` by every user-level policy. Forgy's structural sharing principle applies: `fromFunctionMatch` evaluates the presence of each context key once, and all policies that require that key benefit from the single check. In Rete terms, the shared `host` presence test is a one-input node near the root of the network, reached by all host-level policies.

**Fixpoint convergence for entity discovery.** Den v2's scope graph construction is iterative: a host-level policy fires and spawns user-level entities, which widen the context, which enables user-level policies to fire, which may spawn further entities. This is Forgy's recognize-act cycle: working memory changes (new context keys from `spawn` effects) trigger new matches. gen-derive's `fixpoint` manages this loop, with `extract` pulling new entity context from spawn effects, `combine` merging it into the scope, and `eq` testing whether the entity graph has stabilized. The `fired` set ensures policies fire at most once per scope, preventing infinite loops -- the state preservation mechanism from Rete S2.2.3 applied to scope graph construction.

**Phase stratification for effect ordering.** Den v2 requires structural effects (spawn, enrich) to complete before resolution effects (edge, drop, reroute) and collection effects (pipe routing). gen-derive's stratified phases, while primarily drawn from Datafun's stratification, also parallel Rete's implicit ordering: intra-element tests complete before inter-element joins, which complete before terminal node signaling. The phase DAG ensures spawn effects are processed before edge effects can reference the spawned nodes.

**NACs for constraint propagation.** Den v2's `drop` effect (prune an aspect from resolution) maps to Rete's negated patterns: "this aspect must NOT be present in scope." A policy might declare `nac = sel.attrs { type = "aspect"; name = "logging"; }` to fire only when logging is absent from the current scope. The NAND node semantics -- pass only when the count is zero -- are the correct model for conditional absence.

## Appendix: Follow-up Work

### Unexploited Ideas

- **Compiled discrimination network topology** (S2.2.1, S3.2, Fig. 2). Forgy's compiler builds an actual tree-structured network with shared one-input node prefixes, then linearizes it into instruction sequences with FORK/MERGE nodes. gen-derive evaluates conditions independently per rule via `match(condition, id, ctx)`. A true Rete network would precompute a discrimination tree over `builtins.functionArgs` signatures, routing context checks through shared prefix paths and avoiding redundant key-presence tests entirely. For configurations with hundreds of policies sharing common context key patterns, this could measurably reduce dispatch cost.

- **Two-input join node memories** (S2.2.3). Rete's two-input nodes store partial matches persistently: when a token arrives on one side, it is joined against all stored tokens on the other. gen-derive's `fired` set tracks which rules have fired but does not cache partial match state. In a multi-position dispatch scenario (gen-derive's `fixpoint` running across many scope graph positions), caching partial match results between positions could avoid redundant condition evaluation.

- **Linearized network representation** (S3.2, S4). Forgy's linearization converts the network DAG into a flat instruction stream with FORK (branch) and MERGE (join) pseudo-instructions, enabling a simple interpreter loop with a state stack. gen-derive's dispatch is structured as function calls. A linearized representation could be beneficial for very large rule sets where the overhead of Nix function calls dominates.

- **Incremental modification via paired tokens** (S2.1.1). When a working memory element is modified, Rete sends a `-` token for the old value and a `+` token for the new value. gen-derive's `fixpoint` reprocesses all non-fired rules on each iteration. A paired-token model could enable true incremental re-evaluation: when context changes, only the affected rules are re-tested, not the entire rule set.

### Potential New Libraries or Features

- **gen-rete: Compiled condition network.** A library that takes a set of rules with `builtins.functionArgs`-based conditions and compiles a discrimination DAG (Forgy S2.2.1). Shared prefix nodes would test common context keys once. The library would return a `dispatch` function that traverses the compiled network rather than iterating over rules. Scope: medium (~200 lines core). Depends on gen-algebra for identity. Useful for den configurations with 50+ policies where condition overlap is high.

- **Partial match caching for gen-derive fixpoint.** Extend `fixpoint` with optional two-input-node-style memories that cache condition evaluation results between iterations. When context changes, only rules whose conditions depend on changed keys are re-evaluated. This would require tracking which context keys each condition reads -- information already available from `builtins.functionArgs`. Scope: small extension to gen-derive (~50 lines). High impact for configurations with many fixpoint iterations.

- **Delta-driven context widening.** Replace gen-derive's current "reprocess all unfired rules" approach with Rete-style delta propagation: each `combine` step produces a set of changed keys, and only rules whose conditions reference those keys are re-tested. This narrows the per-iteration work from O(rules) to O(affected rules). Scope: moderate refactor of the fixpoint loop. Requires `fromFunctionMatch` to expose its key dependency set.

### Research Directions

- **Rete network sharing analysis for den policy sets.** Empirical study: given a real den configuration's policy set, what is the sharing factor of the compiled discrimination network? If most policies share `{ host, ... }` or `{ host, user, ... }` prefixes, the sharing factor could be very high, and a compiled network would provide significant constant-factor improvement.

- **Lazy Rete for demand-driven evaluation.** Forgy's Rete is eager: all tokens propagate through the full network. In a Nix context where evaluation is demand-driven, a lazy Rete variant could defer node activation until downstream consumers demand results. This would combine Rete's incremental state with gen-scope's demand-driven evaluation model, potentially yielding an incremental demand-driven policy dispatch engine.

- **Rete-like state for scope graph attribute caching.** gen-scope's `_eval` memoization caches computed attributes, but does not track dependencies between attribute computations. A Rete-style dependency network between attributes could enable incremental re-evaluation when scope graph structure changes (e.g., when gen-derive's fixpoint adds new nodes) -- re-computing only the attributes whose inputs changed, rather than relying on Nix's lazy evaluation to avoid redundant work. This connects to Mokhov 2018's build system traces and could enable truly incremental scope graph evaluation.
