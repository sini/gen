# lock-agreement — the hub's two-edge pin-agreement predicate (den-hoag-0moiy).
#
# ── THE DEFECT THIS REMOVES ──
# Every check under `ci/` builds its roster from `inputs.gen`, whose sibling inputs resolve through
# `ci/flake.lock`'s copy of the `gen` node — NOT through the root `flake.lock`. The two locks agree
# today and nothing kept them agreeing: a root pin bump that BREAKS the wiring passes
# `nix flake check ./ci` GREEN, because ci's evaluation never reads the root's pin at all. Several
# checks under `ci/` said in prose that they observed the root's pins; none of them did. This cell is
# the second object that makes the two locks' disagreement visible instead of silent.
#
# ── THE PREDICATE: TWO EDGES, NEVER A NAME LOOKUP ──
#   ROOT edge   `rootLock.nodes[root].inputs.<name>`
#                 — what a consumer resolves for `gen.inputs.<name>`
#   CI   edge   `ciLock.nodes[ ciLock.nodes[root].inputs.gen ].inputs.<name>`
#                 — what `inputs.gen.inputs.<name>` resolves to inside ci's evaluation
# Both resolved through `follows`, compared on `locked.rev`.
#
# ★ `lock.nodes.<label>` IS NEVER INDEXED. A lock routinely carries `X` and `X_2` for one library at
# DIFFERENT revisions, and the bare index returns whichever was minted first, at exit 0 — this
# project's silent-and-plausible defect class living inside nix's own artefact.
#
# ★★ AND THE PREDICATE IS NOT MULTIPLICITY-SHAPED. `gen-prelude` carried 46 nodes under its label at
# gen `4edc4bb` and 3 at `76093b7`; `gen-types` went 8 → 1. Neither move had anything to do with pin
# agreement — the hub was relocked. A predicate whose correctness needs multiplicity 1
# (`distinctUnder`, `countUnder … == 1`, across-lock set equality) is therefore red or green on
# relock churn orthogonal to what it tests. Two edges are invariant under multiplicity at every value
# the hub has ever held — and under the stronger ground as well: nix does not merge two inputs
# reached via different declaration paths, emitting `X` and `X_2` even when their `original` objects
# are byte-identical and their `locked.rev` equal, so a multiplicity-1 predicate is wrong ALWAYS and
# not merely unstable.
#
# ── THE DOMAIN IS THE ROSTER OF RECORD, MAPPED INTO THE INPUT NAMESPACE ──
# ADR-0015: `mkGenLibs` "is the roster of record, never a count". The in-domain names are its member
# keys mapped through `"gen-" + k`, minus `strata` and minus the declared exclusion. Taken from the
# roster, never from the lock — a lock-derived domain would take its extent from the very artefact it
# is meant to hold to account, and a hard-coded name list would have gone stale this arc when
# `gen-resolve` left the roster and the domain went 22 → 21.
#
# ★★★ THE MAP IS THE LOAD-BEARING STEP AND NOT A FORMALITY: THE ROSTER'S KEYS ARE BARE.
# `lib/mkGenLibs.nix` binds `prelude = (input "gen-prelude").lib;`, so the `gen-` string lives only
# inside the INPUT NAME and never in the member key. A domain written as "the `gen-`-prefixed members
# of `mkGenLibs { }`" is THE EMPTY SET — and an empty domain reads `agree = true` on every input,
# which is the silent wrong answer this whole carrier exists to remove. `domain-from-roster` below is
# the arm that refuses it, and it is armed on that exact spelling.
#
# ── WHAT A GREEN MEANS, AND WHAT IT DOES NOT ──
# That the two locks resolve the same revision for each roster member AT THE HUB'S DIRECT EDGES. It
# says nothing one level down: the hub-edge nodes' own inputs were measured to agree (41 second-level
# edges, 0 disagreements, gen `76093b7`, with a live control that reports 3 disagreements on
# deliberately mismatched nodes) but that is a reading of a moment and not a construction. If this
# cell ever reads green against a real divergence, the second level is the first thing to re-check.
{
  gen,
  lib,
}:
let
  roster = gen.lib.mkGenLibs { };

  # `strata` is an attribute of the roster and not a member of it — the same meta-key filter
  # `ci/sole-evaluator.nix` and `ci/direction-of-dependence.nix` apply, for the same reason.
  rosterMetaKeys = [ "strata" ];
  members = builtins.filter (k: !(builtins.elem k rosterMetaKeys)) (builtins.attrNames roster);

  # THE DECLARED EXCLUSION. `nixpkgs` is deduped by `gen.inputs.nixpkgs.follows` in `ci/flake.nix`
  # and legitimately differs between the two locks. It is subtracted from BOTH sides of the floor
  # below, so withdrawing the declaration moves both together — and it is why the `follows` limb
  # ships armed rather than dropped: withdrawing it is one edit, after which a follows edge enters
  # the domain and a limb that failed silently would reproduce this carrier's own defect one level
  # down.
  excluded = [ "nixpkgs" ];

  sorted = builtins.sort (a: b: a < b);
  without = xs: ys: sorted (builtins.filter (x: !(builtins.elem x ys)) xs);

  # ★★ THE MAP — see the header. Omitting it makes this the empty set.
  inDomain = without (map (k: "gen-" + k) members) excluded;

  # ── THE TRAVERSAL ──
  # `ci/sole-evaluator.nix`'s `lock` / `lockInputsOf` / `rootInputs` block, one dimension over: two
  # locks rather than one, and read as EDGES rather than as a name set. The root lock is reached at
  # `../flake.lock` the same way `ci/agents-md-hub-inputs.nix` reaches `../AGENTS.md`.
  readLock = p: builtins.fromJSON (builtins.readFile p);
  rootLock = readLock ../flake.lock;
  ciLock = readLock ./flake.lock;

  lockInputsOf =
    lock: node:
    if lock.nodes ? ${node} && lock.nodes.${node} ? inputs then lock.nodes.${node}.inputs else { };

  # Resolve one input of `node` to a node key. A direct edge IS the node key; a `follows` value is a
  # PATH LIST resolved segment by segment from that lock's own root.
  #
  # ★ THE LIMB IS DEAD IN PRODUCTION AND SHIPS ARMED. Measured at gen `76093b7`: 0 of the 21
  # in-domain names are follows-shaped on either side, and the only `follows` in either node is the
  # excluded `nixpkgs`. `follows-resolved` below fires on it.
  followingResolver =
    lock: node: inp:
    let
      v = (lockInputsOf lock node).${inp};
    in
    if builtins.isString v then
      v
    else
      builtins.foldl' (cur: seg: followingResolver lock cur seg) lock.root v;

  # The PRE-LIMB reader over the same objects — `ci/sole-evaluator.nix`'s `libOnlyWorld`
  # construction. `follows-resolved`'s control arm runs the SAME comparator with this resolver in
  # place of the one above, so the arm SHOWS the limb is load-bearing rather than asserting it. The
  # sentinel is a node key no lock holds, which `revIn` reads as an absent revision — so the stripped
  # reader cannot NAME the seeded divergence, which is exactly the arm's claim.
  directOnlyResolver =
    lock: node: inp:
    let
      v = (lockInputsOf lock node).${inp};
    in
    if builtins.isString v then v else "<unresolved-follows>";

  # ── THE COMPARATOR ──
  # Parameterised on the DOMAIN, the RESOLVER and the two lock VALUES, so every seeded world below
  # runs THIS code and not a copy of it. A second implementation would arm nothing.
  agreementOf =
    domain: resolve: rootLock_: ciLock_:
    let
      rootInputs = lockInputsOf rootLock_ rootLock_.root;
      rootGenEdges = without (builtins.filter (lib.hasPrefix "gen-") (builtins.attrNames rootInputs)) excluded;

      # REFUSAL 1 — ci's root node carries no `gen` edge. The unguarded construction throws
      # `error: attribute 'gen' missing`: true, useless, and indistinguishable from a typo here.
      hasCiGen = rootInputsOfCi ? gen;
      rootInputsOfCi = lockInputsOf ciLock_ ciLock_.root;
      ciGenNode = if hasCiGen then resolve ciLock_ ciLock_.root "gen" else null;
      ciGenInputs = if ciGenNode == null then { } else lockInputsOf ciLock_ ciGenNode;

      # REFUSAL 2 — the root lock carries no `gen-*` edge at all. A predicate that reaches nothing
      # reads as a held invariant; this names the reach instead of reporting the invariant.
      refusals =
        lib.optional (!hasCiGen)
          "ci/flake.lock: the root node carries no `gen` input — the hub edge this check walks does not exist"
        ++
          lib.optional (rootGenEdges == [ ])
            "flake.lock: the root node carries no `gen-*` input — every in-domain name would compare against nothing";

      onBothSides = n: rootInputs ? ${n} && ciGenInputs ? ${n};
      present = builtins.filter onBothSides domain;
      missing = without domain present;

      # REFUSAL 3 — `locked.rev` equality is NOT total. A node whose `locked` carries no `rev`
      # compares `null == null` ⇒ AGREES, silently. Latent at `76093b7` (the domain is 42/42
      # `type: "github"`, every one carrying a `rev`) but such nodes exist in these very locks — ci's
      # own `gen` node is `{"path":"..","type":"path"}` — so a roster member added as a `path:` or
      # tarball input would read silently-agree. It is a NAMED refusal, never an agreement.
      revIn = lock: key: if lock.nodes ? ${key} then lock.nodes.${key}.locked.rev or null else null;
      rootRev = n: revIn rootLock_ (resolve rootLock_ rootLock_.root n);
      ciRev = n: revIn ciLock_ (resolve ciLock_ ciGenNode n);

      unlocked = sorted (builtins.filter (n: rootRev n == null || ciRev n == null) present);
      differs = sorted (builtins.filter (n: !(builtins.elem n unlocked) && rootRev n != ciRev n) present);

      shown =
        has: rev: n:
        if !(has n) then
          "<absent>"
        else if rev n == null then
          "<unlocked>"
        else
          rev n;
    in
    {
      inherit
        domain
        missing
        differs
        unlocked
        refusals
        rootGenEdges
        ciGenNode
        ;
      agree = missing == [ ] && differs == [ ] && unlocked == [ ];
      rows = map (n: {
        name = n;
        root = shown (m: rootInputs ? ${m}) rootRev n;
        ci = shown (m: ciGenInputs ? ${m}) ciRev n;
      }) domain;
    };

  live = agreementOf inDomain followingResolver rootLock ciLock;

  # ── THE FLOOR, AS A PREDICATE OVER TWO INDEPENDENTLY MOVING OBJECTS ──
  # The roster-derived domain against the ROOT lock's own `gen-*` edge set, both differences empty —
  # and NON-EMPTY, which is the half that refuses the silent spelling. `[ ] == [ ]` is the reading an
  # empty domain gives for free, so a containment-only floor would pass there too.
  floorOf =
    domain: edges: domain != [ ] && without domain edges == [ ] && without edges domain == [ ];
  liveFloor = floorOf inDomain live.rootGenEdges;

  # ── THE ARMING ──
  # `agree == true` is an ABSENCE CLAIM, so it travels with seeds that FIRE in the same run and the
  # same instrument. Every seed below is a lock VALUE handed to the comparator above; nothing here
  # writes to a repository, and no seed is a second implementation of the predicate.
  #
  # ★★ AND EVERY ARM BELOW READS ITS SEED AT THE ROW, NEVER AS A SET DIFFERENCE AGAINST THE LIVE
  # READING. A seeded world is built ON TOP OF the live locks, so a REAL divergence rides into every
  # seed. Measured here, both failure modes in one session: an ABSOLUTE list (`differs == [x]`) goes
  # red on any live disagreement at all — seeding one live `gen-graph` divergence turned three arming
  # arms red while every guard was firing perfectly — and a SET DIFFERENCE against the live reading
  # fixes that but still goes red when the live divergence lands on the very name a seed uses, where
  # it subtracts to empty. Both are the same false signal: "the arming stopped firing" said of an
  # arming that is working, and both would weld the live reading to the instrument-integrity arms,
  # which is exactly what §4.1's one-line residue requires them not to be.
  #
  # The ROW carries the SEEDED REVISION, a value the live lock cannot produce, so these arms are
  # immune to the collision. `ci/sole-evaluator.nix` meets the same problem at tree granularity ("a
  # tree-level difference cannot see a plant in an already-refused tree") and answers it the same
  # way: go FINER, do not subtract.
  ciRowOf = result: n: (lib.findFirst (r: r.name == n) null result.rows).ci;

  liveCiGenNode = live.ciGenNode;
  liveCiGenNodeValue = ciLock.nodes.${liveCiGenNode};
  ciRootValue = ciLock.nodes.${ciLock.root};

  # A rev-only mutation is INVISIBLE — nix resolves by narHash and six arms of a prior round all
  # returned the identical derivation hash and read as a clean decisive result. These seeds move the
  # NODE an edge points at, which is what the comparator reads.
  seedRev = "0000000000000000000000000000000000000000";
  seedNodeAtRev = {
    locked = {
      rev = seedRev;
      type = "github";
    };
  };
  # A node whose `locked` carries NO `rev` — refusal 3's operand, the shape ci's own `gen` node has.
  seedNodeUnlocked = {
    locked = {
      path = "..";
      type = "path";
    };
  };

  # Rebuild ci's lock with the gen node's inputs, the root node's inputs and the node table rewritten
  # — one constructor, so a seed differs from the live object in exactly the field it names.
  seedCi =
    {
      nodes ? { },
      genInputs ? (i: i),
      rootInputs ? (i: i),
    }:
    ciLock
    // {
      nodes =
        ciLock.nodes
        // nodes
        // {
          ${ciLock.root} = ciRootValue // {
            inputs = rootInputs (lockInputsOf ciLock ciLock.root);
          };
          ${liveCiGenNode} = liveCiGenNodeValue // {
            inputs = genInputs liveCiGenNodeValue.inputs;
          };
        };
    };

  # The divergence seed and the missing-edge seed are the two RED rows of O-1. The second is
  # `den-hoag-duzn`'s real production defect re-seeded: ci's lock carried 19 `gen-*` edges to the
  # root's 20 and the hub's gate was red on a MISSING edge rather than on the divergence behind it.
  seedDivergedKey = "gen-select";
  seedMissingKey = "gen-link";
  seedFollowsKey = "gen-types";
  seedUnlockedKey = "gen-memo";

  seededDiverged = agreementOf inDomain followingResolver rootLock (seedCi {
    nodes."seed-diverged" = seedNodeAtRev;
    genInputs = i: i // { ${seedDivergedKey} = "seed-diverged"; };
  });

  seededMissingEdge = agreementOf inDomain followingResolver rootLock (seedCi {
    genInputs = i: removeAttrs i [ seedMissingKey ];
  });

  # O-2's operand: ci's `gen` node reaches the name through a FOLLOWS PATH, and ci's root gains the
  # target at a different revision. The divergence is reachable ONLY by walking that path.
  seedFollowsCi = seedCi {
    nodes."seed-follows" = seedNodeAtRev;
    genInputs = i: i // { ${seedFollowsKey} = [ seedFollowsKey ]; };
    rootInputs = i: i // { ${seedFollowsKey} = "seed-follows"; };
  };
  seededFollows = agreementOf inDomain followingResolver rootLock seedFollowsCi;
  seededFollowsDirectOnly = agreementOf inDomain directOnlyResolver rootLock seedFollowsCi;

  seededUnlockedRev = agreementOf inDomain followingResolver rootLock (seedCi {
    nodes."seed-unlocked" = seedNodeUnlocked;
    genInputs = i: i // { ${seedUnlockedKey} = "seed-unlocked"; };
  });

  seededNoCiGenEdge = agreementOf inDomain followingResolver rootLock (
    ciLock
    // {
      nodes = ciLock.nodes // {
        ${ciLock.root} = ciRootValue // {
          inputs = removeAttrs (lockInputsOf ciLock ciLock.root) [ "gen" ];
        };
      };
    }
  );

  # ── THE TWO SILENT-GREEN SEEDS, and they are the reason `domain-from-roster` exists ──
  # (a) THE ROOT LOCK STRIPPED. The roster still enumerates 21 names, so they all read MISSING and
  #     the cell is red. The REJECTED BUILD — the same comparator over a LOCK-DERIVED domain on the
  #     same stripped lock — reaches nothing and reads `agree = true`. Its return is computed beside
  #     the real one and asserted, because an arm that never evaluates the rejected build would pass
  #     under it too.
  strippedRootLock = rootLock // {
    nodes = rootLock.nodes // {
      ${rootLock.root} = rootLock.nodes.${rootLock.root} // {
        inputs = lib.filterAttrs (n: _: !(lib.hasPrefix "gen-" n)) (lockInputsOf rootLock rootLock.root);
      };
    };
  };
  lockDerivedDomain =
    lock:
    without (builtins.filter (lib.hasPrefix "gen-") (builtins.attrNames (lockInputsOf lock lock.root))) excluded;
  seededStrippedRoot = agreementOf inDomain followingResolver strippedRootLock ciLock;
  rejectedLockDerivedDomain =
    agreementOf (lockDerivedDomain strippedRootLock) followingResolver strippedRootLock
      ciLock;

  # (b) THE SPELLING. The domain written WITHOUT the map — "the `gen-`-prefixed members of
  #     `mkGenLibs { }`" — over the LIVE, HEALTHY locks. Both refusals stay silent because both locks
  #     are intact; the domain is simply empty, and the cell reads `agree = true` on every input.
  #     This is the one failure mode no other arm here can see.
  verbatimDomain = builtins.filter (lib.hasPrefix "gen-") members;
  seededVerbatimDomain = agreementOf verbatimDomain followingResolver rootLock ciLock;

  arming = {
    inherit
      seedDivergedKey
      seedMissingKey
      seedFollowsKey
      seedUnlockedKey
      ;
    # `named` — the seeded key appears in the list the seed targets; `ciRev` — the revision the
    # comparator actually READ for it on ci's side, which is the seed's own value and not one the
    # live lock can supply.
    seededDiverged = {
      inherit (seededDiverged) agree;
      named = builtins.elem seedDivergedKey seededDiverged.differs;
      ciRev = ciRowOf seededDiverged seedDivergedKey;
    };
    seededMissingEdge = {
      inherit (seededMissingEdge) agree;
      named = builtins.elem seedMissingKey seededMissingEdge.missing;
      ciRev = ciRowOf seededMissingEdge seedMissingKey;
    };
    seededFollows = {
      inherit (seededFollows) agree;
      named = builtins.elem seedFollowsKey seededFollows.differs;
      ciRev = ciRowOf seededFollows seedFollowsKey;
    };
    # The pre-limb reader over the IDENTICAL seed: it cannot name the divergence, because it cannot
    # walk the path — the edge reads as an absent revision instead of as a disagreement.
    seededFollowsDirectOnly = {
      named = builtins.elem seedFollowsKey seededFollowsDirectOnly.differs;
      ciRev = ciRowOf seededFollowsDirectOnly seedFollowsKey;
    };
    seededUnlockedRev = {
      inherit (seededUnlockedRev) agree;
      named = builtins.elem seedUnlockedKey seededUnlockedRev.unlocked;
      ciRev = ciRowOf seededUnlockedRev seedUnlockedKey;
    };
    seededNoCiGenEdge = {
      inherit (seededNoCiGenEdge) refusals missing;
    };
    seededStrippedRoot = {
      inherit (seededStrippedRoot) refusals missing agree;
      floor = floorOf inDomain seededStrippedRoot.rootGenEdges;
    };
    # THE REJECTED BUILD: a lock-derived domain on the same stripped lock reaches nothing and reads
    # as a held invariant. Asserted TRUE below — if it ever stopped returning the silent answer, the
    # arm that rejects it would no longer be about anything.
    rejectedLockDerivedDomain = {
      inherit (rejectedLockDerivedDomain) domain agree;
    };
    seededVerbatimDomain = {
      inherit (seededVerbatimDomain) domain agree;
      floor = floorOf verbatimDomain live.rootGenEdges;
    };
  };

  # Every key MUST be `true`. The check builder is handed `builtins.attrNames` of this rather than a
  # hand-kept list beside it: a second register would let an arm be added here and left out of the
  # enforced set — an unchecked arm that reads exactly like a passing one.
  gate = {
    # ★★★ O-1, THE READING — AND IT IS THE ONE ARM WHOSE DISPOSITION IS OWNER-OPEN (§4.1 of
    # `specs/2026-09-12-gen-hub-lock-agreement-predicate-spec.md`): whether pin coherence between the
    # root lock and ci's is a GATING red or an OBSERVATION. The cell computes the same value under
    # both arms; what the answer changes is ONE line in `mkLockAgreementCheck`
    # (`ci/flake.nix`) — whether a failure of THIS key exits 1 or prints. Every other key below gates
    # under both arms, because a guard that can no longer fire is not a passing guard in either
    # disposition.
    locks-agree = live.agree;

    # O-1's two RED rows, armed: a moved direct edge is NAMED in `differs` carrying the SEEDED
    # revision, and a deleted edge is NAMED in `missing` reading `<absent>`. Each arm reads the row,
    # so it says "the guard still fires" under a live disagreement — including one on its own key.
    arming-divergence =
      arming.seededDiverged.named
      && arming.seededDiverged.ciRev == seedRev
      && arming.seededMissingEdge.named
      && arming.seededMissingEdge.ciRev == "<absent>";

    # O-2 — the `follows` limb is load-bearing, shown by the same comparator reading the same seed
    # with the limb removed: the full reader walks the path to the seeded revision and NAMES the
    # divergence; the pre-limb reader reaches an unresolvable edge and cannot.
    follows-resolved =
      arming.seededFollows.named
      && arming.seededFollows.ciRev == seedRev
      && !arming.seededFollowsDirectOnly.named
      && arming.seededFollowsDirectOnly.ciRev == "<unlocked>";

    # ★★ O-5, THE FLOOR — and it is the arm to read first, because it is the only one whose failure
    # is SILENT. The domain is the roster of record and the root lock's own `gen-*` edges are the
    # second, independently moving object; both differences empty AND the domain non-empty. Armed on
    # all three of its failure modes: the unmapped spelling (empty domain over healthy locks, cell
    # green), a root lock that reaches nothing, and the rejected lock-derived build that takes its
    # extent from the artefact it is meant to hold to account.
    domain-from-roster =
      liveFloor
      && !arming.seededVerbatimDomain.floor
      && arming.seededVerbatimDomain.agree
      && arming.seededVerbatimDomain.domain == [ ]
      && !arming.seededStrippedRoot.floor
      && arming.seededStrippedRoot.agree == false
      && arming.rejectedLockDerivedDomain.agree;

    # §2.2's three refusals: a ci root with no `gen` edge, a root lock with no `gen-*` edge, and an
    # in-domain node carrying no `locked.rev`. Each is NAMED — a throw here is indistinguishable from
    # a typo in this file, and a `null == null` revision comparison is indistinguishable from
    # agreement.
    #
    # ★ `live.refusals == [ ]` belongs HERE and `live.unlocked` does NOT. A ci root with no `gen`
    # edge is a BROKEN INSTRUMENT and gates under both arms of §4.1; a roster member pinned without a
    # revision is a READING about the pins, so it sits inside `agree` and travels with `locks-agree`.
    edges-refused-by-name =
      live.refusals == [ ]
      && arming.seededNoCiGenEdge.refusals != [ ]
      && arming.seededNoCiGenEdge.missing == inDomain
      && arming.seededStrippedRoot.refusals != [ ]
      && arming.seededUnlockedRev.named
      && arming.seededUnlockedRev.ciRev == "<unlocked>";
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "revision agreement between the hub's ROOT `flake.lock` and `ci/flake.lock`, at the hub's DIRECT edges, over the roster of record";
    property = "what a consumer resolves for `gen.inputs.<name>` is what `inputs.gen.inputs.<name>` resolves to inside this CI flake's evaluation";
    observable = "`locked.rev` at two edges — `rootLock.nodes[root].inputs.<name>` and `ciLock.nodes[ciLock.nodes[root].inputs.gen].inputs.<name>` — each resolved through `follows`, never by indexing `lock.nodes.<label>`";
    direction = "EXACT at the hub's direct edges and SILENT one level down: the hub-edge nodes' own inputs are not compared, and were measured to agree at gen `76093b7` rather than shown to agree by construction";
    domainSource = "`gen.lib.mkGenLibs { }`'s member keys MAPPED through `\"gen-\" + k` (the roster's keys are BARE), minus `strata`, minus the declared exclusion — ADR-0015's roster of record, never a count and never the lock";

    inherit inDomain excluded;
    domainCount = builtins.length inDomain;
    rootGenEdges = live.rootGenEdges;
    floor = liveFloor;

    inherit (live)
      agree
      differs
      missing
      unlocked
      refusals
      ciGenNode
      rows
      ;

    inherit arming;
  };
}
