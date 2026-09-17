# The hub's standalone (non-flake) entry — L4 of the module-layout pattern. Flake consumers should
# use the `.lib` output; this is what gives a framework built on gen something to `import`, and it is
# the clause that carries flake-optionality TRANSITIVELY (a framework consumed without flakes needs a
# gen consumable without flakes, and until this file existed there was none).
#
# THE HUB IS A CONSUMER OF THE PATTERN, NOT AN EXCEPTION TO IT (owner-ruled 2026-09-14): "`mkGenLibs`
# stops being a fixed point and becomes a CONSUMER of the same pattern every member follows: L3
# applies to the hub." So this file is the L1 shim — three channels, one precedence — over
# `./lib/mkGenLibs.nix`, which is the hub's `lib/` in exactly the sense every member's is. `gen/lib/`
# holds `compose.nix` and `mkGenLibs.nix` and NO `default.nix`, so the wire below names the file.
#
# THREE CHANNELS, ONE PRECEDENCE, AND NONE OF THEM IS A PROBE. A named formal per member wins; the
# `inputs` bag is next, tested by attrset membership so a supplied-but-throwing value throws as
# ITSELF rather than falling back; the default is resolved from `./flake.lock`, read as local data.
# There is NO `...`: an argument this root does not declare is a loud error, not a silent drop.
#
# THE PIN SOURCE IS THE ROOT `flake.lock`, NOT `ci/flake.lock` (ADR-0037 as amended 2026-09-15): a
# library's dependency graph and its test/oracle graph are SEPARATE, and the second must not enter
# the first — "whatever the optimal pattern is, it can no longer be DEFER TO THE TEST LOCK". The ci
# lock keeps every input it has, including both of its cycles, because no library code reads it any
# more; it is the TEST graph's pin source and nothing else.
#
# ★★ THE MEMBERS ARE ROOT INPUTS OF THIS LOCK, AND THE PATHS BELOW SAY SO. `flake.lock` declares all
# 21 roster members directly under its root, so every default is `dep [ "gen-X" ]` — ONE segment,
# entered at the member's own name, which makes this shim structurally identical to every member's.
# `ci/flake.lock` is the lock that declares NO roster member as a root input: all 21 hang under its
# `gen` node, `{ "path": "..", "type": "path" }` with no rev and no narHash. That remains a landed
# decision rather than drift — den-hoag-erls retired the hub's 13 sibling ci pins in favour of that
# self-pin, and the hub's own ci still reaches members through it (`genInputs = inputs.gen.inputs` in
# `ci/flake.nix`, with `ci/direction-of-dependence.nix` and `ci/mkgenlibs-eval.nix` stating the rule
# in terms). erls governs the TEST graph and is untouched here; what moved is which lock THIS file
# reads. Re-adding the 21 members to `ci/flake.nix` is still the REJECTED alternative — it reverses
# erls and gives the hub two independent pin sets for one edge.
#
# `src` AND `dep` ARE FORMALS, NOT `let` BINDINGS, AND THAT IS THE INJECTABLE RESOLVER SEAM. `src` is
# the only expression here that fetches; everything else reads the lock as data. A caller supplying
# `src = segs: throw "…"` therefore makes fetching IMPOSSIBLE for that application rather than merely
# absent. A `dep` bound in the `let` below would close over the `let`'s `src`, so the override would
# silently do nothing and the shim would fetch anyway, at rc 0.
#
# The `let` is OUTSIDE the lambda because a formal's default is evaluated in the FORMAL scope, which
# does not see a `let` in the body.
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  # A direct edge IS the node key; a `follows` value is a PATH resolved segment by segment from this
  # lock's own root. Never by indexing `lock.nodes.<label>` — a last-segment shortcut reads a
  # different node wherever a lock aliases a key. This lock happens to alias none — every roster
  # member is a root input under its own name — but the rule is the resolver's, not this file's, and
  # `ci/hub-entry.nix` drives it on a fixture that does alias. IT TAKES ITS LOCK AS AN ARGUMENT so that a
  # cell can drive this exact binding on a fixture where the two rules disagree by construction; a
  # resolver closed over this repository's own lock could only ever be compared against a second copy
  # of itself. This is the ONE declaration of the rule here — the check reads this binding through
  # the record the body hands `wire`, instead of transcribing the fold a second time.
  resolve =
    lock:
    let
      following =
        node: inp:
        let
          v = (lock.nodes.${node}.inputs or { }).${inp};
        in
        if builtins.isString v then v else builtins.foldl' following lock.root v;
    in
    segs: builtins.foldl' following lock.root segs;
  fetch = resolve lock;
