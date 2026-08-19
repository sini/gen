# direction-of-dependence — ADR-0015's enforcement half: the CI lint on the DIRECTION of dependence.
#
# ADR-0015 rules where stratum enforcement lives: ADR-0014 (only plain data crosses a gen↔gen
# boundary) PLUS a lint on the direction of dependence, and NEVER the lock graph. That ruling was
# made on measured ground — gen is already maximally separated at 23 repositories and that did not
# stop gen-schema re-exporting gen-merge's values, so packaging separation was tried and does not
# enforce the boundary. The ADR-0014 half landed with the deletion of gen-schema's seven verbatim
# re-exports; this file is the other half. The failure it guards is SILENT: a substrate-stratum
# library that acquires an aspects-stratum input produces no error, no red suite and no refusal — it
# evaluates.
#
# ── THE OBSERVABLE: DECLARED ROOT-FLAKE INPUT NAMES ──
# `declaredOf` is the ONE site that reads a member's input set, and what it reads is
# `builtins.attrNames` of it — never a rev, a narHash or an outPath. A pin bump that changes no
# declared name therefore changes no result here. The lock RESOLVES declared names to revisions;
# this predicate never reads what they resolved to, which is the distinction ADR-0015's ruling turns
# on: what the ADR forbids is buying enforcement with pin separation. Obtaining the names through
# the flake value is an implementation convenience — the enforcement source is the declaration, and
# parsing each member's flake.nix from `outPath` would be the same predicate by another route.
#
# The other two candidate observables are ruled out rather than overlooked. The lock graph is
# forbidden by the ADR. A lexical reading of each member's `lib/` tree is MEASURED VACUOUS at these
# pins: on non-comment lines there is not one resolved reference to a sibling library by repository
# name across all twenty members, because every sibling dependence arrives as an INJECTED FORMAL of
# the `lib` entry function. That vacuity is a measurement and not a property — it holds while the
# injected-formal convention holds — so the declared names are the primary observable either way.
#
# The limit of this observable, stated rather than left implicit: it sees a DECLARED dependence and
# cannot see a library that reaches a higher stratum through a formal its caller fills. That residue
# is ADR-0014's half of the enforcement, not this one's.
#
# ── THE TREE IT GOVERNS ──
# The HUB'S PINNED REVISIONS, not the working clones — the surface consumers actually get, which is
# the principle ci/mkgenlibs-eval.nix already states for the roster itself. A library whose working
# tree has drifted from its pin is governed at the pin, and the drift becomes visible when the pin
# moves.
#
# ── THE DOMAIN ──
# The roster of record, `gen/lib/mkGenLibs.nix`, never a count. Two consequences follow by
# construction rather than by exception: the HUB is outside the domain (`gen` is not a roster
# member, so a member-ranging predicate never reaches it — NO exception naming the hub is written,
# because an exception by name is what invites the next one), and OFF-ROSTER repositories are
# outside it too (they carry no stratum, so there is nothing to rank them against). Nested
# `examples/*/flake.nix` inputs dissolve the same way: a member's declared inputs are its ROOT
# flake's, so the repo-level pin cycles examples create are outside the domain WITHOUT an ignore
# rule — the arm that does not have to be maintained.
#
# ── NOTHING ON THE EDGE-SET PATH DISCARDS SILENTLY ──
# A lint against silent upward dependence that assembled its own edge set by quietly dropping what
# it did not recognise would fail in exactly the shape it exists to catch. So every declared input
# name lands in exactly ONE published class — an edge to a roster member, an off-roster gen
# repository, or a non-gen input — every class is counted, and `partition-total` asserts the three
# sum to what was declared. A lookup with no answer REPORTS rather than dying: a member the hub does
# not pin, a member with no declared input set and a member with no layer are each named. Where an
# absence would otherwise read as success the zero is printed as a zero.
#
# Accounted for and NAMED are different guarantees, and they go to different classes. The classes a
# reader must act on — refused, excepted, unranked, off-roster — are named edge by edge. The `ok`
# class is counted and NOT enumerated: a name there asks nothing of anyone, and 25 lines of legal
# edges on every run is the noise that gets output skimmed.
#
# ── WHAT THIS CHECK IS NOT ──
# Stratum TOTALITY (every member declares a layer) is ci/mkgenlibs-eval.nix's arm and stays there.
# Removing that arm must not turn this check red: a member with no layer is named here and its edges
# move to the unranked set. This check fails on the NEW property only.
{ gen }:
let
  roster = gen.lib.mkGenLibs { };
  trueStrata = roster.strata;

  # `strata` is an attribute of the roster and not a member of it. Any OTHER non-member attribute
  # the roster grows would be read as a member here — it would then carry no layer, and
  # `membersWithNoLayerDeclared` names it rather than letting it pass as a ranked member.
  rosterMetaKeys = [ "strata" ];
  members = builtins.filter (k: !(builtins.elem k rosterMetaKeys)) (builtins.attrNames roster);

  # "gen-schema" -> "schema"; a name not prefixed `gen-` -> null. The prefix test is the whole
  # difference between reading a declared gen edge and reading four characters off an unrelated
  # input name: without it `nix-flake` and `abc-types` both strip to roster member keys and become
  # edges their declarer never wrote.
  genKeyOf =
    n:
    if builtins.substring 0 4 n == "gen-" then
      builtins.substring 4 (builtins.stringLength n) n
    else
      null;

  # The hub's view of a member. Absent is a REPORTED state, not an empty edge list: a member the hub
  # does not pin contributes nothing, and saying nothing about it is the silence this lint refuses.
  hubInput = k: gen.inputs."gen-${k}" or null;
  membersNotPinned = builtins.filter (k: hubInput k == null) members;
  membersNoInputSet = builtins.filter (
    k:
    let
      i = hubInput k;
    in
    i != null && !(i ? inputs)
  ) members;

  # ★ THE SINGLE READ SITE OF A MEMBER'S INPUT SET, and it reads NAMES (see the header, oracle 8).
  trueDeclared =
    k:
    let
      i = hubInput k;
    in
    if i == null || !(i ? inputs) then [ ] else builtins.attrNames i.inputs;

  # ── THE PARTITION ──
  inputClass =
    n:
    let
      key = genKeyOf n;
    in
    if key == null then
      "non-gen"
    else if builtins.elem key members then
      "member"
    else
      "off-roster";

  inputsIn =
    declFn: c: k:
    builtins.filter (n: inputClass n == c) (declFn k);

  edgesOf =
    declFn:
    builtins.concatMap (
      k:
      map (n: {
        from = k;
        to = genKeyOf n;
      }) (inputsIn declFn "member" k)
    ) members;

  # An off-roster repository is neither refused nor silently exempted: it never becomes an edge —
  # it has no stratum to rank — and it is NAMED here, so the exclusion leaves a trace.
  offRosterOf =
    declFn:
    builtins.concatMap (
      k:
      map (n: "${k} declares ${n} — off-roster gen repository, no stratum") (
        inputsIn declFn "off-roster" k
      )
    ) members;

  nonGenOf =
    declFn: builtins.concatMap (k: map (n: "${k} declares ${n}") (inputsIn declFn "non-gen" k)) members;

  declaredCountOf = declFn: builtins.foldl' (a: k: a + builtins.length (declFn k)) 0 members;
  classifiedCountOf =
    declFn:
    builtins.length (edgesOf declFn)
    + builtins.length (offRosterOf declFn)
    + builtins.length (nonGenOf declFn);
  # Gated rather than thrown: a gate key prints BOTH counts and then takes the check red naming
  # `partition-total`, where a throw would take the eval down before the report a reader needs.
  partitionTotalOf = declFn: declaredCountOf declFn == classifiedCountOf declFn;

  trueEdges = edgesOf trueDeclared;

  # ── THE RANK ──
  # TOTAL over members: a member with no entry ranks null and lands in the unranked set BY NAME.
  layerOf = st: k: st.${k} or null;
  layerName =
    st: k:
    let
      s = layerOf st k;
    in
    if s == null then "no-layer-declared" else s;
  membersNoLayerIn = st: builtins.filter (k: layerOf st k == null) members;

  # THE RULED RELATION: the chain. ADR-0015's "S1 is the core" is a claim about the ARCHITECTURE,
  # and this lint does not soften it to a partial order to buy a passing check. `retiring` is a
  # lifecycle state and not a layer — ADR-0015 publishes four buckets and rules that `retiring`
  # publishes none — so it ranks null and its edges are unrankable rather than legal.
  chain =
    s:
    if s == "substrate" then
      0
    else if s == "modules" then
      1
    else if s == "aspects" then
      2
    else if s == "framework" then
      3
    else
      null;

  # ── THE RULED EXCEPTION ──
  # Closed at exactly two edges, keyed by EDGE and never by member, so no member is exempt: an
  # upward edge out of gen-schema to a member this list does not name is refused. This is NOT the
  # per-member allow-list the spec refutes — that shape had neither a cause nor a retirement
  # condition, so nothing bounded it and nothing retired it, and it grew by an edit each round.
  # Each entry here MUST state its cause and its retirement carrier, an entry that cannot name both
  # is refused rather than admitted, and the width is asserted against the ruling — an appended
  # third entry takes this check red at the line naming the ruling it would have to change.
  #
  # ★ THE TWO EDGES DO NOT SHARE A CAUSE. Reading them as one cause misattributes the second, and
  # they retire independently: neither carrier discharges the other's edge.
  ruledExceptionEntries = [
    {
      from = "schema";
      to = "merge";
      cause = "option/type vocabulary: gen-schema declares kinds whose fields are options, so it needs the module system's vocabulary to say what a field is. Measured at gen-schema 87f54bd: of 45 calls through the injected merge formal, 40 are merge.types.*/mkOption/mkOptionType and merging semantics proper is 2. gen-schema is substrate BY ROLE and written in modules' language";
      retirementCarrier = "den-hoag-b91m";
    }
    {
      from = "schema";
      to = "types";
      cause = "declared for gen-merge's benefit, not consumed by gen-schema: the library entry takes prelude, merge and algebra, and gen-types is never injected into it; the standalone non-flake entry fetches gen-types only to construct gen-merge's own types argument";
      retirementCarrier = "den-hoag-iogq";
    }
  ];

  requiredExceptionFields = [
    "from"
    "to"
    "cause"
    "retirementCarrier"
  ];

  # The owner ruling of 2026-08-18 admits EXACTLY these edges. Changing this number in EITHER
  # direction is a ruling-visible act, not an edit: widening it is a new ruling, and narrowing it on
  # a landed retirement is the ruling admitting fewer than it did.
  ruledExceptionWidth = 2;

  mkException =
    entries:
    let
      checked = map (
        x:
        let
          missing = builtins.filter (f: !(x ? ${f}) || x.${f} == "") requiredExceptionFields;
        in
        if missing == [ ] then
          x
        else
          throw "direction-of-dependence: an exception entry (${x.from or "?"} -> ${x.to or "?"}) omits required field(s): ${builtins.concatStringsSep ", " missing}. An exception with no stated cause and no retirement carrier is the unbounded allow-list this check refuses."
      ) entries;
    in
    if builtins.length checked == ruledExceptionWidth then
      checked
    else
      throw "direction-of-dependence: the exception set holds ${toString (builtins.length checked)} entries; the ruling of 2026-08-18 admits exactly ${toString ruledExceptionWidth}. A further entry is a NEW RULING and takes this line with it.";

  ruledException = mkException ruledExceptionEntries;

  covers = exc: e: builtins.any (x: x.from == e.from && x.to == e.to) exc;

  edgeName = st: e: "${e.from}(${layerName st e.from}) -> ${e.to}(${layerName st e.to})";

  # ── THE PREDICATE ──
  # Parameterised over its strata, its rank, its exception set and its edge set, so a seeded world
  # runs THIS code and not a copy of it. That is the arming construction, and it is a deliberate
  # difference from ci/mkgenlibs-eval.nix, which reads `gen.lib` directly and cannot be armed.
  classify =
    st: rank: exc: e:
    let
      a = rank (layerOf st e.from);
      b = rank (layerOf st e.to);
    in
    if a == null || b == null then
      "unranked"
    else if a < b then
      (if covers exc e then "excepted" else "refused")
    else
      "ok";

  pick =
    c: st: rank: exc: edges:
    map (edgeName st) (builtins.filter (e: classify st rank exc e == c) edges);
  refusals = pick "refused";

  # Every class is seeded at zero, so a count of none is PRINTED rather than being an absent key.
  # The class that matters most here is the one that reads zero on a clean run.
  classes = [
    "refused"
    "ok"
    "excepted"
    "unranked"
  ];
  tally =
    st: rank: exc: edges:
    builtins.foldl'
      (
        acc: e:
        let
          c = classify st rank exc e;
        in
        acc // { ${c} = acc.${c} + 1; }
      )
      (builtins.listToAttrs (
        map (c: {
          name = c;
          value = 0;
        }) classes
      ))
      edges;

  # ── THE EXCEPTION REPORT ──
  # Reported entry by entry on EVERY run and never suppressed, with the cause and the carrier a
  # reader needs in order to act on it, including on a run where it refuses nothing — an exception
  # that stops being printed is one nobody retires. An entry that has stopped firing is the
  # retirement signal for ITS OWN carrier.
  #
  # "no longer declared" and "no longer upward" are STALE; an endpoint that acquires the `retiring`
  # lifecycle is INDETERMINATE and not stale, because nothing was fixed and a stale reading there
  # would retire the exception on a lifecycle change.
  exceptionReportOf =
    st: edges: exc:
    map (
      x:
      let
        e = {
          inherit (x) from to;
        };
      in
      {
        edge = edgeName st e;
        inherit (x) cause retirementCarrier;
        status =
          if !(builtins.any (t: t.from == x.from && t.to == x.to) edges) then
            "STALE — edge no longer declared"
          else if classify st chain [ ] e == "refused" then
            "active"
          else if classify st chain [ ] e == "unranked" then
            "INDETERMINATE — an endpoint carries no layer"
          else
            "STALE — edge is no longer upward";
      }
    ) exc;

  statusesOf = report: map (r: r.status) report;

  # ── THE ARMING (in tree, at introduction) ──
  # `refused == [ ]` on the true tree is an ABSENCE CLAIM, so it travels with live controls in the
  # same run and in the same instrument. Each arm below is the identical predicate over a seeded
  # world; each must FIRE, and each fires on a different axis of the construction.

  # Axis 1 — the EDGE SET. Two upward edges at DIFFERENT rank gaps (one arm can pass on an
  # accidentally narrow predicate), plus one out of the excepted member to a target the exception
  # does not name, which is what separates a two-edge exception from a member exemption.
  seedAspects = trueEdges ++ [
    {
      from = "prelude";
      to = "aspects";
    }
  ];
  seedFramework = trueEdges ++ [
    {
      from = "graph";
      to = "settings";
    }
  ];
  seedSchemaOther = trueEdges ++ [
    {
      from = "schema";
      to = "aspects";
    }
  ];

  # Axis 2 — the RANK. Inverting the chain must refuse the edges that run DOWN it. Without this the
  # `refused: 0` verdict is consistent with a rank function that ranks nothing at all.
  inverted =
    s:
    let
      r = chain s;
    in
    if r == null then null else 3 - r;

  # Axis 3 — the STRATA. A member's layer removed: the check must stay GREEN, name the member, and
  # move its edges into the unranked set. `merge` is the seed because it carries ranked edges in
  # both directions AND is an endpoint of a ruled exception, so the same arm exercises the
  # INDETERMINATE branch of the exception report.
  seedNoLayerMember = "merge";
  seedStrata = builtins.removeAttrs trueStrata [ seedNoLayerMember ];
  seedStrataTouched = builtins.filter (
    e: e.from == seedNoLayerMember || e.to == seedNoLayerMember
  ) trueEdges;
  seedStrataTouchedRankedBefore = builtins.filter (
    e: classify trueStrata chain ruledException e != "unranked"
  ) seedStrataTouched;
  seedStrataTouchedUnrankedAfter = builtins.filter (
    e: classify seedStrata chain ruledException e == "unranked"
  ) seedStrataTouched;

  # Axis 4 — the EXCEPTION SET. An uncaused entry, an uncarried entry and an appended third must
  # each be refused; the ruled set itself must be ACCEPTED, which is the positive control that
  # makes those three refusals readings rather than a broken constructor.
  accepts = entries: (builtins.tryEval (builtins.deepSeq (mkException entries) true)).success;
  seedUncaused = [
    (builtins.removeAttrs (builtins.elemAt ruledExceptionEntries 0) [ "cause" ])
    (builtins.elemAt ruledExceptionEntries 1)
  ];
  seedUncarried = [
    (builtins.elemAt ruledExceptionEntries 0)
    (builtins.removeAttrs (builtins.elemAt ruledExceptionEntries 1) [ "retirementCarrier" ])
  ];
  seedThirdEntry = ruledExceptionEntries ++ [
    {
      from = "prelude";
      to = "aspects";
      cause = "a third entry appended by edit rather than by ruling";
      retirementCarrier = "den-hoag-none";
    }
  ];

  # Axis 5 — the DECLARED INPUT SET. An off-roster gen repository must be NAMED and must become no
  # edge. There are none at these pins, so the live figure is a zero and this arm is what makes the
  # zero a reading. `gen-demand` is the precedent: orphaned for reference under ADR-0008 §4.
  seedOffRosterInput = "gen-demand";
  seedOffRosterMember = "prelude";
  seedOffRosterDeclared =
    k: trueDeclared k ++ (if k == seedOffRosterMember then [ seedOffRosterInput ] else [ ]);

  # Axis 6 — the STALE branch of the exception report, which the live tree cannot exercise while
  # both entries are active.
  seedExceptionStale = builtins.filter (e: !(e.from == "schema" && e.to == "merge")) trueEdges;

  # ── THE VERDICTS ──
  ruledRefused = refusals trueStrata chain ruledException trueEdges;
  ruledExcepted = pick "excepted" trueStrata chain ruledException trueEdges;
  chainOnlyRefused = refusals trueStrata chain [ ] trueEdges;
  unrankedEdges = builtins.filter (
    e: classify trueStrata chain ruledException e == "unranked"
  ) trueEdges;
  unranked = map (edgeName trueStrata) unrankedEdges;

  invertedRefused = refusals trueStrata inverted [ ] trueEdges;
  seededNoLayerRefused = refusals seedStrata chain ruledException trueEdges;
  seededNoLayerReport = exceptionReportOf seedStrata trueEdges ruledException;
  seededStaleReport = exceptionReportOf trueStrata seedExceptionStale ruledException;

  offRoster = offRosterOf trueDeclared;
  nonGen = nonGenOf trueDeclared;
  seededOffRoster = offRosterOf seedOffRosterDeclared;

  arming = {
    # The live control on every arm below: the identical predicate on the true tree.
    liveControl = ruledRefused;
    seededAspects = refusals trueStrata chain ruledException seedAspects;
    seededFramework = refusals trueStrata chain ruledException seedFramework;
    seededSchemaOther = refusals trueStrata chain ruledException seedSchemaOther;
    seededInvertedRank = invertedRefused;
    seededNoLayer = {
      member = seedNoLayerMember;
      refused = seededNoLayerRefused;
      named = membersNoLayerIn seedStrata;
      edgesRankedBefore = map (edgeName trueStrata) seedStrataTouchedRankedBefore;
      edgesUnrankedAfter = map (edgeName seedStrata) seedStrataTouchedUnrankedAfter;
      exceptionStatuses = statusesOf seededNoLayerReport;
    };
    seededException = {
      ruledSetAccepted = accepts ruledExceptionEntries;
      uncausedAccepted = accepts seedUncaused;
      uncarriedAccepted = accepts seedUncarried;
      thirdEntryAccepted = accepts seedThirdEntry;
    };
    seededOffRoster = {
      declaration = seededOffRoster;
      edgeCountUnchanged = builtins.length (edgesOf seedOffRosterDeclared) == builtins.length trueEdges;
      partitionStillTotal = partitionTotalOf seedOffRosterDeclared;
    };
    seededExceptionStale = statusesOf seededStaleReport;
  };

  # A seeded arm counts as fired only when it names EXACTLY the planted edge — a count alone would
  # pass on an arm that refused the whole tree.
  firesOn = seeded: name: seeded == [ name ];

  # Every key MUST be true. The check builder is handed `builtins.attrNames` of this rather than a
  # hand-kept list beside it: a second register would let an arm be added here and left out of the
  # enforced set — an unchecked arm that reads exactly like a passing one.
  gate = {
    # THE LINT ITSELF.
    no-upward-edge = ruledRefused == [ ];
    # The edge-set path accounted for in full (the three classes sum to what was declared).
    partition-total = partitionTotalOf trueDeclared;
    # The exception is what moves the two edges — not a hole in the rank function.
    exception-covers-chain-refusals = ruledExcepted == chainOnlyRefused && chainOnlyRefused != [ ];

    # ARMING — axis 1, the edge set.
    arming-upward-aspects = firesOn arming.seededAspects "prelude(substrate) -> aspects(aspects)";
    arming-upward-framework = firesOn arming.seededFramework "graph(substrate) -> settings(framework)";
    arming-exception-keyed-by-edge = firesOn arming.seededSchemaOther "schema(substrate) -> aspects(aspects)";
    # ARMING — axis 2, the rank.
    arming-rank-inverted = invertedRefused != [ ];
    # ARMING — axis 3, the strata. Green, named, and the edges moved — this check fails on the NEW
    # property only, so a missing layer is ci/mkgenlibs-eval.nix's red and not this one's.
    arming-no-layer-stays-green = seededNoLayerRefused == [ ];
    arming-no-layer-names-member = arming.seededNoLayer.named == [ seedNoLayerMember ];
    arming-no-layer-moves-edges =
      seedStrataTouchedRankedBefore != [ ]
      && builtins.length seedStrataTouchedUnrankedAfter == builtins.length seedStrataTouched;
    arming-exception-indeterminate = builtins.elem "INDETERMINATE — an endpoint carries no layer" arming.seededNoLayer.exceptionStatuses;
    # ARMING — axis 4, the exception set. The acceptance of the ruled set is the positive control
    # on the three refusals beside it.
    arming-exception-ruled-set-accepted = arming.seededException.ruledSetAccepted;
    arming-exception-refuses-uncaused = !arming.seededException.uncausedAccepted;
    arming-exception-refuses-uncarried = !arming.seededException.uncarriedAccepted;
    arming-exception-refuses-third-entry = !arming.seededException.thirdEntryAccepted;
    # ARMING — axis 5, the declared input set. The live off-roster figure is a zero; this is what
    # makes it a reading.
    arming-off-roster-named =
      seededOffRoster == [
        "${seedOffRosterMember} declares ${seedOffRosterInput} — off-roster gen repository, no stratum"
      ]
      && arming.seededOffRoster.edgeCountUnchanged
      && arming.seededOffRoster.partitionStillTotal;
    # ARMING — axis 6, the exception report's STALE branch.
    arming-exception-stale-branch = builtins.elem "STALE — edge no longer declared" arming.seededExceptionStale;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  # The report, printed on every run. `ok` is counted and not enumerated; every class a reader must
  # act on is named edge by edge.
  report = {
    governs = "the hub's pinned library revisions, not the working clones";
    observable = "declared root-flake input NAMES — no revision is read";
    relation = "substrate < modules < aspects < framework";

    memberCount = builtins.length members;
    edgeCount = builtins.length trueEdges;
    declaredInputCount = declaredCountOf trueDeclared;
    classifiedInputCount = classifiedCountOf trueDeclared;

    ruled = tally trueStrata chain ruledException trueEdges;
    inherit ruledRefused ruledExcepted;

    # The chain WITHOUT the exception: the arm that identifies which edges the exception covers.
    chainOnly = tally trueStrata chain [ ] trueEdges;
    inherit chainOnlyRefused;

    exceptionWidthRuled = ruledExceptionWidth;
    exceptionCount = builtins.length ruledException;
    exceptionReport = exceptionReportOf trueStrata trueEdges ruledException;

    inherit unranked;
    unrankedCount = builtins.length unrankedEdges;
    unrankedByMember = builtins.listToAttrs (
      map (k: {
        name = k;
        value = builtins.length (builtins.filter (e: e.from == k || e.to == k) unrankedEdges);
      }) (builtins.filter (k: chain (layerOf trueStrata k) == null) members)
    );
    # The per-member counts partition the unranked set only while this is zero.
    unrankedBothEndpointsUnrankable = builtins.length (
      builtins.filter (
        e: chain (layerOf trueStrata e.from) == null && chain (layerOf trueStrata e.to) == null
      ) unrankedEdges
    );

    inherit offRoster nonGen;
    offRosterCount = builtins.length offRoster;
    nonGenCount = builtins.length nonGen;
    # The hub is outside the domain BY CONSTRUCTION — `gen` is not a roster member, so a
    # member-ranging predicate never reaches it and no exception names it. Published with a live
    # control on the same predicate, because an absence read off an empty membership test would
    # look identical to this one.
    hubOutsideDomain = {
      hubIsRosterMember = builtins.elem "gen" members;
      control_schemaIsRosterMember = builtins.elem "schema" members;
    };
    membersNotPinnedAtHub = membersNotPinned;
    membersWithNoInputSet = membersNoInputSet;
    membersWithNoLayerDeclared = membersNoLayerIn trueStrata;

    # Stated beside the figures rather than left for the reader to reconstruct.
    excludedAxis = "the unranked set — edges with a `retiring` endpoint, which no relation over the four published buckets ranks — and any off-roster declaration, which carries no stratum. Both are counted and named above.";

    inherit arming;
  };
}
