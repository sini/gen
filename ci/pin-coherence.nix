# pin-coherence — L7: roster-wide pin coherence across the 21 members' `ci/flake.lock` files.
#
# ── WHAT THIS IS FOR, AND WHY IT IS A CLAUSE AND NOT HOUSEKEEPING ──
# `specs/2026-09-14-gen-module-layout-pattern-spec.md` §2, L7. Under L1 a library's `default.nix`
# defaults each dependency out of its OWN `ci/flake.lock`, so a flakeless construction of one
# library resolves each shared dependency once per pinning member. `import` memoises by STORE PATH:
# coherent pins collapse that split to one value with no further mechanism, and incoherent pins
# re-open it silently the moment one library lands. The hub is the only place that sees all 21 ci
# locks — it does not already hold the answer, it holds the only lever.
#
# ── THE SUBJECT IS THE MEMBERS' CI LOCKS, NOT THE HUB'S OWN TWO ──
# `ci/lock-agreement.nix` (den-hoag-0moiy) is the hub's own root-vs-ci predicate and this check sits
# BESIDE it, never over it: that one compares two locks of ONE repository at the hub's direct edges,
# this one compares ONE edge class across TWENTY-ONE repositories. Neither subsumes the other.
#
# ── THE TWO READINGS, AND WHY THEY ARE SEPARATE KEYS ──
# (1) CROSS-MEMBER coherence — for each shared node, all members pinning it name ONE revision. This
#     is the property that makes `import` memoise, and it is satisfiable: `gen-harness` reads 21
#     sites at 1 revision today, live, in the domain.
# (2) HUB-ROOT agreement — every member pin equals the hub ROOT lock's `follows`-resolved revision
#     for that node. The spec names this as L7's reference and the bump's target.
#
# ★★★ (2) IS NOT SATISFIABLE WHILE THE MEMBER→MEMBER CI EDGE GRAPH HOLDS A CYCLE, AND IT DOES.
# The hub root pins member M at a COMMIT of M. For member N's ci lock to name that commit, N must be
# relocked after it — which makes a new commit of N, which M's ci lock must then name. Measured at
# gen `bd57c06`: `gen-merge/ci/flake.nix` declares `gen-memo.url` and `gen-memo/ci/flake.nix`
# declares `gen-merge.url`, both deliberately (each file says why), so `content(r_merge)` would have
# to contain `r_memo = H(content(r_memo))` and `content(r_memo)` contain `r_merge = H(content(r_merge))`.
# 14 of the 21 members sit in that cyclic component; the 7 outside it (gen-identity, gen-algebra,
# gen-prelude, gen-bind, gen-graph, gen-product, gen-types) are orderable and CAN reach it.
# ★★ And the live control says the same thing from the other side: `gen-harness` is the one node
# that IS roster-wide coherent, its 21 pins name `d56dece7`, and `gen-harness`'s own HEAD is
# `b12b5e3b` — the ecosystem's only instance of the property is coherent WITH ITSELF and not with any
# HEAD. `gen-harness` is also not a hub root input at all, so under reading (2) the only live
# positive control is out of domain.
# ⇒ BOTH readings are COMPUTED and PRINTED; neither GATES, pending the owner's disposition. That is
# `mkLockAgreementCheck`'s shipped arm verbatim (`ci/flake.nix`, `gating`) and for the same reason:
# the predicate, the domain, the traversal and the message are identical under either disposition and
# only the exit status differs. Everything BELOW the readings — the domain floor, the live control,
# the arming and the refusals — gates under both arms, because a guard that can no longer fire is not
# a passing guard in either.
#
# ── THE DOMAIN IS THE ROSTER OF RECORD, MAPPED INTO THE INPUT NAMESPACE ──
# ADR-0015: `mkGenLibs` is the roster of record. The member keys are BARE (`prelude`, not
# `gen-prelude`), so the `"gen-" + k` map is load-bearing and not a formality — the domain written as
# "the `gen-`-prefixed members of `mkGenLibs { }`" is THE EMPTY SET, and an empty domain reads
# `coherent = true` over zero nodes. `domain-from-roster` is the arm that refuses it.
#
# ★ THE NODES ARE NOT THE DOMAIN. The members are what this check ENUMERATES; the shared nodes are
# what it FINDS in their locks. `gen-harness`, `gen-differential` and `gen-scope-unmet` appear as
# pinned nodes and are on no roster — subtracting them would delete the one live positive control.
#
# ── ★★★ A `path:` PIN SITE IS OUTSIDE THE RELATION, BY TYPE — AND THE PLANE DECIDES ITS VERDICT ──
# The subject of this check is: do members AGREE on which REVISION of a node they pin. A `path:`
# input NAMES A TREE, NOT A PUBLICATION, so it carries no `rev` — there is nothing for it to agree or
# disagree ABOUT. It is not a participant whose revision happens to be null; it is not a participant.
# A `path:` site is therefore dropped from the relation BY ITS NODE TYPE, and NAMED in `pathExcluded`
# so the site count is never quietly short.
#
# ★★★ OWNER-RULED 2026-09-18: "the path is valid for self-ref at ci/ only, never at the root."
# So the type alone does not settle the verdict — THE PLANE DOES, and this cell reads both:
#   `ci/` lock  + `path:` node  ⇒ LEGITIMATE. Outside the coherence relation; it names the tree under
#                                 test, which is what makes the self-input invariant testable.
#   ROOT lock   + `path:` node  ⇒ A VIOLATION, NAMED. A published library's root is the plane
#                                 consumers actually resolve through, and it must name a REVISION.
#   either lock + revless NON-path node ⇒ REFUSED, unchanged. The genuine broken-instrument case.
# `rootPlaneOf` is the second reading and `root-plane-refuses-path` the arm. The corpus already
# honours the rule — 53 `gen-*` root edges over 19 members, all `github`, measured 2026-09-18 — and a
# rule the corpus happens to satisfy is exactly the kind that rots silently, so it ships ARMED.
#
# ★★ THIS IS NOT THE NARROWING `mkPinCoherenceCheck` FORBIDS — AND THE PLANE PARTITION IS ITS
# OPPOSITE. That message reads, verbatim:
#     "Disposed of by converging the members' ci locks onto ONE revision per node — NEVER by
#      narrowing this cell's domain, and NEVER by removing a member's flake input
#      (den-hoag-mehb8 fences that)."
# Partitioning by PLANE shrinks nothing: the relation keeps every node it could ever have judged, and
# the cell GAINS a case it previously could not express at all, because it read no member's own root
# lock. The domain grew by one plane. The `ci/`-side exclusion below is the only subtraction, and it
# forbids excluding a MEMBER, or a node, TO HIDE A REAL DISAGREEMENT ABOUT A REAL REVISION. The
# exclusion here removes only sites that CANNOT CARRY A REVISION AT ALL, so it cannot remove a
# revision from any comparison: every non-path site is compared exactly as before, and two members
# naming two revisions of one repository are still named however either of them reaches it. A `path:`
# pin has no revision to hide behind. Reading the prohibition to cover this type would make the check
# unable to coexist with the self-input invariant (den-hoag-c0wc1) that `gen-inspect` and `gen-memo`
# hold by following their own node onto the tree under test — which is what makes THAT invariant
# testable, is CI-green in both members, and is not this check's to undo.
#
# ★ AND THE BROKEN-INSTRUMENT CASE SURVIVES INTACT. A node with NO `locked.rev` that is NOT a path —
# a tarball, a `file:`, a node this walk failed to resolve — still REFUSES by name, because there
# `null == null` reading as agreement is exactly the rubber stamp REFUSAL 3 exists to prevent. The
# two cases are separated by `locked.type` and by nothing else, and both ship armed: `seededUnlocked`
# seeds a revless NON-path node and must be REFUSED, `seededPathNode` seeds a path node and must be
# EXCLUDED — refused and excluded are different lists, asserted against each other.
{
  gen,
  lib,
}:
let
  roster = gen.lib.mkGenLibs { };

  # `strata` is an attribute of the roster and not a member of it — the same meta-key filter
  # `ci/lock-agreement.nix` and `ci/sole-evaluator.nix` apply, for the same reason.
  rosterMetaKeys = [ "strata" ];
  rosterKeys = builtins.filter (k: !(builtins.elem k rosterMetaKeys)) (builtins.attrNames roster);

  sorted = builtins.sort (a: b: a < b);
  unique = xs: builtins.attrNames (builtins.listToAttrs (map (x: lib.nameValuePair x null) xs));

  # ★★ THE MAP — see the header. Omitting it makes this the empty set.
  memberNames = sorted (map (k: "gen-" + k) rosterKeys);

  # ── REACHING THE MEMBER TREES ──
  # `gen.inputs.<name>.outPath`, which is `ci/sole-evaluator.nix`'s route to the same 21 trees. Each
  # is the member AT THE REVISION THIS HUB PINS, which is the revision a consumer of the hub gets —
  # so the reading is about the published ecosystem and not about anybody's working tree.
  lockPathOf = n: "${gen.inputs.${n}.outPath}/ci/flake.lock";
  readLock = p: builtins.fromJSON (builtins.readFile p);
  liveLocks = builtins.listToAttrs (
    map (
      n:
      lib.nameValuePair n (if builtins.pathExists (lockPathOf n) then readLock (lockPathOf n) else null)
    ) memberNames
  );

  # ── THE ROOT PLANE, a SECOND reading over the SAME trees ──
  # Owner-ruled 2026-09-18: "the path is valid for self-ref at ci/ only, never at the root." The two
  # planes are not the same object and this cell now reads both — the ci lock beside it, each
  # member's own ROOT lock here, one path component away on the tree this hub already pins. This is
  # the ONLY reader in this file of a member's own root lock; `hubRootLock` below is the HUB's, used
  # as reading (2)'s reference value and never enumerated per-member.
  rootLockPathOf = n: "${gen.inputs.${n}.outPath}/flake.lock";
  liveRootLocks = builtins.listToAttrs (
    map (
      n:
      lib.nameValuePair n (
        if builtins.pathExists (rootLockPathOf n) then readLock (rootLockPathOf n) else null
      )
    ) memberNames
  );

  hubRootLock = readLock ../flake.lock;

  # ── THE TRAVERSAL ──
  # `ci/lock-agreement.nix`'s `following` rule, one dimension over. A direct edge IS the node key; a
  # `follows` value is a PATH LIST resolved segment by segment from that lock's own root.
  #
  # ★ `lock.nodes.<label>` IS NEVER INDEXED BY NAME. A lock routinely carries `X` and `X_2` for one
  # library at DIFFERENT revisions and the bare index returns whichever was minted first, at exit 0.
  # gen-assemble's own ci lock holds 10 `gen-prelude` nodes at 3 revisions (spec §3, O1).
  #
  # ★ THE `follows` LIMB IS DEAD IN PRODUCTION AND SHIPS ARMED. Measured at gen `bd57c06`: all 80
  # member root `gen-*` edges are direct, 0 follows-shaped. One member declaring `gen-x.follows` on
  # another of its own root inputs puts an edge in the limb, and a limb that failed silently would
  # read the pin as absent rather than as itself. `follows-resolved` fires on a seeded one.
  inputsOf =
    lock: node:
    if lock.nodes ? ${node} && lock.nodes.${node} ? inputs then lock.nodes.${node}.inputs else { };
  following =
    lock: node: inp:
    let
      v = (inputsOf lock node).${inp} or null;
    in
    if v == null then
      null
    else if builtins.isString v then
      v
    else
      builtins.foldl' (cur: seg: if cur == null then null else following lock cur seg) lock.root v;

  # The PRE-LIMB reader over the same objects, so `follows-resolved`'s control arm runs the SAME
  # comparator with the limb stripped rather than a second implementation of it.
  directOnly =
    lock: node: inp:
    let
      v = (inputsOf lock node).${inp} or null;
    in
    if v == null || !(builtins.isString v) then null else v;

  revIn =
    lock: key:
    if key != null && lock.nodes ? ${key} then lock.nodes.${key}.locked.rev or null else null;
  # The NODE TYPE beside the revision, read off the same resolved key. This is the only field that
  # separates "names a tree, so it has no revision to agree about" from "should name a revision and
  # does not" — see the header. An unresolvable key reads `null`, which is NOT `"path"`, so an edge
  # this walk could not follow falls to the refusal and never to the exclusion.
  typeIn =
    lock: key:
    if key != null && lock.nodes ? ${key} then lock.nodes.${key}.locked.type or null else null;
  genEdgesOf =
    lock:
    sorted (builtins.filter (lib.hasPrefix "gen-") (builtins.attrNames (inputsOf lock lock.root)));

  # ── THE ROOT-PLANE READING ──
  # Owner-ruled 2026-09-18: a `path:` self-reference is legitimate at `ci/` and a VIOLATION at the
  # root. The ci plane's path sites leave the coherence relation (header); a root plane's path site
  # is NAMED, because a published library's root is the plane consumers actually resolve through and
  # it must name a REVISION. Same edge class as the coherence walk, same `follows` resolver, same
  # type reader — so this is one more reading of the objects already open, not a second instrument.
  #
  # ★ THREE OUTCOMES, AND THE THIRD IS NOT A FAILURE. A member whose root flake declares NO inputs
  # has NO root `flake.lock` AT ALL, by construction — measured 2026-09-18: `gen-algebra`,
  # `gen-identity` and `gen-prelude`, the three zero-dependency leaves, corroborated from their
  # clones' `origin/main` by `git cat-file -e`. That is a fact about the member, like REFUSAL 2, and
  # it is NAMED in `lockAbsent` rather than counted as a violation or as a clean read. Folding it
  # into either one would be wrong in opposite directions.
  #
  # ★★ PARAMETERISED ON THE LOCK SET so a seeded root world runs THIS code. The live reading is
  # `pathSites == [ ]` today — 53 `gen-*` root edges over the 19 members that have a root lock, type
  # histogram `{ github = 53; }` — and a green from a walk that reached nothing would look identical,
  # which is why `root-plane-refuses-path` asserts the edge count and the member partition too.
  rootPlaneOf =
    domain: resolve: rootLocks:
    let
      lockAbsent = sorted (builtins.filter (m: rootLocks.${m} or null == null) domain);
      present = builtins.filter (m: !(builtins.elem m lockAbsent)) domain;

      # ★★ AN INDEPENDENT COUNT OF THE SAME QUANTITY, and the arm asserts the two AGREE. `present` is
      # derived from `lockAbsent`; this is derived from the LOCKS. The arithmetic floor alone cannot
      # separate "absent" from "read but contributed no edges" — measured 2026-09-18: seeding
      # `lockAbsent = [ ]` leaves `readCount + 0 == 22` balanced and the floor passes, while three
      # members that have NO root lock are being counted as read. Two derivations of one number
      # disagree there; one derivation cannot.
      readableCount = builtins.length (builtins.filter (m: rootLocks.${m} or null != null) domain);
      # ★ TOTAL ON A MISSING LOCK, and that is a refusal rather than a convenience — `fieldIn` below
      # meets the same problem and answers it the same way. If `lockAbsent` ever stopped partitioning
      # the domain correctly, a `null` lock would reach `genEdgesOf` and abort the WHOLE cell with
      # `expected a set but found null` from inside `derivationStrict` — indistinguishable from a typo
      # in this file, and printing none of the named arming refusals the builder exists to emit.
      # Driven 2026-09-18: with this guard absent, seeding `lockAbsent = [ ]` took the cell to rc 1 by
      # ABORT; with it, the same seed leaves the walk short and `root-plane-refuses-path` says so.
      edgesOf =
        m:
        let
          lock = rootLocks.${m} or null;
        in
        if lock == null then
          [ ]
        else
          map (e: {
            member = m;
            edge = e;
            type = typeIn lock (resolve lock lock.root e);
          }) (genEdgesOf lock);
      edges = builtins.concatMap edgesOf present;
      pathEdges = builtins.filter (e: e.type == "path") edges;
    in
    {
      inherit lockAbsent readableCount;
      readCount = builtins.length present;
      edgeCount = builtins.length edges;
      pathSites = sorted (map (e: "${e.member} → ${e.edge}") pathEdges);
      pathMembers = sorted (unique (map (e: e.member) pathEdges));
      absentNamed = map (
        m:
        "${m}: declares no root inputs, so it has no root `flake.lock` — no root-plane reading, and that is not a violation"
      ) lockAbsent;
      violations = map (
        e:
        "${e.member}: its ROOT `flake.lock` resolves `${e.edge}` by `path:` — a published library's root must name a REVISION. `path:` self-reference is ruled legitimate at `ci/` ONLY (owner, 2026-09-18)"
      ) pathEdges;
    };

  # ── THE COMPARATOR ──
  # Parameterised on the DOMAIN, the RESOLVER, the member LOCK VALUES and the hub lock, so every
  # seeded world below runs THIS code and not a copy of it. A second implementation would arm nothing.
  coherenceOf =
    domain: resolve: locks: hubLock:
    let
      # REFUSAL 1 — a member whose `ci/flake.lock` could not be read. A member the walk cannot open
      # contributes no pin, and a walk that reaches nothing reads as a held invariant.
      unreadable = sorted (builtins.filter (m: locks.${m} or null == null) domain);
      readable = builtins.filter (m: !(builtins.elem m unreadable)) domain;

      # REFUSAL 2 — a member whose ci lock declares no `gen-*` root input. Under L1 that member's
      # shim has no dependency to default, so it is a fact about the member and not about the pins;
      # it is NAMED so the site count is never quietly short.
      noGenEdges = sorted (builtins.filter (m: genEdgesOf locks.${m} == [ ]) readable);

      pinsOfMember =
        m:
        let
          lock = locks.${m};
        in
        map (
          n:
          let
            key = resolve lock lock.root n;
          in
          {
            node = n;
            member = m;
            rev = revIn lock key;
            type = typeIn lock key;
          }
        ) (genEdgesOf lock);

      # EXCLUSION — a `path:` site names a TREE and carries no revision, so it is not a participant
      # in a relation ABOUT revisions (header). Dropped BY TYPE and NAMED, never by member and never
      # by "has no rev" — that second spelling would swallow REFUSAL 3 below whole.
      #
      # ★ THE EXCLUDED SET AND THE COMPARED SET ARE ONE PREDICATE, COMPLEMENTED — never two filters
      # written to agree. Two independent spellings can drift into leaving a site in BOTH lists or in
      # NEITHER, and a site in neither is one this check silently stopped ranging over: `siteCount`
      # would simply be short and nothing would say so. Complementing one predicate makes the
      # partition hold by construction, and makes a red drive on it move both sides together.
      allPins = builtins.concatMap pinsOfMember readable;
      isPathPin = p: p.type == "path";

      pathPins = builtins.filter isPathPin allPins;
      pathExcluded = sorted (unique (map (p: p.node) pathPins));
      pathSites = sorted (map (p: "${p.member} → ${p.node}") pathPins);

      pins = builtins.filter (p: !(isPathPin p)) allPins;
      nodes = sorted (unique (map (p: p.node) pins));
      sitesOf = n: builtins.filter (p: p.node == n) pins;

      hubRef = n: revIn hubLock (resolve hubLock hubLock.root n);

      rowOf =
        n:
        let
          ss = sitesOf n;
          revs = sorted (unique (map (p: if p.rev == null then "<unlocked>" else p.rev) ss));
          ref = hubRef n;
        in
        {
          node = n;
          sites = builtins.length ss;
          distinct = builtins.length revs;
          hubRoot = if ref == null then "<no-hub-edge>" else ref;
          pins = map (r: {
            rev = r;
            members = sorted (
              map (p: p.member) (builtins.filter (p: (if p.rev == null then "<unlocked>" else p.rev) == r) ss)
            );
          }) revs;
        };
      rows = map rowOf nodes;

      rowsBy = f: sorted (map (r: r.node) (builtins.filter f rows));

      # REFUSAL 3 — `locked.rev` equality is NOT total. A node that SHOULD name a revision and does
      # not — a tarball, a `file:`, an edge this walk could not resolve — carries no `rev`, and
      # `null == null` would read as AGREEMENT. It is a named refusal, never a coherence.
      # ★ `pins` is already path-free, so this reads the GENUINE broken-instrument case only: a
      # `path:` site is excluded above, by type, because it names a tree and has no revision to
      # agree about. Widening this back to "has no rev" would re-swallow the exclusion.
      unlocked = sorted (unique (map (p: p.node) (builtins.filter (p: p.rev == null) pins)));

      incoherent = rowsBy (r: r.distinct > 1);
      singlePinned = rowsBy (r: r.sites == 1);
      canDisagree = rowsBy (r: r.sites > 1);
      noHubReference = rowsBy (r: r.hubRoot == "<no-hub-edge>");

      divergentSites = builtins.filter (
        p:
        let
          ref = hubRef p.node;
        in
        ref != null && p.rev != null && p.rev != ref
      ) pins;
      agreeingSites = builtins.filter (
        p:
        let
          ref = hubRef p.node;
        in
        ref != null && p.rev != null && p.rev == ref
      ) pins;

      refusals =
        map (
          m: "${m}: ci/flake.lock could not be read at this hub's pin — this check contributes no pin for it"
        ) unreadable
        ++ map (m: "${m}: its ci/flake.lock declares no `gen-*` root input") noGenEdges
        ++ map (
          n:
          "${n}: pinned without a `locked.rev` by some member — a null revision reads as agreement and must not"
        ) unlocked;

      # STATED, and deliberately NOT a refusal: these sites are out of the relation's domain, not
      # unreachable within it. They print so the site count is never quietly short.
      exclusions = map (
        s:
        "${s}: a `path:` input — it names a TREE, not a publication, so it pins no revision to agree about"
      ) pathSites;
    in
    {
      inherit
        domain
        rows
        incoherent
        singlePinned
        canDisagree
        noHubReference
        unreadable
        noGenEdges
        unlocked
        refusals
        pathExcluded
        pathSites
        exclusions
        ;
      memberCount = builtins.length domain;
      readCount = builtins.length readable;
      nodeCount = builtins.length nodes;
      siteCount = builtins.length pins;
      pathSiteCount = builtins.length pathPins;
      divergentCount = builtins.length divergentSites;
      agreeingCount = builtins.length agreeingSites;

      # READING (1) — the property `import` memoisation turns on.
      crossMemberCoherent = incoherent == [ ] && unlocked == [ ];
      # READING (2) — the spec's stated reference. See the header for why it does not gate.
      matchesHubRoot = divergentSites == [ ];
    };

  live = coherenceOf memberNames following liveLocks hubRootLock;
  liveRootPlane = rootPlaneOf memberNames following liveRootLocks;

  # ── THE ARMING ──
  # `crossMemberCoherent == true` is an ABSENCE CLAIM, so it travels with seeds that FIRE in the same
  # run and the same instrument. Every seed below is a member LOCK VALUE handed to the comparator
  # above; nothing here writes to a repository.
  #
  # ★★ EVERY ARM READS ITS SEED AT THE ROW, NEVER AS A SET DIFFERENCE AGAINST THE LIVE READING.
  # A seeded world is built ON TOP OF the live locks, so a REAL incoherence rides into every seed —
  # and the live reading has NINE incoherent nodes today. An absolute list (`incoherent == [x]`) is
  # red on all of them; a set difference collapses to empty when a live divergence lands on the seed's
  # own node. The ROW carries the SEEDED REVISION, a value no live lock can produce, so these arms are
  # immune to both. `ci/lock-agreement.nix` meets the same problem and answers it the same way.
  seedRev = "0000000000000000000000000000000000000000";
  seedNodeAtRev = {
    locked = {
      rev = seedRev;
      type = "github";
    };
  };
  # ★★ THE REFUSAL SEED IS A REVLESS **NON-PATH** NODE, AND THE TYPE IS THE WHOLE POINT. REFUSAL 3
  # is about a node that SHOULD name a revision and does not; a `path:` node is out of the relation
  # entirely (header). Seeding this as a path node would make the refusal arm and the exclusion arm
  # assert the same world, and one of the two would then be proving nothing.
  seedNodeUnlocked = {
    locked = {
      type = "tarball";
      url = "https://seed.invalid/no-rev.tar.gz";
    };
  };
  # …and its opposite number: a node that names a TREE. Must be EXCLUDED, never refused.
  seedNodePath = {
    locked = {
      path = "..";
      type = "path";
    };
  };

  # Rewrite ONE member's lock: its root inputs and its node table, one constructor, so a seed differs
  # from the live object in exactly the field it names. A rev-only mutation would be invisible — nix
  # resolves by node, so these seeds move the NODE an edge points at.
  # ★ PARAMETERISED ON THE LOCK SET, because the same seed must be plantable in EITHER PLANE. The
  # owner's rule is that one node is legitimate in a `ci/` lock and a violation in a ROOT lock, so
  # the pair that makes it falsifiable is the IDENTICAL seed differing only in which lock set it
  # lands in — `seedMemberLock` for the ci plane, `seedRootLock` for the root plane.
  seedLockIn =
    locks:
    {
      member,
      nodes ? { },
      rootInputs ? (i: i),
    }:
    let
      lock = locks.${member};
    in
    locks
    // {
      ${member} = lock // {
        nodes =
          lock.nodes
          // nodes
          // {
            ${lock.root} = lock.nodes.${lock.root} // {
              inputs = rootInputs (inputsOf lock lock.root);
            };
          };
      };
    };

  seedMemberLock = seedLockIn liveLocks;
  seedRootLock = seedLockIn liveRootLocks;

  # THE CONTROL NODE. `gen-harness` is the one node that is roster-wide coherent today — 21 sites,
  # 1 revision — so seeding ONE of its sites is the cleanest possible demonstration that this
  # comparator can turn a coherent node incoherent and NAME the member that moved.
  controlNode = "gen-harness";
  # ★ `gen-types` must HAVE a root lock for the root-plane seed to land in one — it does; the three
  # that do not are the zero-input leaves named in `rootPlaneOf`'s header.
  seedMember = "gen-types";

  seededIncoherence = coherenceOf memberNames following (seedMemberLock {
    member = seedMember;
    nodes."seed-pin" = seedNodeAtRev;
    rootInputs = i: i // { ${controlNode} = "seed-pin"; };
  }) hubRootLock;

  seededUnlocked = coherenceOf memberNames following (seedMemberLock {
    member = seedMember;
    nodes."seed-pin" = seedNodeUnlocked;
    rootInputs = i: i // { ${controlNode} = "seed-pin"; };
  }) hubRootLock;

  # The exclusion's own seed, identical to `seededUnlocked` in EVERY respect but `locked.type`. One
  # variable between two worlds: the tarball is refused and stays in the site count, the path is
  # excluded and leaves it. A seed that changed more than the type would not isolate the type.
  #
  # ★★★ AND THIS IS THE `ci/` ARM OF THE OWNER'S RULE. The very same node, the very same member, the
  # very same `locked.type = "path"` — planted HERE, in a `ci/` lock, it is LEGITIMATE and leaves the
  # relation. Planted in the ROOT lock by `seededRootPath` below, it is a VIOLATION and is named.
  # The two seeds differ in NOTHING but the lock set they land in, which is exactly the distinction
  # the ruling draws, so the pair is the ruling made falsifiable rather than asserted.
  seedPathAt = i: i // { ${controlNode} = "seed-pin"; };
  seededPathNode = coherenceOf memberNames following (seedMemberLock {
    member = seedMember;
    nodes."seed-pin" = seedNodePath;
    rootInputs = seedPathAt;
  }) hubRootLock;

  # …the ROOT arm of that pair.
  seededRootPath = rootPlaneOf memberNames following (seedRootLock {
    member = seedMember;
    nodes."seed-pin" = seedNodePath;
    rootInputs = seedPathAt;
  });

  # ★ WHAT PROVES THE PARTITION IS KEYED ON THE PLANE rather than on "a path node anywhere" is a RED
  # DRIVE, not an arm here: pointing `rootLockPathOf` at `ci/flake.lock` reds
  # `root-plane-refuses-path` on the LIVE corpus, because `gen-inspect` and `gen-memo`'s legitimate
  # self-references become violations. An in-cell arm for it would have to read the root plane over a
  # world whose CI lock was seeded — and the root locks are untouched there, so both sides would be
  # the live reading. That arm cannot fail, and an arm that cannot fail is not a control.

  seededNoGenEdges = coherenceOf memberNames following (seedMemberLock {
    member = seedMember;
    rootInputs = lib.filterAttrs (n: _: !(lib.hasPrefix "gen-" n));
  }) hubRootLock;

  # O-2's operand: the member reaches the node through a FOLLOWS PATH to another of its own root
  # inputs, and that target carries the seeded revision. The divergence is reachable ONLY by walking
  # the path, and the pre-limb reader reads the edge as an absent revision instead.
  seedFollowsLocks = seedMemberLock {
    member = seedMember;
    nodes."seed-pin" = seedNodeAtRev;
    rootInputs =
      i:
      i
      // {
        "gen-follows-target" = "seed-pin";
        ${controlNode} = [ "gen-follows-target" ];
      };
  };
  seededFollows = coherenceOf memberNames following seedFollowsLocks hubRootLock;
  seededFollowsDirectOnly = coherenceOf memberNames directOnly seedFollowsLocks hubRootLock;

  # ★★★ THE HUB-ROOT AXIS NEEDS A POSITIVE CONTROL BECAUSE NEITHER OF ITS COUNTS IS A READING ON ITS
  # OWN. Whichever way the ecosystem happens to sit, a comparator that cannot return `agreeing` at
  # all, and one that cannot return `divergent` at all, both produce a plausible pair of numbers.
  # This pair of seeded worlds moves ONE site across the axis and reads the crossing in both
  # directions: same member, same node, same site count, differing ONLY in the seeded revision.
  #
  # ★★ AND THE DELTA IS READ BETWEEN THE TWO SEEDS, NOT AGAINST `live`. This arm used to assert
  # `seeded.agreeingCount == live.agreeingCount + 1`, which silently made the LIVE ecosystem the
  # arm's operand: it holds only while that one site is divergent TODAY, and it goes red the moment
  # a relock converges it — a green check turning red on nothing but good news, with a message about
  # the domain floor. That is line-for-line the defect the block above forbids ("EVERY ARM READS ITS
  # SEED AT THE ROW, NEVER AS A SET DIFFERENCE AGAINST THE LIVE READING"), and this was the one arm
  # that broke it. Measured 2026-09-18 at the converged pins: `agreeingCount` 59 in BOTH worlds,
  # because `gen-types` had by then come to pin `gen-prelude` at the hub root's own revision, so the
  # seed had nothing left to move. The two-world form is immune: it CONSTRUCTS its own operand.
  hubRefNode = "gen-prelude";
  seedHubRootAt =
    rev:
    coherenceOf memberNames following (seedMemberLock {
      member = seedMember;
      nodes."seed-hub-axis" = {
        locked = {
          inherit rev;
          type = "github";
        };
      };
      rootInputs = i: i // { ${hubRefNode} = "seed-hub-axis"; };
    }) hubRootLock;

  # The two worlds. `seedRev` is all zeroes and no live lock can produce it, so the divergent arm is
  # divergent by construction rather than by the ecosystem's current state.
  seededHubRootDivergent = seedHubRootAt seedRev;
  seededHubRootAgreement = seedHubRootAt (
    revIn hubRootLock (following hubRootLock hubRootLock.root hubRefNode)
  );

  # ★★ THE READINGS' OWN POSITIVE CONTROL, NON-DEGENERATE. Both readings are FALSE of the live
  # ecosystem, and a predicate never seen to return true is not a reading. This world keeps all 21
  # members and narrows every one of them to the single edge that IS coherent — 1 node, 21 sites,
  # `crossMemberCoherent = true`. The empty-domain seed below also returns true, but over ZERO sites,
  # which is the answer `domain-from-roster` exists to refuse; this one is the answer it accepts.
  seededAllCoherent = coherenceOf memberNames following (builtins.mapAttrs (
    _: lock:
    lock
    // {
      nodes = lock.nodes // {
        ${lock.root} = lock.nodes.${lock.root} // {
          inputs = lib.filterAttrs (n: _: !(lib.hasPrefix "gen-" n) || n == controlNode) (
            inputsOf lock lock.root
          );
        };
      };
    }
  ) liveLocks) hubRootLock;

  # ── THE SILENT-GREEN SEED, and it is why `domain-from-roster` exists ──
  # The domain written WITHOUT the map — "the `gen-`-prefixed members of `mkGenLibs { }`" — over the
  # LIVE, HEALTHY locks. No refusal fires, because no member is reached at all: the domain is simply
  # empty and the cell reads coherent over ZERO nodes and ZERO sites. This is the one failure mode no
  # other arm here can see, and it is O2's `1 over 1` defect in its strongest form — `0 over 0`.
  verbatimDomain = builtins.filter (lib.hasPrefix "gen-") rosterKeys;
  seededVerbatimDomain = coherenceOf verbatimDomain following liveLocks hubRootLock;

  rowOfLive = n: lib.findFirst (r: r.node == n) null live.rows;
  rowIn = result: n: lib.findFirst (r: r.node == n) null result.rows;
  revsIn =
    result: n:
    let
      r = rowIn result n;
    in
    if r == null then [ ] else map (p: p.rev) r.pins;

  # ★ EVERY ROW READ BELOW IS TOTAL, AND THAT IS A REFUSAL RATHER THAN A CONVENIENCE. A seeded world
  # whose domain reaches nothing has no row for the control node, and `(rowIn …).distinct` then
  # ABORTS the whole cell — `expected a set but found null` from inside `derivationStrict`, which is
  # indistinguishable from a typo in this file and prints none of the named arming refusals the
  # builder is written to emit. Driven: the unmapped-spelling seed took this cell to rc 1 by ABORT
  # before this helper existed, and to rc 1 by a NAMED `PIN COHERENCE ARMING` line afterwards.
  fieldIn =
    result: n: f: fallback:
    let
      r = rowIn result n;
    in
    if r == null then fallback else r.${f};

  controlRow = rowOfLive controlNode;

  arming = {
    inherit controlNode seedMember seedRev;
    seededIncoherence = {
      named = builtins.elem controlNode seededIncoherence.incoherent;
      carriesSeed = builtins.elem seedRev (revsIn seededIncoherence controlNode);
      distinct = fieldIn seededIncoherence controlNode "distinct" 0;
      sites = fieldIn seededIncoherence controlNode "sites" 0;
      coherent = seededIncoherence.crossMemberCoherent;
    };
    seededHubRootAgreement = {
      inherit (seededHubRootAgreement) agreeingCount divergentCount;
      inherit hubRefNode;
    };
    seededHubRootDivergent = {
      inherit (seededHubRootDivergent) agreeingCount divergentCount;
    };
    seededAllCoherent = {
      inherit (seededAllCoherent)
        crossMemberCoherent
        nodeCount
        siteCount
        memberCount
        incoherent
        ;
    };
    seededUnlocked = {
      named = builtins.elem controlNode seededUnlocked.unlocked;
      carriesSeed = builtins.elem "<unlocked>" (revsIn seededUnlocked controlNode);
      refused = seededUnlocked.refusals != [ ];
      # …and it stays IN the relation: a refusal is a site this check could not read, never a site
      # it declined to range over.
      excluded = builtins.elem controlNode seededUnlocked.pathExcluded;
      siteCount = seededUnlocked.siteCount;
    };
    # The type's other side. Same seed, same member, same node, `locked.type = "path"`: NAMED in the
    # exclusions, ABSENT from the refusals, and the site leaves the count rather than reading as a
    # null revision that equals every other null.
    seededPathNode = {
      excluded = builtins.elem controlNode seededPathNode.pathExcluded;
      named = seededPathNode.exclusions != [ ];
      notRefused = !(builtins.elem controlNode seededPathNode.unlocked);
      notIncoherent = !(builtins.elem controlNode seededPathNode.incoherent);
      readsNoUnlockedRev = !(builtins.elem "<unlocked>" (revsIn seededPathNode controlNode));
      siteCount = seededPathNode.siteCount;
      pathSiteCount = seededPathNode.pathSiteCount;
    };
    # ── THE ROOT PLANE (owner-ruled 2026-09-18) ──
    # The live reading, and the SAME seed as `seededPathNode` planted one plane over.
    rootPlane = {
      inherit (liveRootPlane)
        lockAbsent
        readCount
        readableCount
        edgeCount
        pathSites
        ;
      clean = liveRootPlane.violations == [ ];
    };
    seededRootPath = {
      named = seededRootPath.violations != [ ];
      atSeedMember = builtins.elem seedMember seededRootPath.pathMembers;
      sites = builtins.length seededRootPath.pathSites;
      # The seed must not have moved the plane's SHAPE beyond the one edge it plants: same members
      # read, edge count up by EXACTLY one. A seed that also dropped an edge could name a violation
      # by accident of the walk shortening somewhere else.
      # ★ The ci arm's site count is UNMOVED by the identical seed and this one's edge count GROWS,
      # and that asymmetry is a true fact about the two planes rather than a defect: `gen-harness` is
      # a root edge of every member's CI lock (so the seed REPLACES) and of no member's ROOT lock (so
      # it ADDS). Measured 2026-09-18 — `gen-types`' root lock declares `gen-identity`, `gen-prelude`;
      # its ci lock declares those plus `gen-harness`.
      readCount = seededRootPath.readCount;
      edgeCount = seededRootPath.edgeCount;
    };
    seededNoGenEdges = {
      named = builtins.elem seedMember seededNoGenEdges.noGenEdges;
      refused = seededNoGenEdges.refusals != [ ];
      siteCount = seededNoGenEdges.siteCount;
    };
    seededFollows = {
      named = builtins.elem controlNode seededFollows.incoherent;
      carriesSeed = builtins.elem seedRev (revsIn seededFollows controlNode);
    };
    # The pre-limb reader over the IDENTICAL seed: it cannot walk the path, so it reads the edge as
    # an absent revision and the revision it would otherwise NAME becomes a refusal instead.
    seededFollowsDirectOnly = {
      carriesSeed = builtins.elem seedRev (revsIn seededFollowsDirectOnly controlNode);
      readsUnresolved = builtins.elem "<unlocked>" (revsIn seededFollowsDirectOnly controlNode);
    };
    # THE REJECTED BUILD: the unmapped spelling reaches nothing and reads as a held invariant.
    # Asserted TRUE below — if it ever stopped returning the silent answer, the arm that rejects it
    # would no longer be about anything.
    seededVerbatimDomain = {
      inherit (seededVerbatimDomain)
        domain
        crossMemberCoherent
        nodeCount
        siteCount
        memberCount
        ;
    };
  };

  # Every key MUST be `true`. The check builder is handed `builtins.attrNames` of this rather than a
  # hand-kept list beside it: a second register would let an arm be added here and left out of the
  # enforced set — an unchecked arm that reads exactly like a passing one.
  gate = {
    # ★★★ THE TWO READINGS — OWNER-OPEN, AND THE ONLY ARM-DEPENDENT OBJECTS IN THIS CELL. See the
    # header: reading (2) is not satisfiable while the member ci edge graph holds a cycle, and
    # reading (1) is false of the tree today (9 of the 10 nodes that can disagree). Both are
    # COMPUTED and PRINTED; whether either exits 1 is one line in `mkPinCoherenceCheck`.
    #   OBSERVE-ONLY, shipped:  an incoherent pin PRINTS and the build passes.
    #   GATING, one edit:       gating = failed != [ ];
    # ★ An ARMING failure exits 1 under BOTH arms.
    pins-cross-member-coherent = live.crossMemberCoherent;
    pins-match-hub-root = live.matchesHubRoot;

    # ★★ THE LIVE POSITIVE CONTROL, AND ITS CARDINALITY IS HALF THE ASSERTION. `gen-harness` is
    # pinned by every member and at one revision, so it shows this comparator reading coherence on a
    # real node rather than on an empty walk. O2's rule, applied: a walk that reaches exactly one
    # site ALSO yields `distinct = 1`, so `distinct == 1` alone is the same defect in a second dress
    # — the arm asserts the PAIR, `21 sites` against the roster's own member count.
    coherent-control =
      controlRow != null
      && controlRow.distinct == 1
      && controlRow.sites == live.memberCount
      && live.memberCount == builtins.length rosterKeys
      # …and the READING itself returns true over that world, over 21 sites rather than over zero.
      && arming.seededAllCoherent.crossMemberCoherent
      && arming.seededAllCoherent.incoherent == [ ]
      && arming.seededAllCoherent.nodeCount == 1
      && arming.seededAllCoherent.siteCount == live.memberCount;

    # ★★ O-1 — the comparator turns THE ONE COHERENT NODE incoherent and NAMES the seeded revision
    # at the row, with the site count unmoved so the arm cannot pass by losing sites. It reads the
    # seed's own value, which no live lock can produce, so a real incoherence riding into the seeded
    # world cannot satisfy it.
    arming-incoherence =
      arming.seededIncoherence.named
      && arming.seededIncoherence.carriesSeed
      && arming.seededIncoherence.distinct == 2
      && arming.seededIncoherence.sites == live.memberCount
      && !arming.seededIncoherence.coherent;

    # ★★ THE HUB-ROOT AXIS'S OWN CONTROL, READ BETWEEN THE TWO SEEDED WORLDS AND NOT AGAINST `live`.
    # Neither count is a reading on its own: a comparator that can never return `agreeing`, and one
    # that can never return `divergent`, both yield a plausible pair. One site crosses the axis
    # between the two worlds, and it must move BOTH counts by exactly one, in opposite directions —
    # so a limb that has gone blind in either direction fails here whatever the ecosystem's state.
    arming-hub-root-axis =
      arming.seededHubRootAgreement.agreeingCount == arming.seededHubRootDivergent.agreeingCount + 1
      && arming.seededHubRootAgreement.divergentCount == arming.seededHubRootDivergent.divergentCount - 1;

    # O-2 — the `follows` limb is load-bearing, shown by the same comparator reading the same seed
    # with the limb removed: the full reader walks the path to the seeded revision and NAMES the
    # incoherence; the pre-limb reader reaches an unresolvable edge and reads it as an absent
    # revision instead, so it cannot name what the limb names.
    follows-resolved =
      arming.seededFollows.named
      && arming.seededFollows.carriesSeed
      && !arming.seededFollowsDirectOnly.carriesSeed
      && arming.seededFollowsDirectOnly.readsUnresolved;

    # ★★ THE FLOOR, and it is the arm to read first because it is the only one whose failure is
    # SILENT. The domain is the roster of record MAPPED into the input namespace, non-empty, and
    # every member of it was actually opened. Armed on the unmapped spelling, which reads coherent
    # over zero nodes and zero sites on perfectly healthy locks.
    domain-from-roster =
      live.memberCount == builtins.length rosterKeys
      && live.memberCount > 0
      && live.readCount == live.memberCount
      && live.nodeCount > 0
      && live.siteCount >= live.memberCount
      && arming.seededVerbatimDomain.domain == [ ]
      && arming.seededVerbatimDomain.memberCount == 0
      && arming.seededVerbatimDomain.nodeCount == 0
      && arming.seededVerbatimDomain.siteCount == 0
      && arming.seededVerbatimDomain.crossMemberCoherent;

    # The three refusals, each NAMED: an unreadable member lock, a member declaring no `gen-*` root
    # input, and a node pinned without a `locked.rev`. A throw here is indistinguishable from a typo
    # in this file, and a `null == null` revision comparison is indistinguishable from coherence.
    edges-refused-by-name =
      live.unreadable == [ ]
      && arming.seededNoGenEdges.named
      && arming.seededNoGenEdges.refused
      && arming.seededNoGenEdges.siteCount < live.siteCount
      && arming.seededUnlocked.named
      && arming.seededUnlocked.carriesSeed
      && arming.seededUnlocked.refused
      # ★ THE REFUSAL SEED IS A REVLESS **NON-PATH** NODE, AND IT STAYS IN THE RELATION. This is the
      # genuine broken-instrument case the message is really for, and the path exclusion must not
      # have swallowed it: the seeded site is refused, is NOT excluded, and does not leave the count.
      && !arming.seededUnlocked.excluded
      && arming.seededUnlocked.siteCount == live.siteCount;

    # ★★★ A `path:` SITE IS OUT OF THE RELATION'S DOMAIN, BY TYPE — see the header, including why
    # this is outside `mkPinCoherenceCheck`'s prohibition on narrowing. Asserted against the refusal
    # seed above, from which it differs in `locked.type` AND NOTHING ELSE: that one field decides
    # excluded-vs-refused, the two lists are disjoint on it, and the path site leaves the count
    # instead of contributing a null revision that would read as agreement with every other null.
    path-nodes-out-of-domain =
      arming.seededPathNode.excluded
      && arming.seededPathNode.named
      && arming.seededPathNode.notRefused
      && arming.seededPathNode.notIncoherent
      && arming.seededPathNode.readsNoUnlockedRev
      # The site does not vanish — it MOVES, out of the relation and into the named exclusions.
      && arming.seededPathNode.siteCount == live.siteCount - 1
      && arming.seededPathNode.pathSiteCount == live.pathSiteCount + 1;

    # ★★★ THE ROOT PLANE REFUSES WHAT `ci/` PERMITS — owner-ruled 2026-09-18, "the path is valid for
    # self-ref at ci/ only, never at the root". A published library's ROOT is the plane consumers
    # resolve through, and a root that names itself by `path:` carries a second identity formula for
    # one node into exactly that plane.
    #
    # ★★ THIS IS NOT THE NARROWING `mkPinCoherenceCheck` FORBIDS — it is the opposite operation. That
    # message forbids shrinking this cell's domain to hide a disagreement. PARTITIONING BY PLANE
    # shrinks nothing: the relation keeps every node it could ever have judged, and the cell GAINS a
    # case it previously could not express at all, because it read no member's root lock. The domain
    # grew by one plane.
    #
    # ★ THE PAIR THAT MAKES THE RULING FALSIFIABLE IS `seededPathNode` AND `seededRootPath`: one node,
    # one member, one `locked.type`, differing ONLY in the lock set it is planted in — legitimate and
    # excluded in the first, named as a violation in the second. Asserted together, here, so neither
    # can be read alone.
    #
    # ★ AND THE FLOOR, because the live reading is an ABSENCE and the corpus already honours the rule
    # (53 `gen-*` root edges, all `github`, measured 2026-09-18): a walk that opened nothing would
    # also report no violations. The member partition must be TOTAL — every member either read or
    # named as having no root lock — and the edge count non-zero.
    root-plane-refuses-path =
      arming.rootPlane.clean
      && arming.rootPlane.pathSites == [ ]
      && arming.rootPlane.readCount > 0
      && arming.rootPlane.edgeCount > 0
      && arming.rootPlane.readCount + builtins.length arming.rootPlane.lockAbsent == live.memberCount
      # …and the same count derived from the LOCKS rather than from the partition, because the
      # arithmetic above balances even when a member with no root lock is counted as read.
      && arming.rootPlane.readCount == arming.rootPlane.readableCount
      # ROOT ARM — the seed is NAMED, at the member that carries it, exactly once.
      && arming.seededRootPath.named
      && arming.seededRootPath.atSeedMember
      && arming.seededRootPath.sites == 1
      && arming.seededRootPath.readCount == arming.rootPlane.readCount
      && arming.seededRootPath.edgeCount == arming.rootPlane.edgeCount + 1
      # `ci/` ARM — the identical node, planted one plane over, is legitimate and excluded.
      && arming.seededPathNode.excluded
      && arming.seededPathNode.notRefused;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "revision coherence of every shared node across the 21 roster members' `ci/flake.lock` files, read at the revision this hub pins";
    property = "for each shared node, every member pinning it names ONE revision — so a flakeless construction resolves one store path and `import` memoises to one value (spec §2, L7)";
    observable = "`locked.rev` at each member's `ci/flake.lock` root `gen-*` edges, resolved through `follows`, never by indexing `lock.nodes.<label>`";
    direction = "EXACT over the members' ROOT ci edges and SILENT below them: a member's transitive nodes are not compared, and a second gen-prelude reached only through a dependency's own lock is invisible here";
    domainSource = "`gen.lib.mkGenLibs { }`'s member keys MAPPED through `\"gen-\" + k` (the roster's keys are BARE), minus `strata` — ADR-0015's roster of record, never a count and never a lock";
    siteDomain = "every root `gen-*` edge of every enumerated member, MINUS the `path:`-typed ones: a `path:` input names a TREE and pins no revision, so it is not a participant in a relation about revisions (header). Excluded BY `locked.type` and NAMED in `pathExcluded`/`pathSites` — a revless NON-path node still REFUSES";
    rootPlane = "a SECOND reading, over each member's own ROOT `flake.lock`: a `path:`-typed `gen-*` root edge there is a VIOLATION and is named (owner-ruled 2026-09-18, `path:` self-reference is legitimate at `ci/` ONLY). A member declaring no root inputs has no root lock at all and is named in `rootPlane.lockAbsent` — not a violation, not a clean read";

    rootPlaneReading = {
      inherit (liveRootPlane)
        lockAbsent
        readCount
        edgeCount
        pathSites
        pathMembers
        absentNamed
        violations
        ;
    };
    hubReference = "the hub ROOT `flake.lock`'s `follows`-resolved revision per node. NOT SATISFIABLE while the member ci edge graph holds a cycle (header) — reported, not gated";

    inherit (live)
      rows
      incoherent
      singlePinned
      canDisagree
      noHubReference
      unreadable
      noGenEdges
      unlocked
      refusals
      pathExcluded
      pathSites
      exclusions
      memberCount
      readCount
      nodeCount
      siteCount
      pathSiteCount
      divergentCount
      agreeingCount
      crossMemberCoherent
      matchesHubRoot
      ;

    inherit arming;
  };
}
