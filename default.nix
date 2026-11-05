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
# `ci/flake.lock` declares NO roster member at all, and holds no copy of them: the hub's ci reaches
# them through `gen`, this repository's own root flake read at `self`'s locked identity
# (`builtins.getFlake` in `ci/flake.nix`), so `genInputs = inputs.gen.inputs` resolves through THIS
# lock. That is den-hoag-erls's self-pin carried further, not reversed — erls retired the hub's 13
# sibling ci pins in favour of reaching members through the hub; since den-hoag-lbtnv D1 (Lix refuses
# the `path:..` node that self-pin was) there is ONE pin set for the edge, not a root lock and a ci
# copy of it. `ci/direction-of-dependence.nix` and `ci/mkgenlibs-eval.nix` state the rule in terms.
# Re-adding the 21 members to `ci/flake.nix` is still the REJECTED alternative — it reverses erls and
# gives the hub two independent pin sets for one edge; `ci-declares-no-member` refuses it.
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
  # A `follows` path that cycles through the root (`a` follows `b`, `b` follows `a`) recurses in
  # `following` before any check below can run. It is OUT OF DOMAIN: no evaluator writes such a lock.
  #
  # `fetch` IS THE SHIM'S WHOLE PATH-TO-STORE-PATH CONCERN, AND IT LEAVES THROUGH `wire`'s RECORD:
  # the resolver above, `node` (that resolver on this lock) and `locked` (a node's store path), so the
  # entry cells drive these exact bindings rather than a transcription of them. The rule is the one
  # every member shim carries (ADR-0037: every gen library follows the SAME pattern).
  fetch = {
    inherit resolve;
    node = resolve lock;
    # A locked node's store path through the FIXED-OUTPUT form: upstream Nix returns a valid path without
    # consulting its git tarball cache. `github` only, over its exact key set; anything else refuses by
    # name rather than falling back to `fetchTree`.
    locked =
      locked:
      if
        builtins.attrNames locked == [
          "lastModified"
          "narHash"
          "owner"
          "repo"
          "rev"
          "type"
        ]
        && locked.type == "github"
      then
        builtins.fetchTarball {
          url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
          sha256 = locked.narHash;
        }
      else
        throw "gen: a locked node of type `${toString (locked.type or null)}` with attributes ${toString (builtins.attrNames locked)} has no fixed-output form here; refusing rather than falling back to fetchTree";
  };
