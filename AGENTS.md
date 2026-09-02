# gen (hub) — agent capability sheet

## Scope

The ecosystem hub: it owns no concern of its own. It publishes `mkGenLibs` — two-stage instantiation
of the gen library roster (stage 1 captures `genInputs` at definition time and binds the roster; stage
2 hands back that same value, each member flake's self-wired `.lib`) — the three **stratum buckets**
cut from that roster (`lib.substrate`, `lib.modules`, `lib.aspects`, `lib.framework`), and one
flake-parts module.
It publishes **no `mkCi`**: the CI-flake wrapper every library's `ci/` calls is
`gen-harness.lib.mkCi`, in its own repository. The harness pins no gen library, so a sibling's `ci/`
lock no longer drags the aggregator that pins that sibling — and since the hub no longer re-exports
it, there is no second route back to that edge.

## Not this library's job

The hub owns nothing; every concern belongs to a member library. Quoted text is that member's own
`flake.nix` `description` field, verbatim. Left column is the roster key under `mkGenLibs`.

| Concern (roster key) | Owner                                                                                                                                                                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `prelude`            | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem"                                                                                                                                               |
| `algebra`            | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either"                                                                                                                                       |
| `types`              | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem"                                                                                                                                              |
| `merge`              | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system"                                                                                                                           |
| `schema`             | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system"                                                                                                                                      |
| `aspects`            | `gen-aspects` — "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)"                                                                                                                                          |
| `scope`              | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs"                                                                                                                                             |
| `graph`              | `gen-graph` — "gen-graph: accessor-based graph query combinators"                                                                                                                                                                            |
| `select`             | `gen-select` — "gen-select: selector algebra for attributed graph positions"                                                                                                                                                                 |
| `bind`               | `gen-bind` — "gen-bind: module binding with external arguments for Nix"                                                                                                                                                                      |
| `dispatch`           | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)"                                                                                                                                            |
| `class`              | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system"                                                                                                              |
| `product`            | `gen-product` — "gen-product — graph products as first-class operations over accessor-graphs (Cartesian / tensor / strong / lexicographic; cells, slices, fibers, projections, quotients, restriction, containment chains), lazy in and out" |
| `settings`           | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct"                                                                     |
| `link`               | `gen-link` — "gen-link: cross-flake aspect federation over origin-labeled subgraphs"                                                                                                                                                         |

**Repos that WERE roster members and have left.** Each is off the roster, is no longer a hub flake
input, and is archived for reference under ADR-0031 F3 — no content is deleted. They are recorded
here because the roster is where a reader asks "why is there no `edge` key?", and an unexplained
absence reads as a drop rather than as a ruling. **Bind the destination, never these.**

