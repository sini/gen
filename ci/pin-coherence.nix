# pin-coherence — L7: roster-wide pin coherence across the 22 members' `ci/flake.lock` files.
#
# ── WHAT THIS IS FOR, AND WHY IT IS A CLAUSE AND NOT HOUSEKEEPING ──
# `specs/2026-09-14-gen-module-layout-pattern-spec.md` §2, L7. Under L1 a library's `default.nix`
# defaults each dependency out of its OWN `ci/flake.lock`, so a flakeless construction of one
# library resolves each shared dependency once per pinning member. `import` memoises by STORE PATH:
# coherent pins collapse that split to one value with no further mechanism, and incoherent pins
# re-open it silently the moment one library lands. The hub is the only place that sees all 22 ci
# locks — it does not already hold the answer, it holds the only lever.
#
# ── THE SUBJECT IS THE MEMBERS' CI LOCKS, NOT THE HUB'S OWN TWO ──
# The hub's own root-vs-ci question is closed by construction: `gen` is the root flake read at `self`,
# so ci resolves members through the root lock and holds no copy of it (den-hoag-lbtnv D1 retired
# `lock-agreement`, which gated that copy). This one compares ONE edge class across TWENTY-TWO
# repositories, which no construction in the hub closes.
#
# ── THE TWO READINGS, AND WHY THEY ARE SEPARATE KEYS ──
# (1) CROSS-MEMBER coherence — for each shared node, all members pinning it name ONE revision. This
#     is the property that makes `import` memoise, and it is satisfiable: `gen-harness` reads 22
#     sites at 1 revision today, live, in the domain.
# (2) HUB-ROOT agreement — every member pin equals the hub ROOT lock's `follows`-resolved revision
#     for that node. The spec names this as L7's reference and the bump's target.
#
# BOTH ARE COMPUTED AND PRINTED; NEITHER GATES. They meter the TEST graph (ADR-0037), which may drift.
# (2) was once argued unsatisfiable under a member→member ci edge cycle (gen-merge/ci ⇄ gen-memo/ci,
# measured at gen `bd57c06`); gen-memo's ci no longer declares gen-merge, and both readings are true at
# gen `2eb2e48`. Kept observe-only (den-hoag-4dfsv spec OQ3, defaulted). Everything BELOW the readings —
# the domain floor, the live control, the arming and the refusals — gates, because a guard that can no
# longer fire is not a passing guard.
#
# ── ROOT-PLANE COHERENCE: R1 AND R2, AND BOTH GATE (owner-ruled 2026-09-25, den-hoag-4dfsv §4.1(b)) ──
# The standalone path resolves through ROOT locks (`default.nix` reads `./flake.lock`), not ci locks,
# so the ruled property lives there:
# R1 `root-plane-coherent` — ONE REVISION per repository over the hub's root lock plus every member's
#     root lock at this hub's pin, every node reachable BY NODE PATH (not root edges only: a stale
#     nested copy in a hand-edited member lock is invisible to a root-edge reader). Identity is read
#     from `locked` and NORMALISED — github owner/repo lowercased, a `git`/`tarball` URL on
#     `github.com/<o>/<r>` parsed to the same key — and EVERY keyable identity is compared, roster or
#     not. Price, ruled: same REVISION, not same INSTANCE — a member imported twice standalone is
#     evaluated twice. Consequence, ruled: a targeted partial hub relock is no longer publishable
#     (reverses den-hoag-kx1d3's verdict); leaf-first `relock-all` is what keeps R1 green.
# R2 `hub-root-follows-complete` — ONE NODE per repository in the hub's root lock: each keyable
#     identity a hub root input resolves to is reached at that input's node only. This is the flake
#     path's INSTANCE property (ADR-0008 §1, "a single instance can be used"), and it is arm 1, a
#     lock-reading cell, of den-hoag-jzofm's three-arm stop-and-promote (arm 2 a names-only
#     follows-bound cell, arm 3 publishing the edges as a value). jzofm's "expose deps" half is NOT
#     discharged here. The red prints each missing `follows` line literally, nested where the stray
#     sits under a non-root-pinned intermediary.
#   ★ R2 CANNOT SEE a second instance of an UNKEYABLE root: the hub's `nixpkgs` is a release tarball
#     whose URL embeds the release, so no second nixpkgs node ever shares its identity. The uncovered
#     roots are named in `report.hubFollows.uncoveredRoots` and on every run.
# Together they discharge den-hoag-hub-entry-paths-disagree-silently-oii6u AT REVISION: both entry
# paths resolve one revision per roster member. Not at instance on the standalone path — the ruled price.
# A member with no root lock (`lockAbsent`) is converged by construction only if its `flake.nix`
# declares no inputs, and `root-plane-domain-floor` evaluates that rather than assuming it.
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
# unable to coexist with the self-input invariant (den-hoag-c0wc1), one of whose repairs is a member
# following its own node onto the tree under test by `path:` — which is what makes THAT invariant
# testable, and is not this check's to undo.
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
  # `ci/sole-evaluator.nix` applies, for the same reason.
  rosterMetaKeys = [ "strata" ];
  rosterKeys = builtins.filter (k: !(builtins.elem k rosterMetaKeys)) (builtins.attrNames roster);

  sorted = builtins.sort (a: b: a < b);
  unique = xs: builtins.attrNames (builtins.listToAttrs (map (x: lib.nameValuePair x null) xs));

  # ★★ THE MAP — see the header. Omitting it makes this the empty set.
  memberNames = sorted (map (k: "gen-" + k) rosterKeys);

  # ── REACHING THE MEMBER TREES ──
  # `gen.inputs.<name>.outPath`, which is `ci/sole-evaluator.nix`'s route to the same 22 trees. Each
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
  # Nix's own `follows` rule, one dimension over. A direct edge IS the node key; a
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

  # ── THE ROOT-PLANE CLOSURE: readings R1 and R2 (den-hoag-4dfsv §4.1(b), owner-ruled 2026-09-25) ──
  # See the header's ROOT-PLANE COHERENCE block for what each reading claims and what it does not.
  #
  # IDENTITY IS READ FROM `locked`, NEVER FROM AN INPUT NAME OR A NODE LABEL, AND IT IS NORMALISED.
  # `fetchTree` accepts any type, so `sini/gen-x`, `Sini/gen-x` and `git+https://github.com/sini/gen-x`
  # load the same repository; keyed apart, two revisions of it would read as two coherent
  # repositories. Unkeyable sites (a release tarball, a `path:` tree) are NAMED in `outOfDomain`.
  githubUrl =
    u: builtins.match "(git\\+)?(https?|ssh)://([^@/]*@)?github\\.com/([^/]+)/([^/?#]+).*" u;
  identityOf =
    lk:
    let
      m = if builtins.isString (lk.url or null) then githubUrl lk.url else null;
      key = o: r: "github:${lib.toLower o}/${lib.toLower (lib.removeSuffix ".git" r)}";
    in
    if (lk.type or null) == "github" then
      key lk.owner lk.repo
    else if m != null then
      key (builtins.elemAt m 3) (builtins.elemAt m 4)
    else
      null;

  # Every node reachable from `lock.root` BY NODE PATH, each with the first path that reached it and
  # the node keys along it. `expand` decides which entries are walked through: everything for R1,
  # depth ≤ 1 for its root-edge control, stray-free for R2's repair lines. One traversal, three
  # restrictions — as `directOnly` is to `following`, never a second implementation.
  # ★ An edge `following` cannot resolve becomes an UNRESOLVED entry, never a dropped one.
  closureOf =
    expand: lock:
    builtins.genericClosure {
      startSet = [
        {
          key = lock.root;
          path = [ ];
        }
      ];
      operator =
        n:
        if !(lock.nodes ? ${n.key}) || !(expand n) then
          [ ]
        else
          map (
            i:
            let
              t = following lock n.key i;
              p = n.path ++ [ i ];
            in
            {
              key = if t == null then "<unresolved>/${lib.concatStringsSep "/" p}" else t;
              path = p;
            }
          ) (builtins.attrNames (inputsOf lock n.key));
    };
  walkAll = _: true;
  walkRootEdges = n: n.path == [ ];

  sitesIn =
    expand: label: lock:
    map (
      n:
      let
        lk = lock.nodes.${n.key}.locked or { };
      in
      {
        inherit (n) path;
        node = n.key;
        site = "${label}:${lib.concatStringsSep "/" n.path}";
        resolved = lock.nodes ? ${n.key};
        identity = identityOf lk;
        rev = lk.rev or null;
      }
    ) (builtins.filter (n: n.key != lock.root) (closureOf expand lock));

  # R1 — ONE REVISION PER REPOSITORY over the hub's root lock and every member's root lock at this
  # hub's pin. Every keyable identity is compared, roster or not.
  rootCoherenceOf =
    expand: hubLock: rootLocks:
    let
      population = {
        gen = hubLock;
      }
      // lib.filterAttrs (_: l: l != null) rootLocks;
      all = builtins.concatMap (l: sitesIn expand l population.${l}) (builtins.attrNames population);
      unresolved = sorted (map (s: s.site) (builtins.filter (s: !s.resolved) all));
      keyed = builtins.filter (s: s.resolved && s.identity != null) all;
      outOfDomain = sorted (map (s: s.site) (builtins.filter (s: s.resolved && s.identity == null) all));
      revOf = s: if s.rev == null then "<unlocked>" else s.rev;
      rows = lib.mapAttrsToList (identity: ss: {
        inherit identity;
        sites = builtins.length ss;
        revs = map (r: {
          rev = r;
          sites = sorted (map (s: s.site) (builtins.filter (s: revOf s == r) ss));
        }) (sorted (unique (map revOf ss)));
      }) (builtins.groupBy (s: s.identity) keyed);
      incoherentRows = builtins.filter (r: builtins.length r.revs > 1) rows;
      unlocked = sorted (unique (map (s: s.identity) (builtins.filter (s: s.rev == null) keyed)));
    in
    {
      inherit
        rows
        incoherentRows
        unlocked
        unresolved
        outOfDomain
        ;
      locks = builtins.attrNames population;
      incoherent = map (r: r.identity) incoherentRows;
      siteCount = builtins.length keyed;
      identityCount = builtins.length rows;
      holds = incoherentRows == [ ] && unlocked == [ ] && unresolved == [ ];
    };

  # R2 — ONE NODE PER REPOSITORY in the hub's root lock: every keyable identity a hub root input
  # resolves to is reached at exactly that input's node. Any other node of it is a STRAY, and the
  # repair is a `follows` line, printed literally. Lines come from the edges of the STRAY-FREE
  # closure into a stray, so a stray under a non-root-pinned intermediary gets its full nested line,
  # and one reachable only through another stray is subsumed by that stray's line.
  hubFollowsOf =
    lock:
    let
      rootInputs = sorted (builtins.attrNames (inputsOf lock lock.root));
      nodeOf = i: following lock lock.root i;
      idOfNode =
        k: if k != null && lock.nodes ? ${k} then identityOf (lock.nodes.${k}.locked or { }) else null;
      # `listToAttrs` keeps the FIRST binding, so of two root inputs of one repository the
      # alphabetically first is the reference and the other reads as a stray of it.
      rootPins = builtins.listToAttrs (
        builtins.concatMap (
          i:
          let
            id = idOfNode (nodeOf i);
          in
          lib.optional (id != null) (
            lib.nameValuePair id {
              input = i;
              node = nodeOf i;
            }
          )
        ) rootInputs
      );
      isStray =
        k:
        let
          id = idOfNode k;
        in
        id != null && rootPins ? ${id} && rootPins.${id}.node != k;
      strays = builtins.filter (n: isStray n.key) (closureOf walkAll lock);
      missingFollows = sorted (
        unique (
          builtins.concatMap (
            n:
            builtins.concatMap (
              j:
              let
                t = following lock n.key j;
              in
              lib.optional (t != null && isStray t)
                "${
                  lib.concatMapStrings (s: s + ".inputs.") n.path
                }${j}.follows = \"${rootPins.${idOfNode t}.input}\";"
            ) (builtins.attrNames (inputsOf lock n.key))
          ) (builtins.filter (n: !(isStray n.key)) (closureOf (n: !(isStray n.key)) lock))
        )
      );
    in
    {
      inherit missingFollows;
      nodeCount = builtins.length (builtins.attrNames lock.nodes);
      strayCount = builtins.length strays;
      strayRepos = sorted (unique (map (n: idOfNode n.key) strays));
      rootPinCount = builtins.length (builtins.attrNames rootPins);
      # C2: roots R2 cannot key, so a second instance of them is invisible to it — NAMED, not counted.
      uncoveredRoots = builtins.filter (i: idOfNode (nodeOf i) == null) rootInputs;
      holds = strays == [ ];
    };

  liveR1 = rootCoherenceOf walkAll hubRootLock liveRootLocks;
  liveR1RootEdges = rootCoherenceOf walkRootEdges hubRootLock liveRootLocks;
  liveR2 = hubFollowsOf hubRootLock;

  # P5: a lockless member is converged by construction ONLY if it really declares no inputs.
  lockAbsentDeclaring = builtins.filter (
    m: (import "${gen.inputs.${m}.outPath}/flake.nix").inputs or { } != { }
  ) liveRootPlane.lockAbsent;

  # ── THE ROOT-PLANE SEEDS, their sites DERIVED from the live locks (never a hard-coded node) ──
  setNode =
    lock: key: f:
    lock
    // {
      nodes = lock.nodes // {
        ${key} = f lock.nodes.${key};
      };
    };
  # The first member root lock (sorted) with a github-typed root edge, and that edge. A world
  # without one leaves `r1Seed = null`, and every R1 arm reads false by name rather than aborting.
  r1Seed = lib.findFirst (s: s != null) null (
    map (
      m:
      let
        lock = liveRootLocks.${m} or null;
        edge =
          if lock == null then
            null
          else
            lib.findFirst (e: (lock.nodes.${following lock lock.root e}.locked.type or null) == "github") null (
              sorted (builtins.attrNames (inputsOf lock lock.root))
            );
      in
      if edge == null then
        null
      else
        rec {
          member = m;
          inherit edge;
          node = following lock lock.root edge;
          locked = lock.nodes.${node}.locked;
          identity = identityOf locked;
          site = "${m}:${edge}";
        }
    ) memberNames
  );
  r1SeedWorld =
    f:
    if r1Seed == null then
      null
    else
      rootCoherenceOf walkAll hubRootLock (
        liveRootLocks // { ${r1Seed.member} = f liveRootLocks.${r1Seed.member}; }
      );
  # Does `world` carry `seedRev` for `identity`, at `site`? Read AT THE ROW, never as a set difference.
  seedAt =
    world: identity: site:
    world != null
    && builtins.any (
      r:
      r.identity == identity
      && builtins.any (p: p.rev == seedRev && builtins.elem site p.sites) r.revs
      && builtins.elem identity world.incoherent
    ) world.rows;
  relock = f: lock: setNode lock r1Seed.node (n: n // { locked = f n.locked; });

  # s2 — the seed edge's node moved to `seedRev`, in place: the site count cannot move.
  seededRootIncoherence = r1SeedWorld (relock (lk: lk // { rev = seedRev; }));
  # s5 — owner spelled in another case: the same repository.
  seededRootOwnerCase = r1SeedWorld (
    relock (
      lk:
      lk
      // {
        owner = lib.toUpper lk.owner;
        rev = seedRev;
      }
    )
  );
  # s8 — the same repository reached by a `git+https` URL.
  seededRootGitUrl = r1SeedWorld (
    relock (_: {
      type = "git";
      url = "git+https://github.com/${r1Seed.locked.owner}/${r1Seed.locked.repo}.git";
      rev = seedRev;
    })
  );
  # s3 — a copy at `seedRev` planted ONLY at depth 2, under the seed edge's node. The root-edge
  # restriction of the same walk must NOT see it: that pair is what the closure is for.
  nestedAt =
    lock:
    seedLockIn { ${r1Seed.member} = lock; } {
      member = r1Seed.member;
      nodes = {
        "seed-nested".locked = r1Seed.locked // {
          rev = seedRev;
        };
        ${r1Seed.node} = lock.nodes.${r1Seed.node} // {
          inputs = inputsOf lock r1Seed.node // {
            "seed-nested" = "seed-nested";
          };
        };
      };
    };
  nestedSite = "${r1Seed.site}/seed-nested";
  seededRootNested = r1SeedWorld (l: (nestedAt l).${r1Seed.member});
  seededRootNestedRootEdges =
    if r1Seed == null then
      null
    else
      rootCoherenceOf walkRootEdges hubRootLock (
        liveRootLocks // (nestedAt liveRootLocks.${r1Seed.member})
      );
  # s6 — a NON-roster `sini/gen-*` repository at two revisions in two members' root locks.
  nonRosterRepo = "gen-harness";
  nonRosterIdentity = "github:${lib.toLower r1Seed.locked.owner}/${nonRosterRepo}";
  seedNonRosterAt =
    rev: m:
    (seedLockIn liveRootLocks {
      member = m;
      nodes."seed-nonroster".locked = {
        type = "github";
        owner = r1Seed.locked.owner;
        repo = nonRosterRepo;
        inherit rev;
      };
      rootInputs = i: i // { "seed-nonroster" = "seed-nonroster"; };
    }).${m};
  nonRosterMembers = lib.take 2 (builtins.filter (m: liveRootLocks.${m} or null != null) memberNames);
  seededRootNonRoster =
    if builtins.length nonRosterMembers < 2 then
      null
    else
      rootCoherenceOf walkAll hubRootLock (
        liveRootLocks
        // lib.genAttrs [ (builtins.elemAt nonRosterMembers 0) ] (seedNonRosterAt controlBaseRev)
        // lib.genAttrs [ (builtins.elemAt nonRosterMembers 1) ] (seedNonRosterAt seedRev)
      );

  # The hub seeds: the first root input (sorted) whose node has an input resolving to a ROOT-PINNED
  # node, and that input. s1 re-points it at a fresh copy of that node (same revision); s7 plants the
  # copy one level deeper, under a non-root-pinned intermediary.
  hubRootNodes = map (i: following hubRootLock hubRootLock.root i) (
    builtins.attrNames (inputsOf hubRootLock hubRootLock.root)
  );
  r2Seed = lib.findFirst (s: s != null) null (
    map (
      i:
      let
        node = following hubRootLock hubRootLock.root i;
        j = lib.findFirst (j: builtins.elem (following hubRootLock node j) hubRootNodes) null (
          sorted (builtins.attrNames (inputsOf hubRootLock node))
        );
      in
      if j == null then
        null
      else
        rec {
          input = i;
          inherit node j;
          target = following hubRootLock node j;
          targetInput = lib.findFirst (r: following hubRootLock hubRootLock.root r == target) null (
            sorted (builtins.attrNames (inputsOf hubRootLock hubRootLock.root))
          );
          line = "${i}.inputs.${j}.follows = \"${targetInput}\";";
          nestedLine = "${i}.inputs.seed-intermediary.inputs.${j}.follows = \"${targetInput}\";";
        }
    ) (sorted (builtins.attrNames (inputsOf hubRootLock hubRootLock.root)))
  );
  hubSeedWith =
    extra: setNode hubRootLock r2Seed.node (n: n // { inputs = (n.inputs or { }) // extra; });
  withCopy =
    lock:
    lock
    // {
      nodes = lock.nodes // {
        "seed-copy" = hubRootLock.nodes.${r2Seed.target};
      };
    };
  seededHubStray =
    if r2Seed == null then
      null
    else
      withCopy (hubSeedWith {
        ${r2Seed.j} = "seed-copy";
      });
  seededHubNested =
    if r2Seed == null then
      null
    else
      let
        l = withCopy (hubSeedWith {
          "seed-intermediary" = "seed-intermediary";
        });
      in
      l
      // {
        nodes = l.nodes // {
          "seed-intermediary" = {
            locked = {
              type = "github";
              owner = "sini";
              repo = "seed-intermediary";
              rev = seedRev;
            };
            inputs.${r2Seed.j} = "seed-copy";
          };
        };
      };
  seededHubStrayR2 = if seededHubStray == null then null else hubFollowsOf seededHubStray;
  seededHubStrayR1 =
    if seededHubStray == null then null else rootCoherenceOf walkAll seededHubStray liveRootLocks;
  seededHubNestedR2 = if seededHubNested == null then null else hubFollowsOf seededHubNested;

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
  # immune to both.
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

  # THE CONTROL NODE, AND IT IS NOT LOAD-BEARING. The name selects only WHICH input name the seeds
  # are planted on; the construction below forces that edge onto every member and supplies its
  # revision, so the arming world's coherence is a property of THIS FILE rather than of the
  # ecosystem. `gen-harness` is kept because it is a real `gen-*` root edge of every member's ci
  # lock, so the narrowed world's edges are real edges rather than synthetic ones.
  #
  # ★★ THE SENTENCE THAT STOOD HERE — "`gen-harness` is the one node that is roster-wide coherent
  # today" — RECORDED A MEASUREMENT AS THOUGH IT WERE A PROPERTY, and THAT was the defect, not the
  # name. An arming arm resting on it refuses the moment one member lands out of step, which is a
  # state ADR-0037 explicitly tolerates; an arming world must be coherent by construction or it is
  # reading the very ecosystem it exists to judge.
  controlNode = "gen-harness";
  # ★ `gen-types` must HAVE a root lock for the root-plane seed to land in one — it does; the three
  # that do not are the zero-input leaves named in `rootPlaneOf`'s header.
  seedMember = "gen-types";

  # ── THE CONSTRUCTED CONTROL BASE, and it replaces `seededAllCoherent`'s live-pin narrowing ──
  # That narrowing kept every member's own PIN of the control edge, so the world it built was
  # coherent only while the ecosystem was. Pointing the narrowed edge at ONE synthetic node makes
  # the world's coherence a property of this file, which is what an arming world is for.
  controlBaseRev = "1111111111111111111111111111111111111111";
  atControl =
    label: locks:
    builtins.mapAttrs (
      _: lock:
      lock
      // {
        nodes = lock.nodes // {
          "control-base".locked = {
            rev = controlBaseRev;
            type = "github";
          };
          "control-moved".locked = {
            rev = seedRev;
            type = "github";
          };
          ${lock.root} = lock.nodes.${lock.root} // {
            inputs = lib.filterAttrs (n: _: !(lib.hasPrefix "gen-" n)) (inputsOf lock lock.root) // {
              ${controlNode} = label;
            };
          };
        };
      }
    ) locks;

  # THE PAIR. They differ in ONE member's ONE site and in nothing else, so every count read between
  # them is attributable to that site. `seedRev` is all zeroes and no live lock can produce it.
  controlBaseLocks = atControl "control-base" liveLocks;
  controlMovedLocks = controlBaseLocks // {
    ${seedMember} =
      (atControl "control-moved" { ${seedMember} = liveLocks.${seedMember}; }).${seedMember};
  };

  # ★★ O-1's WORLD, BUILT RATHER THAN OBSERVED. The binding that stood here seeded one site of the
  # control node over the LIVE lock set, which made `arming-incoherence`'s `distinct == 2` an
  # accidental live reading — exact only while every other site agreed. Over the constructed pair it
  # is a statement about the pair: `controlBaseRev` and `seedRev`, two revisions, by construction.
  seededIncoherence = coherenceOf memberNames following controlMovedLocks hubRootLock;

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
  # `root-plane-refuses-path` wherever a member's ci lock holds a legitimate `path:` self-reference,
  # which then becomes a violation. No roster member's ci lock holds one (den-hoag-mxbv4 removed the
  # last), so the drive needs such a lock planted to read red. An in-cell arm for it would have to
  # read the root plane over a world whose CI lock was seeded — and the root locks are untouched there, so both sides would be
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

  # ★★ THE READINGS' OWN POSITIVE CONTROL, NON-DEGENERATE — AND CONSTRUCTED, NOT OBSERVED. Both
  # readings are FALSE of the live ecosystem, and a predicate never seen to return true is not a
  # reading. This world keeps all 22 members and narrows every one of them to the single CONSTRUCTED
  # edge — 1 node, 22 sites, `crossMemberCoherent = true`, guaranteed by `atControl` rather than read
  # off whatever the roster happens to agree on today. The empty-domain seed below also returns true,
  # but over ZERO sites, which is the answer `domain-from-roster` exists to refuse; this one is the
  # answer it accepts.
  seededAllCoherent = coherenceOf memberNames following controlBaseLocks hubRootLock;

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
    # ★★★ THE TWO ci-PLANE READINGS — OBSERVE-ONLY (header). Both are COMPUTED and PRINTED; whether
    # either exits 1 is one line in `mkPinCoherenceCheck`.
    #   OBSERVE-ONLY, shipped:  an incoherent pin PRINTS and the build passes.
    #   GATING, one edit:       gating = failed != [ ];
    # ★ An ARMING failure exits 1 under BOTH arms.
    pins-cross-member-coherent = live.crossMemberCoherent;
    pins-match-hub-root = live.matchesHubRoot;

    # ★★ THE POSITIVE CONTROL, AND ITS CARDINALITY IS HALF THE ASSERTION. The world it reads is
    # CONSTRUCTED — every member narrowed to one synthetic node at one synthetic revision — so it
    # shows this comparator reading coherence on a real traversal over real member locks without
    # asserting anything about which nodes the ecosystem currently agrees on. The two conjuncts that
    # did assert that (`controlRow.distinct == 1`, `controlRow.sites == live.memberCount`) are SHED:
    # they made this arm red whenever one member was a commit out of step, a state ADR-0037
    # tolerates. O2's rule still applies and the degeneracy PAIR is what carries it: a walk reaching
    # exactly one site ALSO yields `distinct = 1`, so `nodeCount == 1` alone is the same defect in a
    # second dress — the arm asserts it against `22 sites`, the roster's own member count, and over
    # the constructed world those counts are guaranteed rather than observed.
    coherent-control =
      controlRow != null
      && live.memberCount == builtins.length rosterKeys
      # …and the READING itself returns true over that world, over 22 sites rather than over zero.
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
    #
    # ★★★ `arming.seededPathNode.notIncoherent` IS NOT A CONJUNCT HERE, AND ITS ABSENCE IS THE
    # PROPERTY. It still PRINTS, in the `arming` projection — as a reading, which is what it always
    # was. `incoherent = rowsBy (r: r.distinct > 1)` over `distinct = length (unique revs)`, and the
    # excluded set is this file's ONE `isPathPin` predicate complemented, so excluding a site can
    # only SHRINK the revision set: `distinct` is monotone non-increasing under exclusion and an
    # exclusion therefore CANNOT CREATE an incoherence. That leaves `notIncoherent` exactly two ways
    # to be false — the control node is already incoherent among the sites that remain, which is a
    # fact about the ecosystem and one ADR-0037 tolerates; or the exclusion did not fire, which
    # `readsNoUnlockedRev`, `excluded`, `named`, `notRefused` and both site counts below all assert
    # already. There is no third cause, so the conjunct carried a READING and no guard.
    path-nodes-out-of-domain =
      arming.seededPathNode.excluded
      && arming.seededPathNode.named
      && arming.seededPathNode.notRefused
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
    # ★★★ R1 — ONE REVISION PER REPOSITORY over the root plane, closure by node path (owner-ruled
    # 2026-09-25, den-hoag-4dfsv §4.1(b)). GATES. Header: ROOT-PLANE COHERENCE.
    root-plane-coherent = liveR1.holds;
    # ★★★ R2 — ONE NODE PER REPOSITORY in the hub root lock. GATES; the red prints the lines to add.
    hub-root-follows-complete = liveR2.holds;

    # s2 — the seed edge's node at `seedRev`, IN PLACE: R1 names it at its site, the count unmoved.
    arming-root-plane-incoherence =
      r1Seed != null
      && seedAt seededRootIncoherence r1Seed.identity r1Seed.site
      && seededRootIncoherence.siteCount == liveR1.siteCount
      && !seededRootIncoherence.holds;
    # s3 — a depth-2-only copy at `seedRev`: the closure names it, the root-edge restriction of the
    # same walk does not. That pair is the closure's reason to exist.
    arming-root-plane-nested =
      r1Seed != null
      && seedAt seededRootNested r1Seed.identity nestedSite
      && !builtins.any (
        r: r.identity == r1Seed.identity && builtins.any (p: p.rev == seedRev) r.revs
      ) seededRootNestedRootEdges.rows;
    # C1 — the identity is normalised and the domain is not roster-filtered. Each seed loads two
    # revisions of one repository on the standalone path and must read false.
    arming-root-plane-owner-case =
      r1Seed != null && seedAt seededRootOwnerCase r1Seed.identity r1Seed.site;
    arming-root-plane-git-url = r1Seed != null && seedAt seededRootGitUrl r1Seed.identity r1Seed.site;
    arming-root-plane-non-roster =
      seededRootNonRoster != null
      && !(builtins.elem nonRosterRepo memberNames)
      && builtins.elem nonRosterIdentity seededRootNonRoster.incoherent;

    # s1 — one member's edge re-pointed at a fresh copy of a root-pinned node, SAME revision: R2 names
    # exactly that line while R1 is unmoved. Instance and revision come apart, permanently shown.
    arming-hub-follows =
      seededHubStrayR2 != null
      && !seededHubStrayR2.holds
      && builtins.elem r2Seed.line seededHubStrayR2.missingFollows
      && seededHubStrayR1.incoherent == liveR1.incoherent;
    # s7 (C3) — the copy under a non-root-pinned intermediary: the NESTED line is printed, and the
    # depth-2 line it would otherwise be confused with is not.
    arming-hub-follows-nested =
      seededHubNestedR2 != null
      && !seededHubNestedR2.holds
      && builtins.elem r2Seed.nestedLine seededHubNestedR2.missingFollows
      && !(builtins.elem r2Seed.line seededHubNestedR2.missingFollows);

    # The floor under both readings, because both are ABSENCE claims: every member root lock read
    # or named lockless, the lockless ones really declaring no inputs (P5), sites reached by the
    # closure and by its root-edge restriction, an unkeyable site named (the hub's nixpkgs tarball),
    # and at least one hub root pin R2 can key.
    root-plane-domain-floor =
      builtins.length liveR1.locks == 1 + liveRootPlane.readCount
      && liveRootPlane.readCount + builtins.length liveRootPlane.lockAbsent == live.memberCount
      && lockAbsentDeclaring == [ ]
      && liveR1.siteCount > 0
      && liveR1RootEdges.siteCount > 0
      && liveR1.outOfDomain != [ ]
      && liveR2.rootPinCount > 0;

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
    governs = "revision coherence of every shared node across the 22 roster members' `ci/flake.lock` files, read at the revision this hub pins";
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
    hubReference = "the hub ROOT `flake.lock`'s `follows`-resolved revision per node — reported, not gated (header)";

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

    rootCoherence = {
      governs = "R1: one REVISION per repository over the hub root `flake.lock` and every member root `flake.lock` at this hub's pin, every node reachable by node path (owner-ruled 2026-09-25, den-hoag-4dfsv §4.1(b))";
      inherit (liveR1)
        locks
        siteCount
        identityCount
        incoherent
        incoherentRows
        unlocked
        unresolved
        outOfDomain
        ;
      rootEdgesIncoherent = liveR1RootEdges.incoherent;
      inherit lockAbsentDeclaring;
    };
    hubFollows = {
      governs = "R2: one NODE per repository in the hub root `flake.lock` — every keyable identity a hub root input resolves to is reached at that input's node only";
      inherit (liveR2)
        nodeCount
        strayCount
        strayRepos
        rootPinCount
        uncoveredRoots
        missingFollows
        ;
    };
    rootPlaneArming = {
      inherit r1Seed r2Seed nestedSite;
      nonRoster = {
        identity = nonRosterIdentity;
        members = nonRosterMembers;
      };
    };

    inherit arming;
  };
}
