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
# `pin-coherence` takes and for the same reason: a cell that fetches 21
# repositories to answer a question about wiring has bought nothing and made the gate non-hermetic.
# What that leaves outside: this cell does not force a member, so it is silent about whether a
# resolved node BUILDS. ONE CELL IS NOT HERMETIC, by spec (den-hoag-idhzc §2.3, tyh4b C4):
# `fetch-locked-is-fetchTree-on-every-reached-node` fetches every reached node both ways, because path
# identity of the fixed-output form is a property only a fetch can read. The planted-lock cells fetch
# nothing: their `src` is a fixture member, or an uncatchable abort where the refusal must come first. The flake path's force is `mkgenlibs-eval`'s, which `deepSeq`s every roster
# member under `nix flake check ./ci` (den-hoag-ydm94 R7 retired the root's own forcing output,
# `roster`, once this check was confirmed to force the same key set more deeply).
#
# ── THE ARMING IS IN THE CELL, AND IT GATES ──
# Three seeded defects are evaluated here on every run, each a DELTA against the live reading printed
# beside it: a member repointed to another member's repository, a member repointed to a node that
# does not exist, and the HUB-SCOPED path form this lock cannot serve. A fourth arm drives the scan
# holding `lock` to the entry's own over seeded TEXT, since no lock mutation reaches it. A guard
# that can no longer fire is not a passing guard, so an arming failure exits 1 even where a reading
# would only print.
{
  gen,
  lib,
  lockedRepo,
}:
let
  # The roster of record, ADR-0015's own file, reached through the published surface rather than by
  # counting anything: the hub's member keys are BARE (`class`), the repositories are `gen-`-prefixed.
  roster = gen.lib.mkGenLibs { };
  rosterKeys = builtins.attrNames (builtins.removeAttrs roster [ "strata" ]);

  # The lock the entry defaults against — the ROOT lock `../default.nix` reads, taken from the record
  # the entry hands `wire` rather than read a second time here. A second read is a second copy that
  # can fall out of step with the entry's: the ci lock beside this file names the same members at
  # other revisions, so a read of it passes every `locked.repo` comparison below while resolving
  # through the TEST graph's pin source (ADR-0037 as amended 2026-09-15). The gate's
  # `entry-lock-is-read-through-the-seam` holds this binding to that one shape.
  lock = seam.lock;

  # THE SEAM READ. `dep = segs: segs` makes each default evaluate to its own path instead of an
  # import; `wire = args: args` hands back the record the body builds. One application yields all
  # three — the map, the entry's own resolver and the lock that resolver runs over.
  seam = import "${gen}" {
    dep = segs: segs;
    wire = args: args;
  };
  paths = seam.deps;
  entryResolve = seam.fetch.resolve;

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
    if n == null then null else lockedRepo l.nodes.${n}.locked;

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
  # an empty roster. `ci/flake.lock` no longer carries a `gen` node either (den-hoag-lbtnv D1: ci
  # reads the root flake at `self`), so no lock in this repository holds the hub-scoped shape; the
  # form stays REJECTED here rather than forgotten — if one ever did, this arm would stop holding.
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

  # ── WHICH LOCK — what `locked.repo` cannot see ──
  # Every reading above compares a repository NAME, and two locks naming one repository at two
  # revisions agree on it, so they cannot tell which lock `lock` read. Measured 2026-09-16
  # (`specs/2026-09-15-gen-pin-source-split-spec.md` §2.2): a member's test left reading the ci lock
  # after its entry moved to the root lock stayed green. There is no independently declared revision
  # to compare against, so the guard is on this FILE'S OWN TEXT: `lock` is bound exactly once, to
  # `seam.lock`. It scans the COMPLEMENT of that one shape rather than the defect's spelling — every
  # binding of `lock` is captured and any other right-hand side is offending, so a path bound a
  # statement earlier, an aliased `readFile` and a read moved into a second file red alike; the
  # leading class keeps `lockWrongRepo =` out, `[^=;]` keeps `lock ==` out, and `seamBound` counts
  # the permitted shape itself, so a binding moved into an `inherit` reds on its absence. Comments
  # are stripped first: the prose above names `lock` and `flake.lock` freely.
  lockBindingNeedle = "(^|[^[:alnum:]_'-])lock[[:space:]]*=([^=;][^;]*);";
  lockBindingsOf =
    text:
    let
      rhss = map (m: builtins.elemAt m 1) (
        builtins.filter builtins.isList (
          builtins.split lockBindingNeedle (
            builtins.concatStringsSep "" (builtins.filter builtins.isString (builtins.split "#[^\n]*" text))
          )
        )
      );
      isSeam = rhs: builtins.match "[[:space:]]*seam[.]lock[[:space:]]*" rhs != null;
    in
    {
      offending = builtins.length (builtins.filter (rhs: !isSeam rhs) rhss);
      seamBound = builtins.length (builtins.filter isSeam rhss);
    };
  lockProvenance = lockBindingsOf (builtins.readFile ./hub-entry.nix);

  # ── THE FIXED-OUTPUT FETCH RULE (tyh4b C1–C4, den-hoag-idhzc §2.3) ──
  # `default.nix`'s `fetch` binding is the one place the entry fetches, and Nix publishes no default, so
  # the reading that `src` takes that rule is textual. COMMENTS ARE STRIPPED, then EVERY whitespace
  # character is deleted, so a formatter's line breaking cannot move the reading. The rule's text is
  # every member shim's, with `gen` as the name in its refusal.
  fetchRule = ''
    fetch = {
      inherit resolve;
      node = resolve lock;
      locked =
        locked:
        if builtins.attrNames locked == [ "lastModified" "narHash" "owner" "repo" "rev" "type" ] && locked.type == "github" then
          builtins.fetchTarball { url = "https://github.com/''${locked.owner}/''${locked.repo}/archive/''${locked.rev}.tar.gz"; sha256 = locked.narHash; }
        else
          throw "gen: a locked node of type `''${toString (locked.type or null)}` with attributes ''${toString (builtins.attrNames locked)} has no fixed-output form here; refusing rather than falling back to fetchTree";
    };
  '';
  # The comment marker, spelled as a JSON escape so that no `#` stands inside a string literal on any
  # line here: a line-wise comment strip cuts at the first `#` and would truncate live code there.
  commentMarker = builtins.fromJSON ''"#"'';
  fetchSrcLine = "src ? segs: fetch.locked lock.nodes.\${fetch.node segs}.locked,";
  countFetch =
    text:
    let
      dense =
        s:
        builtins.replaceStrings [ " " "\n" "\t" ] [ "" "" "" ] (
          builtins.concatStringsSep "\n" (
            map (l: builtins.head (builtins.split commentMarker l)) (
              builtins.filter builtins.isString (builtins.split "\n" s)
            )
          )
        );
      occurrences =
        needle: hay:
        (builtins.stringLength hay - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] hay))
        / builtins.stringLength needle;
      d = dense text;
    in
    {
      fetchTree = occurrences "builtins.fetchTree" d;
      rule = occurrences (dense fetchRule) d;
      src = occurrences (dense fetchSrcLine) d;
      # `fetch` is a record: applying it (`fetch segs`, `fetch [`) is an evaluator error on exactly the
      # inputs the named refusals exist for, so each reads 0 against `fetch.node`'s live reads.
      fetchApplied = occurrences "fetchsegs" d + occurrences "fetch[" d;
      nodeReads = occurrences "fetch.node" d;
    };
  fetchReading = countFetch (builtins.readFile ../default.nix);

  # ONE REAL SIX-KEY `github` NODE, so that in C3's `extraKey` arm the added key is the ONLY difference
  # from an admitted node: a fixture missing `lastModified` lets a rule that ignores the key pass.
  githubNode = {
    lastModified = 0;
    narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    owner = "sini";
    repo = "gen-prelude";
    rev = "0000000000000000000000000000000000000000";
    type = "github";
  };
  refusesFetch =
    locked: !(builtins.tryEval (builtins.deepSeq (seam.fetch.locked locked) true)).success;

  # C4's DOMAIN: every node reached from a roster root input, closed over lock edges (a direct edge is
  # the node key, a `follows` path resolves from the root through the entry's own resolver). This is the
  # hub's one domain difference from the members' C4 (whole lock): `nixpkgs`, a `tarball` node, is an
  # input of the root only, no `src` call reaches it, and `fetch.locked` would refuse it. No `github`
  # conjunct is added: a reached non-`github` node must red here.
  reachedNodes = map (n: n.key) (
    builtins.genericClosure {
      startSet = map (k: { key = entryResolve lock [ "gen-${k}" ]; }) rosterKeys;
      operator =
        n:
        map (v: { key = if builtins.isString v then v else entryResolve lock v; }) (
          builtins.attrValues (lock.nodes.${n.key}.inputs or { })
        );
    }
  );
  nameOf =
    p:
    builtins.head (
      builtins.match "${builtins.storeDir}/[^-]*-(.*)" (builtins.unsafeDiscardStringContext p)
    );
  # BOTH SIDES ARE COPIED by `builtins.path`, each under its own store-path name, never compared as
  # strings: under Determinate's lazy trees either string can be a virtual path that `==` reads unequal
  # to the store path it denotes.
  copied =
    p:
    builtins.path {
      path = p;
      name = nameOf p;
    };
  fetchIdentity = builtins.listToAttrs (
    map (n: {
      name = n;
      value =
        copied (seam.fetch.locked lock.nodes.${n}.locked)
        == copied (builtins.fetchTree lock.nodes.${n}.locked);
    }) reachedNodes
  );

  # ── ONE VALUE PER LOCK NODE: THE PLANTED-LOCK CELLS (den-hoag-idhzc §3a A9, P6) ──
  # The entry's `dep` default closes over `./flake.lock`, so a lock is planted by re-importing THIS
  # REPOSITORY'S OWN `default.nix` under a scope whose `builtins.readFile` answers `flake.lock` with the
  # planted lock: the code under test is the real file, only its data is seeded. The same scope pins
  # `throw` to the one refusal the cell expects: that message throws (and `tryEval` reads it), and any
  # OTHER throw aborts uncatchably with its text, so a refusal naming the wrong set reds loudly rather
  # than passing as "some failure".
  entryOnLock =
    l: expected: args:
    builtins.scopedImport {
      builtins = builtins // {
        readFile =
          p: if baseNameOf (toString p) == "flake.lock" then builtins.toJSON l else builtins.readFile p;
      };
      throw =
        m:
        if builtins.match expected m != null then
          builtins.throw m
        else
          builtins.abort "hub-entry: an unexpected refusal from the planted entry: ${m}";
    } "${gen}/default.nix" args;
  # A member root standing in for every node, so nothing is fetched: it forces each lock edge it is
  # handed, which builds the members those edges reach. A leaf receives `{ }`, a non-leaf all three seams.
  fixtureSrc =
    _:
    builtins.toFile "hub-entry-fixture-member.nix" ''
      { inputs ? { }, src ? null, dep ? null }: builtins.mapAttrs (_: v: builtins.seq v true) inputs
    '';
  # Every member built, every edge it carries forced; `true` iff that evaluation completes.
  buildsOn =
    l: expected: args:
    (builtins.tryEval (builtins.deepSeq (entryOnLock l expected ({ wire = a: a.deps; } // args)) true))
    .success;
  noRefusal = "a refusal no live lock may raise";
  # Cycle plant: one member edge retargeted so that a real evaluation cycle forms (never a leaf-edge
  # plant, which reds with `unexpected argument 'inputs'` whatever the check does). gen-memo builds on
  # gen-graph, so gen-graph's own prelude edge is pointed at gen-memo.
  cycleFrom = "gen-graph";
  cycleTo = "gen-memo";
  fromNode = entryResolve lock [ cycleFrom ];
  cyclePrecondition = builtins.elem [ cycleFrom ] (
    builtins.attrValues (lock.nodes.${entryResolve lock [ cycleTo ]}.inputs or { })
  );
  lockCycle = lock // {
    nodes = lock.nodes // {
      ${fromNode} = lock.nodes.${fromNode} // {
        inputs = lock.nodes.${fromNode}.inputs // {
          gen-prelude = [ cycleTo ];
        };
      };
    };
  };
  # The named set must EQUAL the planted cycle's members: a check that also named their dependents (a
  # one-ended prune) reds here.
  cycleMessage = "gen: the hub lock's member edges form a cycle through ${cycleFrom}, ${cycleTo};.*";
  # `src` aborts uncatchably: the refusal must precede the first fetch, not follow it.
  cycleRefusedBeforeAnyFetch =
    !(buildsOn lockCycle cycleMessage {
      src = _: builtins.abort "hub-entry: a fetch preceded the cycle refusal";
    });
  # Stray plant: a second node for gen-prelude, outside the root's inputs, that gen-graph's edge reaches.
  lockStray = lock // {
    nodes = lock.nodes // {
      gen-prelude_stray = lock.nodes.${entryResolve lock [ "gen-prelude" ]};
      ${fromNode} = lock.nodes.${fromNode} // {
        inputs = lock.nodes.${fromNode}.inputs // {
          gen-prelude = "gen-prelude_stray";
        };
      };
    };
  };
  strayMessage = "gen: `${cycleFrom} → gen-prelude` reaches lock node `gen-prelude_stray`, which is no roster member's root input;.*";
  strayRefused = !(buildsOn lockStray strayMessage { src = fixtureSrc; });
  # The live lock under the same harness builds every member: the two refusals above are the plants'.
  liveBuilds = buildsOn lock noRefusal { src = fixtureSrc; };

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
    # Each way a second read of the lock comes back, and the permitted shape. ASSEMBLED, NOT
    # WRITTEN: every fixture binding is split inside `lock`, so the live scan of this file does not
    # read the fixtures as bindings of its own.
    lockProvenance = builtins.mapAttrs (_: lockBindingsOf) {
      permitted = "  lo" + "ck = seam.lock;\n";
      ciLock = "  lo" + "ck = builtins.fromJSON (builtins.readFile ./flake.lock);\n";
      reflowed =
        "  lo" + "ck =\n    builtins.fromJSON\n      (builtins.readFile\n        ../flake.lock);\n";
      pathBound =
        "  lockPath = ../flake.lock;\n  lo" + "ck = builtins.fromJSON (builtins.readFile lockPath);\n";
      aliased =
        "  readLock = builtins.readFile;\n  lo" + "ck = builtins.fromJSON (readLock ../flake.lock);\n";
      secondFile = "  lo" + "ck = import ./lock-reader.nix;\n";
      inherited = "  inherit (import ./lock-reader.nix) lock;\n";
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

    # The lock every reading above runs over is the entry's own, bound once and through the seam.
    entry-lock-is-read-through-the-seam =
      lockProvenance == {
        offending = 0;
        seamBound = 1;
      };

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

    arming-lock-provenance =
      builtins.mapAttrs (_: r: r.offending) arming.lockProvenance == {
        permitted = 0;
        ciLock = 1;
        reflowed = 1;
        pathBound = 1;
        aliased = 1;
        secondFile = 1;
        inherited = 0;
      }
      && arming.lockProvenance.permitted.seamBound == 1
      && arming.lockProvenance.inherited.seamBound == 0;

    # ── C1–C4: the fixed-output fetch rule ──
    the-fetch-rule-is-the-fixed-output-rule =
      builtins.removeAttrs fetchReading [ "nodeReads" ] == {
        fetchTree = 0;
        rule = 1;
        src = 1;
        fetchApplied = 0;
      }
      && fetchReading.nodeReads >= 5;

    control-the-fetch-rule-check-discriminates =
      builtins.mapAttrs
        (
          _: t:
          builtins.removeAttrs (countFetch t) [
            "fetchApplied"
            "nodeReads"
          ]
        )
        {
          exact = fetchRule + fetchSrcLine;
          planted = ''src ? segs: "''${builtins.fetchTree lock.nodes.''${fetch segs}.locked}",'';
          commented = builtins.concatStringsSep "\n" (
            map (l: commentMarker + " " + l) (
              builtins.filter builtins.isString (builtins.split "\n" (fetchRule + fetchSrcLine))
            )
          );
          urltypo = builtins.replaceStrings [ ".tar.gz" ] [ ".tar" ] fetchRule + fetchSrcLine;
        } == {
        exact = {
          fetchTree = 0;
          rule = 1;
          src = 1;
        };
        planted = {
          fetchTree = 1;
          rule = 0;
          src = 0;
        };
        commented = {
          fetchTree = 0;
          rule = 0;
          src = 0;
        };
        urltypo = {
          fetchTree = 0;
          rule = 0;
          src = 1;
        };
      }
      && (countFetch "lock.nodes.\${fetch segs}.inputs").fetchApplied == 1
      && (countFetch "name = fetch [ n ];").fetchApplied == 1;

    # HERMETIC: each fixture is refused before anything is fetched; a rule blind to a key would try to
    # download the all-zero revision and red on the network.
    fetch-locked-refuses-outside-its-form =
      refusesFetch (
        builtins.removeAttrs githubNode [
          "owner"
          "repo"
        ]
        // {
          type = "git";
          url = "https://github.com/sini/gen-prelude";
        }
      )
      && refusesFetch (
        builtins.removeAttrs githubNode [
          "owner"
          "repo"
        ]
        // {
          type = "tarball";
          url = "https://example.invalid/x.tar.gz";
        }
      )
      && refusesFetch (githubNode // { host = "ghe.example.invalid"; });

    # NOT HERMETIC: it fetches every reached node, both ways. The domain covers every roster node.
    fetch-locked-is-fetchTree-on-every-reached-node =
      builtins.all (n: fetchIdentity.${n}) reachedNodes
      && builtins.all (k: builtins.elem (entryResolve lock [ "gen-${k}" ]) reachedNodes) rosterKeys;

    # ── one value per lock node: the planted-lock refusals, each beside the live control ──
    standalone-entry-refuses-a-member-cycle-by-name =
      cyclePrecondition && cycleRefusedBeforeAnyFetch && liveBuilds;
    standalone-entry-refuses-a-stray-member-node-by-name = strayRefused && liveBuilds;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "the hub's standalone entry (`default.nix`): which roster members it wires, and which repository's node each default resolves to";
    property = "the entry wires EVERY roster member, and each one defaults to a node of its own repository, at the member-scoped path [ <member> ]";
    observable = "the member-to-path record the entry hands `wire`, resolved through the entry's OWN `resolve` binding against the ROOT `flake.lock`, compared on the repository gen-harness `lockedRepo` reads from each node's `locked` (`repo`, or a `git` node's last `url` segment)";
    direction = "HERMETIC and EXACT over wiring, except the fetch-identity cell, which fetches every reached node both ways; SILENT about building a real member. No member is forced, so a member that resolves correctly and then fails to evaluate is invisible here — that force is `mkgenlibs-eval`'s, which deepSeqs every roster member under `nix flake check ./ci`";
    domainSource = "`gen.lib.mkGenLibs { }`'s member keys minus `strata` — ADR-0015's roster of record — intersected with nothing and counted from nowhere else";
    ceiling = "the repository name is neither `owner` nor node/revision identity: a member repointed to a DIFFERENT node of the RIGHT repository passes here. The entry's declared path is the only statement of intent, so there is no independent expectation to compare a node against";

    inherit (live)
      rows
      unresolvable
      misdirected
      notMemberScoped
      memberCount
      resolvedCount
      correctCount
      ;

    inherit arming lockProvenance;
    fetchRule = {
      reading = fetchReading;
      inherit reachedNodes;
      identity = fetchIdentity;
    };
    oneValuePerNode = {
      inherit
        cyclePrecondition
        cycleRefusedBeforeAnyFetch
        strayRefused
        liveBuilds
        ;
    };
  };
}