| Former key | Repo         | Ruling      | Where the content went                                                                                                                                                                                                                                                                                                  |
| ---------- | ------------ | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `demand`   | `gen-demand` | ADR-0008 §4 | `scope` — the demand/kind folds re-express over the sole evaluator (ADR-0006); `adapters` retired without moving rather than give the evaluator a selector-algebra dependency                                                                                                                                           |
| `edge`     | `gen-edge`   | ADR-0010 §3 | `view` — the fourth destination §3 gained on 2026-08-20, beside `select`, `graph` and `scope`. The (S,T,P,M) algebra, edge-set derivation and Kahn-ordered materialization each name their destination construct per export                                                                                             |
| `pipe`     | `gen-pipe`   | ADR-0010 §3 | `view` for the channel and dataflow constructs, `select` for `sel`. B5's determinism and provenance laws are restated as properties of the query construction rather than dropped                                                                                                                                       |
| `flake`    | `gen-flake`  | ADR-0031    | The hub's `lib.compose` / interim `flakeModules.default` for the compose S2 core; `memo` for warm/override/trace; `delivery` for the projection + `realize`; the crossing's Adapter set for inject/terminals. `diff.nix` stays in the orphaned repo as reference (a named input to gen-memo's failure-attribution spec) |

**Sibling repos that exist but are NOT in the roster and NOT hub flake inputs.** Consumers reach these
directly, not through `mkGenLibs`.

| Repo       | Description (verbatim `flake.nix`)                         |
| ---------- | ---------------------------------------------------------- |
| `gen-vars` | "gen-vars: scope-driven, multi-target variable generation" |

Enumeration command (from the hub repo root) and its output:

```sh
nix eval --impure --json --expr 'builtins.filter (n: builtins.substring 0 4 n == "gen-") (builtins.attrNames (builtins.getFlake (toString ./.)).inputs)'
```

<!-- gen-inputs:begin -->

```json
["gen-algebra","gen-aspects","gen-assemble","gen-bind","gen-class","gen-delivery","gen-dispatch","gen-graph","gen-identity","gen-link","gen-memo","gen-merge","gen-prelude","gen-product","gen-program","gen-schema","gen-scope","gen-select","gen-settings","gen-types","gen-view"]
```

<!-- gen-inputs:end -->

CI-bound (den-hoag-bzcb4): `ci/agents-md-hub-inputs.nix` reads this block back out of the
committed file between the two markers above and compares it, both directions, against the
flake's own `gen-*` inputs (`gen.inputs`, filtered by prefix) — so the next hub input reddens
`nix flake check ./ci` instead of leaving this block to rot silently the way it did once
(den-hoag-8j5b, 19-vs-21).

## Exports

Entry: `inputs.gen`. Root outputs are exactly two attributes — `lib` and `flakeModules`. There are no
`packages`, `devShells`, `checks`, or `formatter` at the root.

**`lib`**

| Export          | Signature                                                                       |
| --------------- | ------------------------------------------------------------------------------- |
| `lib.mkGenLibs` | `_ -> roster` — the argument is vestigial (`lib/mkGenLibs.nix` binds it as `_`) |
| `lib.substrate` | the S1 stratum bucket — 10 members, selected from the flat roster               |
| `lib.modules`   | the S2 (module-system) stratum bucket — 2 members                               |
| `lib.aspects`   | the S3 (aspect-layer) stratum bucket — 3 members                                |
| `lib.framework` | the framework bucket — 1 member                                                 |

**There is no `lib.mkCi` here.** It lives at `gen-harness.lib.mkCi`, on the signature
`{ inputs, name, testModules, specialArgs ? {}, extraModules ? [] } -> flake outputs`, already
stage-1-applied so a consumer makes one call. Every library repository calls it from its own
`ci/flake.nix`. `gen-vars` still calls a hub `mkCi` that no longer exists, at a pinned older hub
revision; it is excluded from the inventory by ADR-0003 and is knowingly left there.

**`lib.mkGenLibs` roster** — the `roster` binding in `lib/mkGenLibs.nix`, which is the roster of
record and never a count (ADR-0015): the members are all unprefixed, plus the **`strata` declaration**
(below), which is total over them. Each member value is `genInputs.gen-<key>.lib` verbatim except
`class`. Enumerate by evaluation — `nix eval ./ci#… .#lib --apply 'x: builtins.attrNames (x.mkGenLibs {})'`.

`algebra` `aspects` `bind` `class` `dispatch` `edge` `flake` `graph` `link` `memo` `merge` `pipe`
`prelude` `product` `resolve` `schema` `scope` `select` `settings` `types` — plus `strata`

`class` is the one exception: the `class` binding re-imports `"${genInputs.gen-class}/lib"` with
`{ prelude; merge; }` rather than re-exporting `gen-class.lib`, because gen-class's own flake leaves
`merge = null`. Every other member is a plain re-export.

**The stratum declaration.** `strata` maps every member name to the layer it belongs to. It is
**total and explicit** — a member with no entry is a build error, never a member of an implicit
residue bucket, because a defaulted stratum would let a new library land silently in whatever bucket
the default names. Adding a roster member is therefore two lines in the same commit: the binding and
its stratum. Five values:

| value       | meaning                                                                                                                                          | publishes a path? |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------- |
| `substrate` | the base layer: values, graphs, selection, evaluation                                                                                            | `lib.substrate`   |
| `modules`   | the module system: the checking half and the merging half                                                                                        | `lib.modules`     |
| `aspects`   | the aspect layer, built on the module system                                                                                                     | `lib.aspects`     |
| `framework` | above the stack rather than a layer of it — a configuration framework assembles with it, and no substrate vocabulary may be defined in its terms | `lib.framework`   |
| `retiring`  | on the roster and leaving it: content is moving to another member, so it stays reachable but no consumer should newly adopt it                   | **no**            |

`framework` and `retiring` are facts about the roster, not consumer surfaces: publishing a path for
them would invite exactly the adoption `retiring` exists to prevent. Their members stay reachable on
the flat roster, unchanged.

Current assignment (derive it from `strata`, never from this heading):

```
substrate  algebra bind dispatch graph memo prelude product schema scope select
modules    merge types
aspects    aspects class link
framework  assemble settings
retiring   edge flake pipe resolve
```

**`lib.substrate` / `lib.modules` / `lib.aspects` / `lib.framework`** — the four stratum buckets,
each a **selection from the flat roster**, never a re-import: `lib.substrate.prelude` and the flat `prelude` are one
value rather than two evaluations of the same source. The distinction is invisible to a
names-and-types comparison — a library re-imported at a different pin has identical names and
identical types while being a different build — so `ci/mkgenlibs-eval.nix` holds it by value equality
(`buckets-agree`), not by shape.

★ The token `aspects` carries two senses on two nearby surfaces: `lib.aspects` is the **S3 bucket**
(`aspects`, `link`, `class`), while `lib.aspects.aspects` and `(lib.mkGenLibs { }).aspects` are the
**gen-aspects library**. Both resolve; neither shadows the other. `substrate` and `modules` carry no
such overload.

**`flakeModules`** — `flake.nix:42`

| Export                 | Signature                                                                                    |
| ---------------------- | -------------------------------------------------------------------------------------------- |
| `flakeModules.genLibs` | a **path** (`builtins.typeOf` ⇒ `"path"`), not a module value — `./flakeModules/genLibs.nix` |

Imported into a flake-parts consumer it sets `_module.args` to **eight** of the twenty roster keys,
under camelCase `gen*` names (`flakeModules/genLibs.nix:13-22`):

```
genAlgebra genAspects genBind genDispatch genGraph genSchema genScope genSelect
```

The other eleven (`class` `edge` `flake` `link` `merge` `pipe` `prelude` `product` `resolve`
`settings` `types`) are reachable via `inputs.gen.lib.mkGenLibs { }`, the sibling flake input
directly, or — for the six that declare a published stratum (`class` `link` `merge` `prelude`
`product` `types`) — the matching bucket. The other five publish no bucket path: `edge`,
`flake`, `pipe`, `resolve` (`retiring`) and `settings` (`framework`).

**Three names per library.** Flake input `gen-schema` · roster key `schema` · `_module.args` name
`genSchema`.

## Entry points by task

| Task                                                 | Reach for                                                                                                                                                                                                            |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Get the whole roster in a consumer                   | `inputs.gen.lib.mkGenLibs { }`                                                                                                                                                                                       |
| Get one stratum                                      | `inputs.gen.lib.substrate` / `.modules` / `.aspects` / `.framework` — the members of that layer, selected from the flat roster                                                                                       |
| Find out which layer a library is in                 | `(inputs.gen.lib.mkGenLibs { }).strata.<key>` — total, and forceable with no `genInputs` at all                                                                                                                      |
| Get one library                                      | `inputs.gen-<name>.lib` directly — the roster adds nothing over the flake input, except for `class`                                                                                                                  |
| Get gen-class with tier-2 (`applyCoreFixed`) working | `(inputs.gen.lib.mkGenLibs { }).class` — **not** `inputs.gen-class.lib`                                                                                                                                              |
| Inject libs as flake-parts module args               | `imports = [ inputs.gen.flakeModules.genLibs ];` (eight keys only)                                                                                                                                                   |
| Stand up a sibling library's CI flake                | `gen-harness.lib.mkCi { inherit inputs; name = "gen-x"; testModules = ./tests; }` — from `github:sini/gen-harness`, **not** this hub: pinning the hub for a harness pins every library, including the one under test |
| Use `gen-vars`                                       | their flake inputs directly — not in the roster, not hub inputs                                                                                                                                                      |
| Run the hub's real gate                              | `nix flake check ./ci` (see Drift check)                                                                                                                                                                             |
| Look up a term or a citation                         | `TERMINOLOGY.md` (§Core Terms, §Per-Library Vocabulary, §Academic References)                                                                                                                                        |
| Look up layering / dependency DAG / constraints      | `ARCHITECTURE.md` (§Dependency Graph, §Library Roles, §Design Constraints)                                                                                                                                           |

## Measured traps

Verified at rev `8eb5f29` (Nix 2.34.8), tree clean. Commands run from the hub repo root.
`f` = `builtins.getFlake (toString ./.)`. Rows marked *re-measured at the stratum commit*, and the two
stratum rows, were re-run when `strata` landed; the rest carry their original run.

| Trap                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The hub's `flake.nix` declares **no `description`** — unlike all 22 sibling repos                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `git grep -n 'description' -- flake.nix` ⇒ no output, exit 1. Positive control, same command in `../gen-select`: `flake.nix:2:  description = "gen-select: selector algebra for attributed graph positions"`, exit 0                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `nix eval .` at the root fails — there are no `packages`/`devShells`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | `error: flake 'git+file:///…/gen' does not provide attribute 'packages.x86_64-linux.default' or 'defaultPackage.x86_64-linux'`. Root outputs are `["flakeModules","lib"]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `nix flake check .` at the **root** is a false green: it prints `all checks passed!` and exits 0 having checked only output shape                                                                                                                                                                                                                                                                                                                                                                                                                                            | observed `checking flake output 'lib'` / `checking flake output 'flakeModules'` / `all checks passed!`, exit 0. The real gate is `nix flake check ./ci`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| The ci subflake reaches the hub through `gen.url = "path:.."` (`ci/flake.nix:24`) — SOURCE is live but *inputs* come from `ci/flake.lock`, so a roster addition needs a ci relock in the same commit or the gate goes red on a missing input                                                                                                                                                                                                                                                                                                                                 | measured 2026-08-05: a stale ci lock (19 `gen-*` edges, no `gen-link`) failed the gate with `attribute 'gen-link' missing` while the root lock carried 20; fixed by a targeted `nix flake lock --update-input gen` in ci/                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| The `mkgenlibs-eval` roster tripwire (`expectedKeys`) must be bumped in the SAME commit as any roster change — it is a hand-maintained list, not derived. `extra` is every actual key absent from that list, so it cannot tell a member from a declaration: the `strata` key is listed there too                                                                                                                                                                                                                                                                             | the `expectedKeys` binding in `ci/mkgenlibs-eval.nix`; `nix eval --json './ci#lib.mkGenLibsEval' --apply 'r: { inherit (r) keyCount memberCount missing extra; }'` ⇒ `{"extra":[],"keyCount":21,"memberCount":20,"missing":[]}` (re-measured at the stratum commit). Measured 2026-08-05: `gen-link` had entered the roster without a bump — `extra:["link"]` — fixed same day. Measured again when `strata` landed: an unbumped list returns `extra:["strata"]`, `rosterOk` false                                                                                                                                                                                                                                                                                                                                                       |
| The SAME contract binds `expectedSurface`, the per-member export-surface pin beside it: bump the moved member's line in the SAME commit as the pin bump that moved it. A member with no entry drifts by construction (`or null`) — a new roster member is pinned or it is named, never defaulted into agreement. Regenerate through `./ci#lib.mkGenLibsEval.surfaceHashes` and nowhere else: the arm compares what the **ci** subflake's `gen-*` nodes resolve to, so a root-flake route reads a different lock (row above) and would pin a literal that reds a correct tree | the `expectedSurface` binding in `ci/mkgenlibs-eval.nix`. Regenerate with `nix eval ./ci#lib.mkGenLibsEval.surfaceHashes --raw --apply 'h: builtins.concatStringsSep "\n" (map (k: "    ${k} = \"${h.${k}}\";") (builtins.attrNames h))'`. Measured 2026-09-01 at `badd181b`: `surfaceDrift` ⇒ `[ ]`, `surfaceHash` ⇒ `3a70a738…`, `gateKeys` 30 → 31. Control, same run: `--override-input gen/gen-resolve github:sini/gen-resolve/b729ea31…` (14 exports → 11) ⇒ `surfaceDrift:["resolve"]`, `failed:["surface-pinned"]` with the other 30 keys still `true`, and `nix build ./ci#checks.x86_64-linux.mkgenlibs-eval` exit 1. It is blind to a BEHAVIOUR change under an unchanged export surface — a docs-only bump (`gen-identity 58c114c → 1f70760`) leaves `surfaceHash` byte-identical while the lock's rev and narHash both move |
| `mkgenlibs-eval` wraps each key in `tryEval` to name *which* key broke, but a **missing flake input is not catchable by `tryEval`** in Nix 2.34.8, so the whole check aborts unnamed instead                                                                                                                                                                                                                                                                                                                                                                                 | `ci/mkgenlibs-eval.nix:51`; `(tryEval (deepSeq (throw "boom") true)).success` ⇒ `false`, exit 0, but `(tryEval (deepSeq ({ }.nope) true)).success` ⇒ throws, exit 1. Observed live during the 2026-08-05 stale-lock incident: forcing the missing key aborted unnamed, exit 1                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| The roster is **fully lazy**: `attrNames` returns all 21 keys even when `genInputs` is `{ }`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | `import ./lib/mkGenLibs.nix { genInputs = { }; }` then `attrNames (mk { })` ⇒ the full 21-key list, exit 0. Forcing one member from that same value (`(mk { }).prelude`) ⇒ exit 1. Positive control with real `genInputs` ⇒ `true`, exit 0. This is why the ci check needs `deepSeq` (re-measured at the stratum commit)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| The `strata` declaration is **pure data** — forceable with no inputs at all, unlike every member                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | same empty-`genInputs` value: `(mk { }).strata.class` ⇒ `"aspects"`, exit 0, while `(mk { }).prelude` ⇒ exit 1 in the same run. A tool can read the layering without resolving a single flake input                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `mkGenLibs`'s argument is **inert** — `{ }`, `null`, and `{ lib = throw "forced"; }` all yield the identical roster                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `lib/mkGenLibs.nix` binds it as `_`; all three `attrNames` runs returned the same list, and the `throw` was never forced                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Every application of `mkGenLibs` returns the **same value**, so `lib.substrate.class == (lib.mkGenLibs { }).class`                                                                                                                                                                                                                                                                                                                                                                                                                                                           | the `roster` binding sits in stage 1, above the `_:`. Measured across two applications: `tryEval (r1.${k} == r2.${k})` ⇒ 21/21 `true`, 0 throws. Before the roster was hoisted into stage 1 the same instrument returned 19/20 with **`class` false** — it is an `import` the hub applies itself, so a per-application binding re-allocated it. Live negative control both runs (each member against a different member) ⇒ 0 `true`                                                                                                                                                                                                                                                                                                                                                                                                      |
| `(mkGenLibs { }).class` and `inputs.gen-class.lib` expose the **same ten attribute names** but are not interchangeable: only the hub's supports tier-2                                                                                                                                                                                                                                                                                                                                                                                                                       | both `attrNames` ⇒ `["applyCoreExtend","applyCoreFixed","applyCoreMerge","compareCounters","gateCore","invariantUnder","mkClass","mkClasses","mkCore","mkCoreRecord"]`, and `? applyCoreFixed` ⇒ `true` on both. Calling it on a valid core: hub ⇒ `success = true`, raw input ⇒ `success = false` (`gen-class/lib/apply.nix:166-167` throws when `merge == null`). Positive control on the same two libs: `mkCore` and tier-1 `applyCoreMerge` both ⇒ `success = true`                                                                                                                                                                                                                                                                                                                                                                  |
| `mkCore` rejects a hand-built `{ members; archetype; }` attrset — the `class` argument must come from `mkClass`                                                                                                                                                                                                                                                                                                                                                                                                                                                              | `gen-class/lib/apply.nix` → `contract.mkCoreRecord`: `error: gen-class: mkCoreRecord: class must be a gen-class/class record`. `mkClass { key = "k"; members = [ "a" "b" ]; }` then works                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `mkCi`'s input resolution falls back to the HARNESS's pins for any tool the consumer does not declare — never to this hub's                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `gen-harness/mkCi.nix`: `resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name}`, where `genInputs` is gen-harness's own input set. This hub declares no tool inputs at all, so there is nothing here to fall back to                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Two independent lock files: root `flake.lock` and `ci/flake.lock`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | 20 vs 19 `gen-*` edges (above). Bumping the root lock does not move what CI checks, and vice versa                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| The hub's CI workflow is **not** the shared sibling workflow — it runs four jobs, and `nix flake check` is not at the sibling line numbers                                                                                                                                                                                                                                                                                                                                                                                                                                   | `.github/workflows/ci.yml` (`cat -n`): `:13` `working-directory: ci`, `:18` `nix fmt -- --ci`, `:27` `nix flake check ./ci`, `:36` `nix run ./ci#perf-bench`, `:46` `nix run ./ci#fleet-consistency`. Only `:27` was executed in this run                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

## Theory

The hub claims no result of its own. `README.md` (§Theoretical foundations) lists the
ecosystem's grounding as a flat set of areas with representative citations — attribute grammars
(Knuth 1968; Vogt 1989, HOAG; Hedin 2000, RAG; Sloane 2010, Kiama), scope graphs (Neron 2015; van
Antwerpen 2016, Statix; 2018, Scopes as Types), algebraic graphs (Mokhov 2017), intensional functions
(Palmer 2024), record algebra (Leijen 2005; Bracha & Cook 1990), contracts (Findler 2002; Chitil
2012), rule systems (Forgy 1982, RETE; Ehrig 2006; Arntzenius 2016, Datafun).

The per-result mapping lives in `TERMINOLOGY.md` (§Academic References) — a 39-row table pairing
each citation with the specific library and construct that uses it. That table, not this sheet, is
the provenance authority.

`ARCHITECTURE.md` (§Design Constraints) states the ecosystem invariants the hub's wiring
presupposes: an acyclic library DAG, no library importing another's flake inputs, opaque
actions/conditions, a nixpkgs-lib-free library level with nixpkgs entering only at the terminal plane
(historically `gen-flake`, now this hub's interim `flakeModules.default` and gen-delivery's `realize` —
ADR-0031 F3), and compose-purely/inject-VALUES-never-TYPES.

## Drift check

```sh
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in { outputs = builtins.attrNames f.outputs; lib = builtins.attrNames f.lib; flakeModules = builtins.attrNames f.flakeModules; roster = builtins.attrNames (f.lib.mkGenLibs { }); }'
```

Current output (verbatim):

```json
{"flakeModules":["default","genLibs"],"lib":["aspects","compose","framework","mkGenLibs","modules","substrate"],"outputs":["flakeModules","lib"],"roster":["algebra","aspects","assemble","bind","class","delivery","dispatch","graph","identity","link","memo","merge","prelude","product","program","resolve","schema","scope","select","settings","strata","types","view"]}
```

`--impure` is required: the root flake exposes no system-scoped attribute, so there is no `.#<attr>`
path that reaches `outputs`/`flakeModules` and the roster in one command.

**Checks.** The test-runner invocation, from the repo root (`.github/workflows/ci.yml:27`):

```sh
nix flake check ./ci
```

Run unmasked it exits **0** (`all checks passed!`; verified 2026-08-05 after the ci relock — see Measured traps for the stale-lock coupling).

The workflow's three other gates, cited from the same file and not executed in this run:
`nix fmt -- --ci` with `working-directory: ci` (`:13,18`), `nix run ./ci#perf-bench` (`:36`),
`nix run ./ci#fleet-consistency` (`:46`).