in
{
  inputs ? { },
  src ? segs: "${builtins.fetchTree lock.nodes.${fetch segs}.locked}",
  # `import p { }` is the ONE call text that answers every roster member alike, leaf or not
  # (den-hoag-iev2q): a zero-dependency member's root is a NULLARY FUNCTION and not a bare value, so
  # there is no second shape here to dispatch on. The arity test this replaced carried an `else v`
  # arm nothing in the roster could take, under a comment asserting three leaves that do not exist.
  dep ? segs: import (src segs) { },
  # `wire` IS THE THIRD SEAM, AND IT IS THE ONE CHANNEL BY WHICH THIS FILE PUBLISHES ANYTHING. Nix
  # publishes WHETHER a formal has a default and never WHAT it is, and a formal is an INPUT channel
  # that cannot carry a value outward — so the only place a member NAME and its resolved PATH are
  # both in scope is this file's argument TO `wire`, and `resolve` leaves by that same argument
  # rather than by a fourth formal. `wire` RECEIVES `{ deps, resolve }`, and `./lib/mkGenLibs.nix`
  # sees only whatever `wire` chooses to hand it — here `deps`, but only because the default below
  # reads it that way. A cell injecting `dep = segs: segs` alongside `wire = args: args` reads this
  # shim's own member-to-path map AND its own resolver directly, with nothing fetched, no path
  # restated and no fold transcribed. The record destructures with no `...`, so a drifted body shape
  # is loud at the default.
  wire ? { deps, resolve }: import ./lib/mkGenLibs.nix deps,
  algebra ? inputs.gen-algebra or (dep [ "gen-algebra" ]),
  aspects ? inputs.gen-aspects or (dep [ "gen-aspects" ]),
  assemble ? inputs.gen-assemble or (dep [ "gen-assemble" ]),
  bind ? inputs.gen-bind or (dep [ "gen-bind" ]),
  class ? inputs.gen-class or (dep [ "gen-class" ]),
  delivery ? inputs.gen-delivery or (dep [ "gen-delivery" ]),
  dispatch ? inputs.gen-dispatch or (dep [ "gen-dispatch" ]),
  graph ? inputs.gen-graph or (dep [ "gen-graph" ]),
  identity ? inputs.gen-identity or (dep [ "gen-identity" ]),
  inspect ? inputs.gen-inspect or (dep [ "gen-inspect" ]),
  link ? inputs.gen-link or (dep [ "gen-link" ]),
  memo ? inputs.gen-memo or (dep [ "gen-memo" ]),
  merge ? inputs.gen-merge or (dep [ "gen-merge" ]),
  prelude ? inputs.gen-prelude or (dep [ "gen-prelude" ]),
  product ? inputs.gen-product or (dep [ "gen-product" ]),
  program ? inputs.gen-program or (dep [ "gen-program" ]),
  schema ? inputs.gen-schema or (dep [ "gen-schema" ]),
  scope ? inputs.gen-scope or (dep [ "gen-scope" ]),
  select ? inputs.gen-select or (dep [ "gen-select" ]),
  settings ? inputs.gen-settings or (dep [ "gen-settings" ]),
  types ? inputs.gen-types or (dep [ "gen-types" ]),
  view ? inputs.gen-view or (dep [ "gen-view" ]),
}:
# THE BODY IS EAGER, AND THAT IS WHAT MAKES THE CHECK TOTAL RATHER THAN PARTIAL. `forced` forces
# every wired member to WHNF before `./lib/mkGenLibs.nix` sees it, so a default that cannot resolve
# is loud AT THE BOUNDARY rather than wherever a consumer first reaches an attribute. Without it a
# force of this root reaches only the members the published surface happens to be derived from, and
# `builtins.deepSeq` cannot make up the difference because it does not enter a lambda — which is
# exactly the hazard here, since three members publish a function root under L3's unapplied arm.
#
# THE FORCE STOPS AT WHNF DELIBERATELY: `builtins.seq` of an attrset does not force its members, so
# this reaches each member's root VALUE and never a member of it. A library that deliberately refuses
# to build some member — gen-scope's `buildNodes` tombstone — is therefore not an exception to it.
let
  deps = {
    inherit
      algebra
      aspects
      assemble
      bind
      class
      delivery
      dispatch
      graph
      identity
      inspect
      link
      memo
      merge
      prelude
      product
      program
      schema
      scope
      select
      settings
      types
      view
      ;
  };
  forced = builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) deps) null;
in
builtins.seq forced (wire {
  inherit deps resolve;
})
