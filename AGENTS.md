# gen (hub) — agent capability sheet

## Scope

The ecosystem hub: it owns no concern of its own. It publishes `mkGenLibs` — two-stage instantiation
of the gen library roster (stage 1 captures `genInputs` at definition time; stage 2 re-exports each
member flake's self-wired `.lib`) — plus `mkCi`, the shared CI-flake wrapper every sibling's `ci/`
calls, and one flake-parts module.

## Not this library's job

The hub owns nothing; every concern belongs to a member library. Quoted text is that member's own
`flake.nix` `description` field, verbatim. Left column is the roster key under `mkGenLibs`.

| Concern (roster key) | Owner |
|---|---|
| `prelude` | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem" |
| `algebra` | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either" |
| `types` | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| `merge` | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system" |
| `schema` | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system" |
| `aspects` | `gen-aspects` — "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)" |
| `scope` | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs" |
| `graph` | `gen-graph` — "gen-graph: accessor-based graph query combinators" |
| `select` | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| `bind` | `gen-bind` — "gen-bind: module binding with external arguments for Nix" |
| `dispatch` | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)" |
| `resolve` | `gen-resolve` — "gen-resolve — demand-driven higher-order RAG evaluator over algebraic scope graphs (Knuth 1968 attribute schedule + Vogt 1989 HOAG)" |
| `flake` | `gen-flake` — "gen-flake — the pure composition boundary of the pure-gen module ecosystem" |
| `class` | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system" |
| `edge` | `gen-edge` — "gen-edge — the content-movement contract: the (S,T,P,M) edge algebra, toposorted materialization fold, and the frozen edge-trace parity oracle" |
| `product` | `gen-product` — "gen-product — graph products as first-class operations over accessor-graphs (Cartesian / tensor / strong / lexicographic; cells, slices, fibers, projections, quotients, restriction, containment chains), lazy in and out" |
| `settings` | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct" |
| `demand` | `gen-demand` — "gen-demand — typed demand cascade (kinds resolve demands into resources + wiring + sub-demands; a stratified, terminating fold resolves the multiset with full provenance)" |
| `pipe` | `gen-pipe` — "gen-pipe — scoped channels + dataflow algebra (map/filter/fold/scan/route/join/tee) with B5 determinism, provenance, dedup, and class-aware contributions" |
| `link` | `gen-link` — "gen-link: cross-flake aspect federation over origin-labeled subgraphs" |

**Sibling repos that exist but are NOT in the roster and NOT hub flake inputs.** Consumers reach these
directly, not through `mkGenLibs`.

| Repo | Description (verbatim `flake.nix`) |
|---|---|
| `gen-rebuild` | "gen-rebuild: pure-Nix incremental rebuilder core (Mokhov rebuilder dimension)" |
| `gen-vars` | "gen-vars: scope-driven, multi-target variable generation" |

Enumeration command (from the hub repo root) and its output:

```sh
nix eval --impure --json --expr 'builtins.filter (n: builtins.substring 0 4 n == "gen-") (builtins.attrNames (builtins.getFlake (toString ./.)).inputs)'
```

```json
["gen-algebra","gen-aspects","gen-bind","gen-class","gen-demand","gen-dispatch","gen-edge","gen-flake","gen-graph","gen-link","gen-merge","gen-pipe","gen-prelude","gen-product","gen-resolve","gen-schema","gen-scope","gen-select","gen-settings","gen-types"]
```

## Exports

Entry: `inputs.gen`. Root outputs are exactly two attributes — `lib` and `flakeModules`. There are no
`packages`, `devShells`, `checks`, or `formatter` at the root.

**`lib`** — `flake.nix:39-40`

| Export | Signature |
|---|---|
| `lib.mkGenLibs` | `_ -> roster` — the argument is vestigial (`lib/mkGenLibs.nix:7,9` binds it as `_`) |
| `lib.mkCi` | `{ inputs, name, testModules, specialArgs ? {}, extraModules ? [] } -> flake outputs` |

`builtins.functionArgs lib.mkCi` ⇒ `{"extraModules":true,"inputs":false,"name":false,"specialArgs":true,"testModules":false}`
(`false` = required). `mkCi` is already stage-1-applied by the flake, so a consumer makes one call.
Live: `gen-select`, `gen-schema`, `gen-class`, `gen-pipe`, `gen-link` all call `gen.lib.mkCi` from
their `ci/flake.nix`.

**`lib.mkGenLibs` roster** — `lib/mkGenLibs.nix:11-41`. Twenty keys, all unprefixed. Each value is
`genInputs.gen-<key>.lib` verbatim except `class` (see below).

`algebra` `aspects` `bind` `class` `demand` `dispatch` `edge` `flake` `graph` `link` `merge` `pipe`
`prelude` `product` `resolve` `schema` `scope` `select` `settings` `types`

