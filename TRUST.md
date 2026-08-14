# gen — Trust

Why the gen ecosystem's claims are checkable, and where each check lives. For what gen is and what it
provides, start at [README.md](README.md).

gen asks you to write modules that a separate evaluator resolves. That is a real transfer of trust,
and it is answered with artifacts rather than assurances: every claim below re-runs from a command,
against a frozen reference, with a described failure mode. This page is the map. The per-proof
inventory is [VALIDATION.md](VALIDATION.md); the measured numbers are [BENCHMARKS.md](BENCHMARKS.md);
the harness rationale and threshold policy are in [`ci/README.md`](ci/README.md).

The ecosystem stands on three proof axes, each with public, CI-enforced artifacts.

## Correctness

[VALIDATION.md](VALIDATION.md) is the full inventory: every claim paired with the command that
re-runs it and the way it fails.

The load-bearing proof is the **byte-parity oracle** `rehost-den-parity` (`nix flake check ./ci`). It
holds the pure stack — gen-prelude → gen-types → gen-merge → the re-hosted gen-schema — byte-identical
to the frozen nixpkgs stack it replaced, down to the `id_hash` SHA, by running den's actual registry
shape through both stacks. It carries **mutation teeth**: a perturbed host `addr` must change the
`id_hash`, so "identical" cannot hold vacuously through a shared throw — without teeth, two stacks
failing the same way would read as agreement. The reference side is pinned at the last pre-re-host
revision and driven through a pinned `github:nix-community/nixpkgs.lib`. Design detail:
[`ci/README.md`](ci/README.md).

A frozen reference keeps the **bar** from drifting, but it cannot follow a **subject** that moves by
design ruling — and the aspect grammar does. So the sibling oracle over that grammar
(`rehost-byte-parity`, retired 2026-08-13) is **not** replaced by a re-pinned equivalent, and one
promise is presently **enforced by no gate**: **module system compatibility** — *whole-stack agreement
with nixpkgs across the aspect grammar*, the property anyone migrating from nixpkgs modules relies on.
★ **The promise stands; what lapsed is its continuous enforcement.** Owner ruling, 2026-08-13: the
promises the oracle held stand and *"don't need to hold at every gate"*, and the oracle is rebuilt
during the final rounds *"so we can make the same guarantees"* — the same ones, re-established rather
than renegotiated. It is recorded, with an empty command cell, in [VALIDATION.md](VALIDATION.md) §1;
its named carrier is `den-hoag-gkkh`, under ADR-0025 item 2, whose contract makes the reference a
parameter rather than a frozen input so a ruled grammar change registers as a named divergence instead
of a red.