in
{
  inputs ? { },
  src ? segs: fetch.locked lock.nodes.${fetch.node segs}.locked,
  # ONE VALUE PER LOCK NODE (den-hoag-idhzc, owner-ruled arm X, 2026-10-20). This lock already states a
  # single resolution: every member edge `follows` a root input. So a member is built with its lock
  # edges answered by the HUB'S OWN values for those nodes — the formals below, so a caller's override
  # of one reaches every member built on it, which is `follows` semantics — and never re-resolves its
  # dependencies from its own lock. A member-relative path is a root path with the member's root input
  # name prefixed, so `fetch.node` answers it with no second resolver.
  #
  # - A LEAF (a node with no lock edges) receives `{ }`: a zero-dependency member's root is a NULLARY
  #   FUNCTION (den-hoag-iev2q). The construction keys on the lock's edges, never on `functionArgs`.
  # - A NON-LEAF receives `inputs`, `src` and `dep`, which every non-leaf shim declares; with all three
  #   supplied, no resolution inside it reads its own lock.
  # - An edge reaching a node that is no roster member's root input is refused by name: answering it
  #   with some root value would be a silent substitution.
  # - The handed `src` refuses a roster member's node by name: importing it would build a second
  #   instance of a member this entry already builds once. Any other node passes to `src`.
  # - THE CYCLE CHECK runs as data over the lock's member edges, before the first build, because a cycle
  #   there (Nix accepts a mutual `follows`) would otherwise read as a bare `infinite recursion`. It
  #   prunes, from both ends, every member with no successor or no predecessor among those left; the
  #   residue is empty iff the edges are acyclic, and with one cycle it is exactly that cycle's members
  #   (with several, it also holds members on a path between two). COST: one pass is O(n²·d) over n
  #   roster members of out-degree at most d, and at most n passes run, so O(n³·d), once per
  #   application of this file, reading only the lock.
  dep ?
    let
      roster = {
        gen-algebra = algebra;
        gen-aspects = aspects;
        gen-assemble = assemble;
        gen-bind = bind;
        gen-class = class;
        gen-delivery = delivery;
        gen-dispatch = dispatch;
        gen-graph = graph;
        gen-identity = identity;
        gen-inspect = inspect;
        gen-link = link;
        gen-memo = memo;
        gen-merge = merge;
        gen-prelude = prelude;
        gen-product = product;
        gen-program = program;
        gen-rules = rules;
        gen-schema = schema;
        gen-scope = scope;
        gen-select = select;
        gen-settings = settings;
        gen-types = types;
        gen-view = view;
      };
      rootInputs = builtins.attrNames lock.nodes.${lock.root}.inputs;
      # lock node ⇒ the root input name that reaches it
      named = builtins.listToAttrs (
        map (n: {
          name = fetch.node [ n ];
          value = n;
        }) rootInputs
      );
      isMember = node: roster ? ${named.${node} or ""};
      at =
        segs:
        let
          node = fetch.node segs;
        in
        if isMember node then
          roster.${named.${node}}
        else
          throw "gen: `${builtins.concatStringsSep " → " segs}` reaches lock node `${node}`, which is no roster member's root input; the standalone entry answers a member's edges only with the hub's own members";
      seams =
        segs:
        let
          edges = lock.nodes.${fetch.node segs}.inputs or { };
        in
        if edges == { } then
          { }
        else
          {
            inputs = builtins.mapAttrs (i: _: at (segs ++ [ i ])) edges;
            src =
              s:
              let
                node = fetch.node (segs ++ s);
              in
              if isMember node then
                throw "gen: `${
                  builtins.concatStringsSep " → " (segs ++ s)
                }` is roster member `${named.${node}}`, which the standalone entry builds once and hands as `inputs`/`dep`; importing it through `src` would build a second instance"
              else
                src (segs ++ s);
            dep = s: at (segs ++ s);
          };
      members = builtins.filter (n: roster ? ${n}) rootInputs;
      succ = builtins.listToAttrs (
        map (n: {
          name = n;
          value = builtins.filter (m: roster ? ${m}) (
            map (
              i:
              named.${
                fetch.node [
                  n
                  i
                ]
              } or ""
            ) (builtins.attrNames (lock.nodes.${fetch.node [ n ]}.inputs or { }))
          );
        }) members
      );
      pred = builtins.listToAttrs (
        map (n: {
          name = n;
          value = builtins.filter (m: builtins.elem n succ.${m}) members;
        }) members
      );
      prune =
        rem:
        let
          inRem = builtins.any (m: builtins.elem m rem);
          keep = builtins.filter (n: inRem succ.${n} && inRem pred.${n}) rem;
        in
        if keep == rem then rem else prune keep;
      cycle = prune members;
      acyclic =
        cycle == [ ]
        || throw "gen: the hub lock's member edges form a cycle through ${builtins.concatStringsSep ", " cycle}; the standalone entry builds each member once from those edges, so a cycle has no construction";
    in
    builtins.seq acyclic (segs: import (src segs) (seams segs)),
  # `wire` IS THE THIRD SEAM, AND IT IS THE ONE CHANNEL BY WHICH THIS FILE PUBLISHES ANYTHING. Nix
  # publishes WHETHER a formal has a default and never WHAT it is, and a formal is an INPUT channel
  # that cannot carry a value outward — so the only place a member NAME and its resolved PATH are
  # both in scope is this file's argument TO `wire`, and `fetch` leaves by that same argument
  # rather than by a fourth formal. `wire` RECEIVES `{ deps, fetch, lock }`, and `./lib/mkGenLibs.nix`
  # sees only whatever `wire` chooses to hand it — here `deps`, but only because the default below
  # reads it that way. A cell injecting `dep = segs: segs` alongside `wire = args: args` reads this
  # shim's own member-to-path map AND its own resolver directly, with nothing fetched, no path
  # restated and no fold transcribed. The record destructures with no `...`, so a drifted body shape
  # is loud at the default.
  wire ?
    {
      deps,
      fetch,
      lock,
    }:
    import ./lib/mkGenLibs.nix deps,
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
  rules ? inputs.gen-rules or (dep [ "gen-rules" ]),
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
      rules
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
  inherit deps fetch lock;
})