`class` is the one exception: `lib/mkGenLibs.nix:38-41` re-imports `"${genInputs.gen-class}/lib"` with
`{ prelude; merge; }` rather than re-exporting `gen-class.lib`, because gen-class's own flake leaves
`merge = null`. Every other key is a plain re-export.

**`flakeModules`** — `flake.nix:42`

| Export | Signature |
|---|---|
| `flakeModules.genLibs` | a **path** (`builtins.typeOf` ⇒ `"path"`), not a module value — `./flakeModules/genLibs.nix` |

Imported into a flake-parts consumer it sets `_module.args` to **eight** of the twenty roster keys,
under camelCase `gen*` names (`flakeModules/genLibs.nix:13-22`):

```
genAlgebra genAspects genBind genDispatch genGraph genSchema genScope genSelect
```

The other twelve (`class` `demand` `edge` `flake` `link` `merge` `pipe` `prelude` `product` `resolve`
`settings` `types`) are reachable only via `inputs.gen.lib.mkGenLibs { }` or the sibling flake input
directly.

**Three names per library.** Flake input `gen-schema` · roster key `schema` · `_module.args` name
`genSchema`.

## Entry points by task

| Task | Reach for |
|---|---|
| Get the whole roster in a consumer | `inputs.gen.lib.mkGenLibs { }` |
| Get one library | `inputs.gen-<name>.lib` directly — the roster adds nothing over the flake input, except for `class` |
| Get gen-class with tier-2 (`applyCoreFixed`) working | `(inputs.gen.lib.mkGenLibs { }).class` — **not** `inputs.gen-class.lib` |
| Inject libs as flake-parts module args | `imports = [ inputs.gen.flakeModules.genLibs ];` (eight keys only) |
| Stand up a sibling library's CI flake | `gen.lib.mkCi { inherit inputs; name = "gen-x"; testModules = ./tests; }` |
| Use `gen-rebuild` / `gen-vars` | their flake inputs directly — not in the roster, not hub inputs |
| Run the hub's real gate | `nix flake check ./ci` (see Drift check) |
| Look up a term or a citation | `TERMINOLOGY.md` (§Core Terms, §Per-Library Vocabulary, §Academic References) |
| Look up layering / dependency DAG / constraints | `ARCHITECTURE.md` (§Dependency Graph, §Library Roles, §Design Constraints) |

## Measured traps

Verified in this run at rev `8eb5f29` (Nix 2.34.8), tree clean. Commands run from the hub repo root.
`f` = `builtins.getFlake (toString ./.)`.