Underneath sit the per-library nix-unit suites — the [gen-merge](https://github.com/sini/gen-merge)
byte-mode engine's 206 tests (at `9f20fb1`) and the [gen-flake](https://github.com/sini/gen-flake)
terminal's 98 (at `f6295f4`), measured by running the suites rather than quoted; the revision is the
anchor, so a reader checks out that exact rev and reproduces the count. VALIDATION §2 carries the whole
table with a revision per library. Alongside them sit the config-thunk deferral regression (den's
`__configThunk` markers ride the engine unforced and resolve byte-identically at the terminal) and
three migrated demos (gen-schema / gen-aspects / gen-vars) that byte-check whole small consumers across
engine bumps.

### The purity scanners

Each library repo carries `ci/tests/purity.nix` (gen-types names it `ci/tests/types-purity.nix`). The
test reads every `lib/**.nix` plus the root `flake.nix` / `default.nix`, strips comments, and asserts
zero occurrences of the nixpkgs tether tokens. `ci/` itself is out of scope — the test harness and the
oracle's reference side legitimately use `nixpkgs.lib`.

The token list is per library rather than uniform, because a library's own API names must stay legal:

- **The pure siblings** — gen-algebra, gen-bind, gen-dispatch, gen-graph, gen-link, gen-rebuild,
  gen-resolve, gen-scope, gen-select, gen-types — ban `lib.` outright, along with `nixpkgs`, the
  `{ lib }` / `{ lib,` parameter signatures, `evalModules` and `mkOption`. No `lib.` call of any kind
  survives there.
- **The module-system libraries** — gen-aspects, gen-class, gen-edge, gen-merge, gen-pipe, gen-product,
  gen-schema, gen-settings — export their own `mkOption` / `mkMerge`, so a bare-token ban would reject
  their own surface. They enumerate the nixpkgs forms instead — `lib.types`, `lib.mkOption`,
  `lib.evalModules`, `evalModules`, `nixpkgs` and the `{ lib }` / `{ lib,` signatures, with
  `lib.mkMerge` and `lib.mkForce` added where the library has cause to.
- **gen-flake** tiers it. The module-system *call* tether is forbidden in every library file, wiring
  included. The nixpkgs *import* tether is additionally forbidden in the strict pure core. Exactly one
  file, `lib/terminals.nix`, is excluded as the sanctioned boundary, and the classifier treats any file
  it does not recognise as strict — so a new pure file is guarded by default and the boundary cannot
  widen by accident.

One roster library carries no scanner. **gen-prelude** needs none: it declares no flake inputs, so
nothing transitive can enter its lock and the flake structure is itself the proof. **gen-vars** is the
documented exception: it is deliberately `nixpkgs.lib`-tethered outside its bottom `pure/` tier, is not
part of the pure plane, and is off-roster. **gen-demand** left the roster with its scanner still
outstanding and will not gain one — its `lib/` was nixpkgs-lib-free by inspection and by its input list
(gen-prelude, gen-graph), but no check ever held that. The content that moved is covered: gen-scope's
scanner enumerates `lib/` with `builtins.readDir`, so the cascade modules came under it on arrival
without an edit to the scanner. ★ **That enumeration is one directory level — `lib/*.nix`, not
`lib/**.nix`** — so its totality is a property of `lib/` being flat (15 files today), not of the
scanner. A module added at `lib/sub/x.nix` would leave the scan silently, which is the failure mode
this section exists to rule out; a recursive walk is the by-construction answer and is gen-scope's
own work to spec.

gen-types additionally ships a teeth test, `test-detector-catches-injected-violation`, proving the
scanner actually fires on an injected violation rather than passing because it matches nothing.

## Performance

[BENCHMARKS.md](BENCHMARKS.md) reports evaluation-time cost against that same frozen nixpkgs stack,
**byte-parity-gated first** — a fast-but-wrong change cannot pass, whatever its timings say.

`nix run ./ci#perf-bench` measures every cell, then evaluates three gate families: parity (every cell's
digest matches across stacks), ratio (the pure stack stays faster and lighter at the largest workload),
and linearity (counters grow no worse than linearly across a ×4 size step — the net that caught an
O(k²) key-union bug). Every failing gate appends to a failure list and the run exits non-zero *after*
the full report is emitted, so a failing run still records everything it measured and you see all
breaches at once rather than only the first.

Two dedicated workloads run their own byte-and-reuse gates: `classShare`
([gen-class](https://github.com/sini/gen-class)'s tier-2 fixed-input path) and `overrideWarm`
(gen-merge's warm re-eval). Each must build ≤ 0.30× the full path's thunk graph, byte-identically. The
exact thresholds are retuned in lockstep with engine changes and kept in one place —
[BENCHMARKS.md](BENCHMARKS.md) for the numbers, [`ci/README.md`](ci/README.md) for the update policy.

The
[3-way comparison](BENCHMARKS.md#3-way-real-flake-comparison--gen-flake-vs-flake-parts-vs-adios-flake)
puts [gen-flake](https://github.com/sini/gen-flake) head-to-head with flake-parts and adios-flake under
a drvPath-equivalence oracle (`nix run ./ci#flake-compare`, 15/15 byte-identical). Fleet-scale dedup
numbers are measured in a separate lab ([hola](https://github.com/sini/hola)) and frozen as gates; this
hub carries the arithmetic tooth over the committed baselines. `nix run ./ci#fleet-consistency`
re-derives each cited number from those baselines — pin agreement, saving arithmetic, digest ties, and
two floors — in seconds, with no fleet eval. Its `--selftest` mode corrupts a *copy* of a baseline (a
counter, then a floor) and asserts each corruption fails, so the roster is proven to have teeth without
touching the committed files.

## Observability

The surface nixpkgs `evalModules` cannot offer. [gen-flake](https://github.com/sini/gen-flake) v1
exposes provenance (which module set each option, at what priority), a diff between two composes, and a
memoization decision trace — powered by [gen-merge](https://github.com/sini/gen-merge)'s always-on
provenance channel and its warm re-eval, with [gen-class](https://github.com/sini/gen-class) carrying
the class-share mechanism den-hoag consumes.

Every one of these surfaces is asserted in tests (VALIDATION §2), including the tooth that the
provenance channel forces only its own records and never the config values, and the adversarial
lying-marker test proving a data module that falsely claims purity is caught at the byte oracle rather
than silently corrupting output. The channel's engine cost is measured rather than assumed — the
BENCHMARKS engine-cost note reports it at +3.7–6.3% pure-side thunks, a channel paid for once up front
rather than per item.

## Re-running it

From this hub's root:

```bash
nix flake check ./ci           # the two byte-parity oracles + treefmt
nix run ./ci#perf-bench        # parity + ratio + linearity gates
nix run ./ci#flake-compare     # 3-way drvPath equivalence (15/15)
nix run ./ci#fleet-consistency # cited fleet numbers vs their own arithmetic
```

Per library — clone the repo and, from its root, `nix flake check ./ci` for the gate or
`nix develop ./ci -c nix-unit --flake ./ci#tests` for the count. A single sub-proof runs directly, e.g.
`nix develop ./ci -c nix-unit --flake ./ci#tests.purity`. The full library set with revisions and test
counts is [VALIDATION §2](VALIDATION.md#2-per-library-unit-suites).
