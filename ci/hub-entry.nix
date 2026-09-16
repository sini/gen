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
# does not exist, and the HUB-SCOPED path form this lock cannot serve. A guard that can no longer
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

  # The lock the entry defaults against. `../default.nix` reads `./flake.lock` — the ROOT lock, not
  # this directory's — so from here that is one level up, and it is read as data exactly as the entry
  # reads it. The ci lock beside this file is the TEST graph's own pin source and is no longer what
  # the entry resolves through (ADR-0037 as amended 2026-09-15).
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);

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
        memberScoped = paths.${k} == [ "gen-${k}" ];
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
      notMemberScoped = map (r: r.member) (builtins.filter (r: !r.memberScoped) rows);
    };

  live = readingOn lock;

  # ── THE SEEDS ──
  # A lock is mutated, never the entry: the entry's own `resolve` and the entry's own declared paths
  # are what the seeded readings run on, so an arm that fires is a statement about THIS code.
  controlMember = if builtins.elem "class" rosterKeys then "class" else builtins.head rosterKeys;
  donorMember = if controlMember == "algebra" then "graph" else "algebra";

  # The members are ROOT INPUTS of this lock (ADR-0037's amendment moved the entry's pin source to the
  # root `flake.lock`, where the 21 are declared directly), so the edge a seed mutates hangs off the
  # root node itself rather than one hop down under a `gen` self-pin.
  rootNode = lock.nodes.${lock.root};
  rootInputs = rootNode.inputs;
  seedRoot =
    edge:
    lock
    // {
      nodes = lock.nodes // {
        ${lock.root} = rootNode // {
          inputs = rootInputs // edge;
        };
      };
    };
  # SEED 1 — repoint one member's edge at ANOTHER member's node. Resolvable, real, wrong repository:
  # the class of defect that reads green on any cell asking only "did it resolve".
  lockWrongRepo = seedRoot { "gen-${controlMember}" = rootInputs."gen-${donorMember}"; };
  # SEED 2 — repoint the same member at a node that does not exist.
  lockMissingNode = seedRoot { "gen-${controlMember}" = "gen-node-that-is-not-in-this-lock"; };
  # SEED 3 — THE REJECTED TOPOLOGY, asserted to reach nothing, AND THE LIVE ONE ASSERTED TO REACH
  # EVERYTHING. The rejected form is now the HUB-SCOPED one, `[ "gen" "gen-X" ]`: that is what the
  # entry declared while `ci/flake.lock` was its pin source, where `den-hoag-erls` had retired the
  # hub's 13 sibling ci pins in favour of a `gen` self-pin and no member was a root input. This lock
  # carries no `gen` self-pin at all, so the hub-scoped form reaches 0 of 21 and the member-scoped
  # form reaches 21 of 21. Both halves are asserted: a cell reading only the zero would also pass on
  # an empty roster. erls still governs `ci/flake.lock`, which is why the form is REJECTED here rather
  # than forgotten — if the entry's pin source ever moved back, this arm is what would stop holding.
  # Membership, NEVER a resolution attempt: `following` selects `inputs.<name>` bare, and a missing
  # attribute is an UNCATCHABLE abort that `tryEval` does not convert — so a probe that tried to
  # resolve either form would take the whole evaluation down instead of reading 0.
  rootInputNames = builtins.attrNames rootInputs;
  memberScopedForm = {
    reaches = builtins.length (builtins.filter (k: builtins.elem "gen-${k}" rootInputNames) rosterKeys);
  };
  hubScopedForm = {
    reaches =
      let
        genEdge = rootInputs.gen or null;
        genInputs = if genEdge == null then { } else lock.nodes.${genEdge}.inputs or { };
      in
      builtins.length (builtins.filter (k: builtins.hasAttr "gen-${k}" genInputs) rosterKeys);
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
    pathForm = {
      memberScopedReaches = memberScopedForm.reaches;
      hubScopedReaches = hubScopedForm.reaches;
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

    # The members are root inputs of the lock this entry reads, so each path is ONE segment entered at
    # the member's own name — the shape that makes the hub's shim structurally identical to every
    # member's (ADR-0037 as amended 2026-09-15).
    entry-paths-are-member-scoped = live.notMemberScoped == [ ];

    # ── ARMING — a guard that cannot fire is not a passing guard ──
    arming-wrong-repository =
      arming.seededWrongRepo.named
      && arming.seededWrongRepo.stillResolves
      && arming.seededWrongRepo.carriesDonorRepo
      && arming.seededWrongRepo.correctCount == live.correctCount - 1;

    arming-missing-node =
      arming.seededMissingNode.named && arming.seededMissingNode.resolvedCount == live.resolvedCount - 1;

    arming-hub-scoped-form-reaches-nothing =
      arming.pathForm.hubScopedReaches == 0
      && arming.pathForm.memberScopedReaches == arming.pathForm.ofCount
      && arming.pathForm.ofCount == live.memberCount;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "the hub's standalone entry (`default.nix`): which roster members it wires, and which repository's node each default resolves to";
    property = "the entry wires EVERY roster member, and each one defaults to a node of its own repository, at the member-scoped path [ <member> ]";
    observable = "the member-to-path record the entry hands `wire`, resolved through the entry's OWN `resolve` binding against the ROOT `flake.lock`, compared on `locked.repo`";
    direction = "HERMETIC and EXACT over wiring; SILENT about building. Nothing is fetched and no member is forced, so a member that resolves correctly and then fails to evaluate is invisible here — that force is `mkgenlibs-eval`'s on the flake path and the root `roster` output's under `nix flake check`";
    domainSource = "`gen.lib.mkGenLibs { }`'s member keys minus `strata` — ADR-0015's roster of record — intersected with nothing and counted from nowhere else";
    ceiling = "`locked.repo` is neither `owner` nor node/revision identity: a member repointed to a DIFFERENT node of the RIGHT repository passes here. The entry's declared path is the only statement of intent, so there is no independent expectation to compare a node against";

    inherit (live)
      rows
      unresolvable
      misdirected
      notMemberScoped
      memberCount
      resolvedCount
      correctCount
      ;

    inherit arming;
  };
}