| Trap | Evidence |
|---|---|
| The hub's `flake.nix` declares **no `description`** — unlike all 22 sibling repos | `git grep -n 'description' -- flake.nix` ⇒ no output, exit 1. Positive control, same command in `../gen-select`: `flake.nix:2:  description = "gen-select: selector algebra for attributed graph positions"`, exit 0 |
| `nix eval .` at the root fails — there are no `packages`/`devShells` | `error: flake 'git+file:///…/gen' does not provide attribute 'packages.x86_64-linux.default' or 'defaultPackage.x86_64-linux'`. Root outputs are `["flakeModules","lib"]` |
| `nix flake check .` at the **root** is a false green: it prints `all checks passed!` and exits 0 having checked only output shape | observed `checking flake output 'lib'` / `checking flake output 'flakeModules'` / `all checks passed!`, exit 0. The real gate is `nix flake check ./ci` |
| The ci subflake reaches the hub through `gen.url = "path:.."` (`ci/flake.nix:24`) — SOURCE is live but *inputs* come from `ci/flake.lock`, so a roster addition needs a ci relock in the same commit or the gate goes red on a missing input | measured 2026-08-05: a stale ci lock (19 `gen-*` edges, no `gen-link`) failed the gate with `attribute 'gen-link' missing` while the root lock carried 20; fixed by a targeted `nix flake lock --update-input gen` in ci/ |
| The `mkgenlibs-eval` roster tripwire (`expectedKeys`) must be bumped in the SAME commit as any roster change — it is a hand-maintained list, not derived | `ci/mkgenlibs-eval.nix:17-39`; `nix eval --json './ci#lib.mkGenLibsEval' --apply 'r: { inherit (r) keyCount missing extra; }'` ⇒ `{"extra":[],"keyCount":20,"missing":[]}` (measured 2026-08-05: `gen-link` had entered the roster without a bump — `extra:["link"]` — fixed same day) |
| `mkgenlibs-eval` wraps each key in `tryEval` to name *which* key broke, but a **missing flake input is not catchable by `tryEval`** in Nix 2.34.8, so the whole check aborts unnamed instead | `ci/mkgenlibs-eval.nix:51`; `(tryEval (deepSeq (throw "boom") true)).success` ⇒ `false`, exit 0, but `(tryEval (deepSeq ({ }.nope) true)).success` ⇒ throws, exit 1. Observed live during the 2026-08-05 stale-lock incident: forcing the missing key aborted unnamed, exit 1 |
| The roster is **fully lazy**: `attrNames` returns all 20 keys even when `genInputs` is `{ }` | `import ./lib/mkGenLibs.nix { genInputs = { }; }` then `attrNames (mk { })` ⇒ the full 20-key list, exit 0. Forcing one key from that same value (`(mk { }).prelude`) ⇒ exit 1. Positive control with real `genInputs` ⇒ `true`, exit 0. This is why the ci check needs `deepSeq` |
| `mkGenLibs`'s argument is **inert** — `{ }`, `null`, and `{ lib = throw "forced"; }` all yield the identical 20-key roster | `lib/mkGenLibs.nix:9` binds it as `_`; all three `attrNames` runs returned the same list, and the `throw` was never forced |
| `(mkGenLibs { }).class` and `inputs.gen-class.lib` expose the **same ten attribute names** but are not interchangeable: only the hub's supports tier-2 | both `attrNames` ⇒ `["applyCoreExtend","applyCoreFixed","applyCoreMerge","compareCounters","gateCore","invariantUnder","mkClass","mkClasses","mkCore","mkCoreRecord"]`, and `? applyCoreFixed` ⇒ `true` on both. Calling it on a valid core: hub ⇒ `success = true`, raw input ⇒ `success = false` (`gen-class/lib/apply.nix:166-167` throws when `merge == null`). Positive control on the same two libs: `mkCore` and tier-1 `applyCoreMerge` both ⇒ `success = true` |
| `mkCore` rejects a hand-built `{ members; archetype; }` attrset — the `class` argument must come from `mkClass` | `gen-class/lib/apply.nix` → `contract.mkCoreRecord`: `error: gen-class: mkCoreRecord: class must be a gen-class/class record`. `mkClass { key = "k"; members = [ "a" "b" ]; }` then works |
| `mkCi`'s input resolution silently **falls back to the hub's pins** for any input the consumer does not declare | `ci/mkCi.nix:27`: `resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name}` — affects `flake-parts`, `import-tree`, `treefmt-nix`, `devshell`, `flake-root`, `git-hooks-nix`, `gen-prelude`. Read, not exercised in this run |
| Two independent lock files: root `flake.lock` and `ci/flake.lock` | 20 vs 19 `gen-*` edges (above). Bumping the root lock does not move what CI checks, and vice versa |
| The hub's CI workflow is **not** the shared sibling workflow — it runs four jobs, and `nix flake check` is not at the sibling line numbers | `.github/workflows/ci.yml` (`cat -n`): `:13` `working-directory: ci`, `:18` `nix fmt -- --ci`, `:27` `nix flake check ./ci`, `:36` `nix run ./ci#perf-bench`, `:46` `nix run ./ci#fleet-consistency`. Only `:27` was executed in this run |

## Theory

The hub claims no result of its own. `README.md:137-149` (§Theoretical Foundations) lists the
ecosystem's grounding as a flat set of areas with representative citations — attribute grammars
(Knuth 1968; Vogt 1989, HOAG; Hedin 2000, RAG; Sloane 2010, Kiama), scope graphs (Neron 2015; van
Antwerpen 2016, Statix; 2018, Scopes as Types), algebraic graphs (Mokhov 2017), intensional functions
(Palmer 2024), record algebra (Leijen 2005; Bracha & Cook 1990), contracts (Findler 2002; Chitil
2012), rule systems (Forgy 1982, RETE; Ehrig 2006; Arntzenius 2016, Datafun).

The per-result mapping lives in `TERMINOLOGY.md:532+` (§Academic References) — a 39-row table pairing
each citation with the specific library and construct that uses it. That table, not this sheet, is
the provenance authority.

`ARCHITECTURE.md:321+` (§Design Constraints) states the ecosystem invariants the hub's wiring
presupposes: an acyclic library DAG, no library importing another's flake inputs, opaque
actions/conditions, a nixpkgs-lib-free library level with nixpkgs entering only at `gen-flake`, and
compose-purely/inject-VALUES-never-TYPES.

## Drift check

```sh
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in { outputs = builtins.attrNames f.outputs; lib = builtins.attrNames f.lib; flakeModules = builtins.attrNames f.flakeModules; roster = builtins.attrNames (f.lib.mkGenLibs { }); }'
```

Current output (verbatim):

```json
{"flakeModules":["genLibs"],"lib":["mkCi","mkGenLibs"],"outputs":["flakeModules","lib"],"roster":["algebra","aspects","bind","class","demand","dispatch","edge","flake","graph","link","merge","pipe","prelude","product","resolve","schema","scope","select","settings","types"]}
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
