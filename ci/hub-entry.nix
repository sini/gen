# hub-entry — L4: the hub's standalone (non-flake) entry wires every roster member, and wires each
# one to a node of its OWN repository.
#
# ── WHAT THIS IS FOR ──
# `specs/2026-09-14-gen-module-layout-pattern-spec.md` §2, L4 and §3's O3. Until `../default.nix`
# existed the hub was flake-only, so a framework built on gen could not itself be consumed without
# flakes — which is invariant I2's parenthesis, the transitive half. The entry is what closes it, and
# an entry that silently wires the WRONG member is worse than none: `import` memoises by store path,
# so a mis-pointed default yields a real, resolvable, wrong library rather than an error.
#
# ── HOW IT READS THE ENTRY, AND WHY IT RESTATES NOTHING ──
# `builtins.functionArgs` publishes WHETHER a formal has a default and never WHAT it is, so the only
# place a member NAME and its resolved PATH are both in scope is the entry's own argument to `wire`.
# This cell injects `dep = segs: segs` alongside `wire = args: args` and reads that record straight
# off: the member-to-path map, and the entry's OWN `resolve` binding. Nothing is fetched, no path is
# restated here, and the `follows` fold is not transcribed a second time — a resolver compared
# against a second copy of itself would be `x == x`. Both `expr` and `expected` below range over the
# map the entry actually wires, so the domain is total by construction and never a hand-written list.
#
# ── DIRECTION, STATED SO IT IS NOT DISCOVERED ──
# HERMETIC. The entry's defaults are read as DATA — the paths they declare and the nodes those paths
# resolve to in `flake.lock` — and never forced, so nothing here fetches. That is the same direction
# `lock-agreement` and `pin-coherence` take and for the same reason: a cell that fetches 21
# repositories to answer a question about wiring has bought nothing and made the gate non-hermetic.
# What that leaves outside: this cell does not force a member, so it is silent about whether a
# resolved node BUILDS. The flake path's force is `mkgenlibs-eval`'s, and the hub root's `roster`
# output carries it under `nix flake check`.
#
# ── THE ARMING IS IN THE CELL, AND IT GATES ──
# Three seeded defects are evaluated here on every run, each a DELTA against the live reading printed
# beside it: a member repointed to another member's repository, a member repointed to a node that
# does not exist, and the ROOT-INPUT path form this lock cannot serve. A guard that can no longer
# fire is not a passing guard, so an arming failure exits 1 even where a reading would only print.
{
  gen,
  lib,
}:
let
  # The roster of record, ADR-0015's own file, reached through the published surface rather than by
  # counting anything: the hub's member keys are BARE (`class`), the repositories are `gen-`-prefixed.
  roster = gen.lib.mkGenLibs { };
  rosterKeys = builtins.attrNames (builtins.removeAttrs roster [ "strata" ]);

  # The ci lock the entry defaults against. `../default.nix` reads `./ci/flake.lock`; from here that
  # is this directory's own lock, and it is read as data exactly as the entry reads it.
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);

  # THE SEAM READ. `dep = segs: segs` makes each default evaluate to its own path instead of an
  # import; `wire = args: args` hands back the record the body builds. One application yields both
  # halves — the map and the entry's own resolver.
  seam = import "${gen}" {
    dep = segs: segs;
    wire = args: args;
  };
  paths = seam.deps;
  entryResolve = seam.resolve;

  # Resolution through the ENTRY's binding, against whichever lock is handed in — which is what lets
  # the seeded arms below drive this exact code on a mutated lock.
  nodeOf =
    l: segs:
    let
      r = builtins.tryEval (entryResolve l segs);
    in
    if r.success && builtins.hasAttr r.value l.nodes then r.value else null;
  repoOf =
    l: segs:
    let
      n = nodeOf l segs;
    in
    if n == null then null else l.nodes.${n}.locked.repo or null;

  # A reading over a lock: per member, the path it declares, the node it resolves to and that node's
  # repository, plus the verdict `repo == "gen-" + key`.
  readingOn =
    l:
    let
      keys = builtins.attrNames paths;
      row = k: {
        member = k;
        segs = paths.${k};
        node = nodeOf l paths.${k};
        repo = repoOf l paths.${k};
        expected = "gen-${k}";
        hubScoped =
          paths.${k} == [
            "gen"
            "gen-${k}"
          ];
      };
      rows = map row keys;
      unresolvable = map (r: r.member) (builtins.filter (r: r.node == null) rows);
      misdirected = map (r: r.member) (builtins.filter (r: r.node != null && r.repo != r.expected) rows);
    in
    {
      inherit rows unresolvable misdirected;
      memberCount = builtins.length keys;
      resolvedCount = builtins.length (builtins.filter (r: r.node != null) rows);
      correctCount = builtins.length (builtins.filter (r: r.node != null && r.repo == r.expected) rows);
      notHubScoped = map (r: r.member) (builtins.filter (r: !r.hubScoped) rows);
    };

  live = readingOn lock;

  # ── THE SEEDS ──
  # A lock is mutated, never the entry: the entry's own `resolve` and the entry's own declared paths
  # are what the seeded readings run on, so an arm that fires is a statement about THIS code.
  controlMember = if builtins.elem "class" rosterKeys then "class" else builtins.head rosterKeys;
  donorMember = if controlMember == "algebra" then "graph" else "algebra";

  genNode = lock.nodes.${lock.nodes.${lock.root}.inputs.gen}.inputs;
  # SEED 1 — repoint one member's edge at ANOTHER member's node. Resolvable, real, wrong repository:
  # the class of defect that reads green on any cell asking only "did it resolve".
  lockWrongRepo = lock // {
    nodes = lock.nodes // {
      ${lock.nodes.${lock.root}.inputs.gen} = lock.nodes.${lock.nodes.${lock.root}.inputs.gen} // {
        inputs = genNode // {
          "gen-${controlMember}" = genNode."gen-${donorMember}";
        };
      };
    };
  };
  # SEED 2 — repoint the same member at a node that does not exist.
  lockMissingNode = lock // {
    nodes = lock.nodes // {
      ${lock.nodes.${lock.root}.inputs.gen} = lock.nodes.${lock.nodes.${lock.root}.inputs.gen} // {
        inputs = genNode // {
          "gen-${controlMember}" = "gen-node-that-is-not-in-this-lock";
        };
      };
    };
  };
  # SEED 3 — THE REJECTED TOPOLOGY, asserted to reach nothing. `den-hoag-erls` retired the hub's 13
  # sibling ci pins for the `gen` self-pin, so a member is NOT a root input of this lock and the
  # root-input path form resolves 0 of 21. Held here so that if the topology ever changed under the
  # entry, the arm that rejects this form would stop being about anything.
  # Membership, NEVER a resolution attempt: `following` selects `inputs.<name>` bare, and a missing
  # attribute is an UNCATCHABLE abort that `tryEval` does not convert — so a probe that tried to
  # resolve this form would take the whole evaluation down instead of reading 0.
  rootInputNames = builtins.attrNames lock.nodes.${lock.root}.inputs;
  rootInputForm = {
    reaches = builtins.length (builtins.filter (k: builtins.elem "gen-${k}" rootInputNames) rosterKeys);
  };

  seededWrongRepo = readingOn lockWrongRepo;
  seededMissingNode = readingOn lockMissingNode;

  arming = {
    inherit controlMember donorMember;
    seededWrongRepo = {
      named = builtins.elem controlMember seededWrongRepo.misdirected;
      stillResolves = builtins.elem controlMember (
        map (r: r.member) (builtins.filter (r: r.node != null) seededWrongRepo.rows)
      );
      carriesDonorRepo =
        (builtins.head (builtins.filter (r: r.member == controlMember) seededWrongRepo.rows)).repo
        == "gen-${donorMember}";
      correctCount = seededWrongRepo.correctCount;
    };
    seededMissingNode = {
      named = builtins.elem controlMember seededMissingNode.unresolvable;
      resolvedCount = seededMissingNode.resolvedCount;
    };
    rootInputForm = {
      inherit (rootInputForm) reaches;
      ofCount = builtins.length rosterKeys;
      inherit rootInputNames;
    };
  };

  gate = {
    # Every roster member is wired by the entry, and the denominator is the roster of record rather
    # than a count: an entry that wired three members would fail here, not pass on a smaller domain.
    entry-wires-the-whole-roster =
      builtins.sort (a: b: a < b) (builtins.attrNames paths) == builtins.sort (a: b: a < b) rosterKeys
      && live.memberCount == builtins.length rosterKeys;

    # Every wired member resolves, and resolves to a node of its OWN repository — stated per member
    # with the denominator in the reading.
    entry-defaults-to-each-members-own-node =
      live.unresolvable == [ ] && live.misdirected == [ ] && live.correctCount == live.memberCount;

    # The members hang one hop below this root, under the `gen` self-pin (den-hoag-erls).
    entry-paths-are-hub-scoped = live.notHubScoped == [ ];

    # ── ARMING — a guard that cannot fire is not a passing guard ──
    arming-wrong-repository =
      arming.seededWrongRepo.named
      && arming.seededWrongRepo.stillResolves
      && arming.seededWrongRepo.carriesDonorRepo
      && arming.seededWrongRepo.correctCount == live.correctCount - 1;

    arming-missing-node =
      arming.seededMissingNode.named && arming.seededMissingNode.resolvedCount == live.resolvedCount - 1;

    arming-root-input-form-reaches-nothing =
      arming.rootInputForm.reaches == 0 && arming.rootInputForm.ofCount == live.memberCount;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "the hub's standalone entry (`default.nix`): which roster members it wires, and which repository's node each default resolves to";
    property = "the entry wires EVERY roster member, and each one defaults to a node of its own repository, at the hub-scoped path [ \"gen\" <member> ]";
    observable = "the member-to-path record the entry hands `wire`, resolved through the entry's OWN `resolve` binding against `ci/flake.lock`, compared on `locked.repo`";
    direction = "HERMETIC and EXACT over wiring; SILENT about building. Nothing is fetched and no member is forced, so a member that resolves correctly and then fails to evaluate is invisible here — that force is `mkgenlibs-eval`'s on the flake path and the root `roster` output's under `nix flake check`";
    domainSource = "`gen.lib.mkGenLibs { }`'s member keys minus `strata` — ADR-0015's roster of record — intersected with nothing and counted from nowhere else";
    ceiling = "`locked.repo` is neither `owner` nor node/revision identity: a member repointed to a DIFFERENT node of the RIGHT repository passes here. The entry's declared path is the only statement of intent, so there is no independent expectation to compare a node against";

    inherit (live)
      rows
      unresolvable
      misdirected
      notHubScoped
      memberCount
      resolvedCount
      correctCount
      ;

    inherit arming;
  };
}
