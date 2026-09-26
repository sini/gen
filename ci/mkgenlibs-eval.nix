# mkgenlibs-eval — the hub's own wiring smoke check.
#
# `gen.lib.mkGenLibs` is the PUBLISHED two-stage instantiation every consumer (den-hoag, the lib
# repos) reaches the ecosystem through. A bad pin bump or a lib whose `.lib` signature drifts breaks
# the wiring silently — no consumer catches it until their OWN eval throws. This forces every key of
# the hub's mkGenLibs so a broken wiring — or a dropped/added roster key — fails `nix flake check ./ci`.
#
# It also checks the STRATUM PARTITION: that every member declares a layer, that the published
# buckets carry exactly what the declaration assigns them, and that a bucket entry is the same VALUE
# as the flat member rather than a second evaluation of the same source.
#
# It also checks the PUBLISHED EXPORT SURFACE: the names each member publishes, fingerprinted per
# member and compared against a hand-maintained pin (`expectedSurface`). The forcing arms above catch
# a pin bump that THROWS; this one catches a pin bump that merely CHANGES — an export removed, added
# or renamed, or a member replaced by a different library, none of which breaks the wiring. The
# observable is names, never a rev/narHash/outPath, so a docs-only bump leaves the fingerprint
# byte-identical; a behaviour change under an unchanged export surface is outside this arm by
# construction, and the AGREEMENT arm above is what covers value identity.
#
# `gen` is the hub itself: its root flake, read at `self`'s own locked identity (ci/flake.nix), so
# its inputs are the root flake's resolved from the root `flake.lock`.
#
# ★ WHICH PINS THIS CHECK OBSERVES: the root `flake.lock`'s. `gen.inputs.gen-X` resolves through the
# root lock a consumer resolves, and ci holds no copy of it, so this fingerprints the surface
# consumers get by construction (den-hoag-lbtnv D1; the retired `lock-agreement` gated the copy).
{ gen }:
let
  genLibs = gen.lib.mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)
  actualKeys = builtins.attrNames genLibs;

  # The stratum declaration is an attribute of the roster but NOT a member of it, so every
  # member-ranging check below subtracts it. Without the subtraction the totality arm reports the
  # declaration as missing from every bucket — a red indistinguishable from a genuinely unassigned
  # library.
  declKey = "strata";
  memberKeys = builtins.filter (k: k != declKey) actualKeys;

  # The roster (lib/mkGenLibs.nix): its members plus the stratum declaration. A roster change is
  # intentional: bump this list in the SAME commit that adds/removes a lib, so this stays a tripwire
  # rather than silent drift. `extra` is every actual key absent from this list and cannot tell a
  # member from a declaration, so the declaration key is listed here too.
  expectedKeys = [
    "algebra"
    "assemble"
    "aspects"
    "bind"
    "class"
    "delivery"
    "dispatch"
    "graph"
    "identity"
    "inspect"
    "link"
    "memo"
    "merge"
    "prelude"
    "product"
    "program"
    "schema"
    "scope"
    "select"
    "settings"
    "strata"
    "types"
    "view"
  ];

  missing = builtins.filter (k: !(builtins.elem k actualKeys)) expectedKeys;
  extra = builtins.filter (k: !(builtins.elem k expectedKeys)) actualKeys;
  rosterOk = missing == [ ] && extra == [ ];

  # ── the retirement register ──
  #
  # A published member may carry a name that REFUSES TO FORCE — a deliberate throwing tombstone, whose
  # ground is that refusing the name means the call cannot be WRITTEN rather than being detected after
  # it is. The three forcing arms below deepSeq every published member, so such a name makes them
  # false. This register is how a tombstone becomes ADMITTED BY NAME, WITH ITS CAUSE AND ITS CARRIER,
  # while an UNREGISTERED throw still reds: each arm subtracts the registered bindings OF THAT MEMBER
  # and nothing else.
  #
  # It lives here rather than in a shared module because its consumers are all in this file — the same
  # reason `sole-evaluator.nix` keeps its own three ruled sets local to itself. Its shape follows that
  # file's `mkRuledSet` (key field plus `cause` plus `carrier`, REQUIRED, an entry missing one REFUSED
  # rather than admitted, and an asserted WIDTH) and `rehost-den-parity.nix`'s named exclusion axis,
  # whose stated counter-obligation — the excluded thing is still FORCED on both sides — is what
  # `retired-refusing` below is made of.
  #
  # AN ENTRY KEYS TO A BINDING — a `member` and the `binding` it publishes — AND NEVER TO A `file:line`.
  # A positional key is invalidated by the very act the register exists to survive: a pin bump moves
  # the lines in the file it would name.
  retirementEntries = [
    {
      member = "scope";
      binding = "buildNodes";
      cause = "a deliberate throwing tombstone for a retired constructor (gen-scope lib/build-nodes.nix, `── THE RETIRED NAME ──`). `buildRoots` returns `{ nodes, nodeOrder }` where this returned a bare node map, so a silent redirect would let every enumerating read answer `[ \"nodeOrder\" \"nodes\" ]` with no error: refusing the name means the call cannot be WRITTEN rather than being detected after it is";
      carrier = "OQ-1 of specs/2026-09-05-gen-hub-relock-migration-spec.md, ruled 2026-09-08";
    }
  ];
  # A GATE, not a notification: a lock bump must not be able to grow this set, because a tombstone
  # entering a published surface is a design decision and takes a ruling.
  retirementWidth = 1;

  ruledRetirement =
    let
      required = [
        "member"
        "binding"
        "cause"
        "carrier"
      ];
      checked = map (
        x:
        let
          missing' = builtins.filter (f: !(x ? ${f}) || x.${f} == "") required;
        in
        if missing' == [ ] then
          x
        else
          throw "mkgenlibs-eval: a retirement register entry (${x.member or "?"}.${x.binding or "?"}) omits required field(s): ${builtins.concatStringsSep ", " missing'}. An entry with no stated cause and no carrier is the unbounded allow-list this check refuses."
      ) retirementEntries;
    in
    if builtins.length checked == retirementWidth then
      checked
    else
      throw "mkgenlibs-eval: the retirement register holds ${toString (builtins.length checked)} entries; its ruled width is ${toString retirementWidth}. A further entry is a NEW RULING and takes this line with it.";

  retiredIn = k: map (e: e.binding) (builtins.filter (e: e.member == k) ruledRetirement);
  # `removeAttrs` on a NON-ATTRSET raises an error `tryEval` does not catch, so the unguarded form
  # aborts the whole check UNNAMED on exactly the input `surfaceOf`'s non-attrset branch exists to
  # NAME. `r == [ ]` is the identity for the unregistered members: their values reach the arms
  # untouched, and `agree` keeps comparing the same value against itself on both sides rather than two
  # fresh attrsets that can no longer exit early on pointer identity.
  minusRetired =
    k: v:
    let
      r = retiredIn k;
    in
    if r == [ ] then v else builtins.removeAttrs v r;

  # Force each key: deepSeq the lib's top-level attrset + values to WHNF — catches a broken import
  # wiring (missing dep arg, dep-signature drift) WITHOUT calling into each function. tryEval turns a
  # throw into `false`, so the check names WHICH key broke instead of aborting the whole eval. Forces
  # every ACTUAL key (not just the roster), so a newly-added broken key is exercised too. The key's
  # registered retirements are subtracted first; `removeAttrs` is lazy in the values it keeps, so the
  # narrowing itself evaluates nothing.
  wired = builtins.listToAttrs (
    map (k: {
      name = k;
      value = (builtins.tryEval (builtins.deepSeq (minusRetired k genLibs.${k}) true)).success;
    }) actualKeys
  );

  # ── the stratum partition ──

  strata = genLibs.${declKey};
  declaredKeys = builtins.attrNames strata;

  # The stratum values that publish a consumer path on the hub's `lib` output. `retiring` is a
  # declaration only — it names no bucket, so nothing selects it here.
  publishedStrata = [
    "substrate"
    "modules"
    "aspects"
    "framework"
  ];
  knownStrata = publishedStrata ++ [
    "retiring"
  ];

  # TOTALITY: every member declares a stratum, and every declaration names a member. Reported as
  # lists rather than a boolean, so a failure names the member instead of only denying.
  strataMissing = builtins.filter (k: !(builtins.elem k declaredKeys)) memberKeys;
  strataExtra = builtins.filter (k: !(builtins.elem k memberKeys)) declaredKeys;
  # A value outside the vocabulary is a non-declaration in effect: it names no bucket, so the member
  # would drop out of every published path silently rather than loudly.
  strataUnknown = builtins.filter (k: !(builtins.elem strata.${k} knownStrata)) declaredKeys;

  # The buckets as PUBLISHED — read off the hub's `lib` output, which is the surface a consumer
  # actually reaches, not a reconstruction of it here.
  buckets = builtins.listToAttrs (
    map (s: {
      name = s;
      value = gen.lib.${s};
    }) publishedStrata
  );
  bucketMembers = s: builtins.attrNames buckets.${s};
  declaredIn = s: builtins.filter (k: strata.${k} == s) declaredKeys;
  bucketPairs = builtins.concatMap (s: map (k: { inherit s k; }) (bucketMembers s)) publishedStrata;

  # The published buckets carry exactly the members the declaration assigns them.
  bucketMismatch = builtins.concatMap (
    s:
    (map (k: "${s}: missing ${k}") (
      builtins.filter (k: !(builtins.elem k (bucketMembers s))) (declaredIn s)
    ))
    ++ (map (k: "${s}: extra ${k}") (
      builtins.filter (k: !(builtins.elem k (declaredIn s))) (bucketMembers s)
    ))
  ) publishedStrata;

  # DISJOINTNESS: no member appears in two buckets.
  bucketOverlap = builtins.filter (
    k: builtins.length (builtins.filter (s: builtins.elem k (bucketMembers s)) publishedStrata) > 1
  ) memberKeys;

  # RESOLVE: force every member of every published bucket, the same deepSeq-under-tryEval
  # construction `wired` uses — and the same retirement narrowing — so a bucket path that throws
  # names the member.
  bucketResolve = builtins.listToAttrs (
    map (p: {
      name = "${p.s}.${p.k}";
      value = (builtins.tryEval (builtins.deepSeq (minusRetired p.k buckets.${p.s}.${p.k}) true)).success;
    }) bucketPairs
  );
  resolveFailed = builtins.filter (k: !bucketResolve.${k}) (builtins.attrNames bucketResolve);

  # AGREEMENT: a bucket entry is the same VALUE as the flat member, not a second evaluation of the
  # same source. This is the one property a names-and-types fingerprint cannot see — a library
  # re-imported at a different pin has identical names and identical types while being a different
  # build — so the arm compares values and tryEval keeps it total. The retirement narrowing is applied
  # to BOTH sides: removing it from one only would compare an attrset against one carrying an extra
  # name, and red every run.
  agree = builtins.listToAttrs (
    map (
      p:
      let
        t = builtins.tryEval (minusRetired p.k buckets.${p.s}.${p.k} == minusRetired p.k genLibs.${p.k});
      in
      {
        name = "${p.s}.${p.k}";
        value = t.success && t.value;
      }
    ) bucketPairs
  );
  agreeFailed = builtins.filter (k: !agree.${k}) (builtins.attrNames agree);

  # ── the register's own staleness gate ──
  #
  # Without this arm the register is precisely the unbounded allow-list it exists not to be: an entry
  # would go on forgiving a binding that had stopped throwing, or one that had left the surface
  # entirely, and nothing would say so. Per entry and per LOCUS — the flat member and every published
  # bucket path carrying it — the binding must be PRESENT and must still REFUSE TO FORCE.
  #
  # Presence is tested BEFORE the force, not through it: tryEval cannot tell a tombstone's throw from
  # a missing-attribute error, so a register entry naming a vanished binding would read as a refusal.
  # AND IT CANNOT TELL ONE THROW FROM ANOTHER EITHER — it returns { success = false; value = false; }
  # for every failure alike. This arm therefore admits *a refusal* at the registered locus, never
  # *this* refusal: if the binding ever stops being a tombstone and becomes a GENUINE wiring break at
  # the same name, it still throws, this reads green, and nothing says so. Closing that would need the
  # retired library to publish a FORCEABLE retirement marker — a value beside the tombstone rather
  # than a message inside it — which MOVES A PUBLISHED SURFACE and is not ruled. The bound is one case
  # wide and it is recorded here rather than left to be discovered.
  retirementAt =
    label: v: e:
    if !(builtins.isAttrs v) || !(v ? ${e.binding}) then
      [ "${label}: registered, and the binding is absent" ]
    else if (builtins.tryEval (builtins.deepSeq v.${e.binding} true)).success then
      [ "${label}: registered, and the binding forces cleanly" ]
    else
      [ ];

  # Ranges over every bucket the member sits in rather than assuming one: `buckets-disjoint` asserts
  # there is at most one, and an arm that ASSUMED it would go blind on exactly the run where that
  # assertion fails. The bucket locus is the one that needs this — `agree` now compares both sides
  # minus the registered bindings, so the bucket path's copy is no longer covered there.
  bucketPathsOf = k: builtins.filter (s: builtins.elem k (bucketMembers s)) publishedStrata;

  retirementFailed = builtins.concatMap (
    e:
    retirementAt "${e.member}.${e.binding}" (genLibs.${e.member} or null) e
    ++ builtins.concatMap (
      s: retirementAt "${s}.${e.member}.${e.binding}" (buckets.${s}.${e.member} or null) e
    ) (bucketPathsOf e.member)
  ) ruledRetirement;

  # ── the published export surface ──
  #
  # THE OBSERVABLE: the names each member PUBLISHES. `direction-of-dependence.nix` faced this same
  # choice for its own predicate and settled it — what it reads is `builtins.attrNames`, "never a
  # rev, a narHash or an outPath … the enforcement source is the DECLARATION, and parsing each
  # member's flake.nix from `outPath` would be the same predicate by another route." This arm takes
  # that observable one level in: not which inputs a member declares, but which names it publishes
  # through the two-stage instantiation every consumer reaches. An outPath/narHash witness would see
  # more and mean less — it reddens on a docs-only pin bump, so its red says "a lock moved" rather
  # than "a member changed meaning".
  #
  # A member whose `.lib` throws is already named by `wired`; here the tryEval keeps a throwing
  # member from aborting the whole eval unnamed, and gives it a surface value that cannot match a
  # pinned hash. The non-attrset branch does the same job for a member that stops being an attrset:
  # a shape change becomes a named drift rather than an uncaught `attrNames` error.
  surfaceOf =
    k:
    let
      t = builtins.tryEval (
        let
          v = genLibs.${k};
        in
        if builtins.isAttrs v then builtins.attrNames v else [ (builtins.typeOf v) ]
      );
    in
    if t.success then t.value else [ "<throws>" ];

  surface = builtins.listToAttrs (
    map (k: {
      name = k;
      value = surfaceOf k;
    }) memberKeys
  );

  # Hand-maintained on the SAME contract as `expectedKeys`: bump the moved member's line in the same
  # commit as the pin bump that moved it, so this stays a tripwire rather than silent drift. A member
  # with no entry drifts by construction (`or null`) — a new roster member is pinned or it is named,
  # never defaulted into agreement. Regenerate through THIS flake, which resolves every member from
  # the root `flake.lock`. The per-member value is `surfaceHashes.<key>`; the aggregate
  # `surfaceHash` is a different quantity and never belongs on a line here:
  #   nix eval ./ci#lib.mkGenLibsEval.surfaceHashes --raw --apply \
  #     'h: builtins.concatStringsSep "\n" (map (k: "    ${k} = \"${h.${k}}\";") (builtins.attrNames h))'
  #
  # ★ THE PRE-FLIGHT, ANSWERABLE BEFORE THE BUMP (den-hoag-w1tr4 OQ-5): whether a candidate member
  # revision moves that member's published name set AS THE HUB COMPOSES IT — a property of the two
  # revisions and the revs the hub injects around them, not of the commits between them and not of
  # the member's flake alone. 17 of the 21 members are plain re-exports (`x = (input "gen-X").lib`)
  # and for those a bare `#lib` eval agrees; FOUR are hub-wired (`program`, `delivery`, `class`,
  # `assemble` above) and a bare `#lib` eval is WRONG for all four: it throws on three ("expected a
  # set but found a function", their `.lib` IS the function the hub applies) and on `class` it
  # AGREES ON HASH WHILE READING A DIFFERENT OBJECT — the flake `.lib` leaves `merge = null`, the hub
  # re-imports with the tier-2 kernel injected, and the two name sets merely happen to agree today.
  # The form below reuses `lib/mkGenLibs.nix` itself rather than restating its wiring, so it is total
  # over all 21 and cannot drift from the wiring it tests:
  #
  #   nix eval --impure --raw --expr '
  #     let
  #       hub  = (builtins.getFlake "git+file://<clone>/gen?dir=ci").inputs.gen;
  #       cand = builtins.getFlake "git+file://<clone>/gen-<member>?rev=<newRev>";
  #       roster = import "${hub}/lib/mkGenLibs.nix" {
  #         genInputs = hub.inputs // { gen-<member> = cand; };
  #       } { };
  #     in builtins.hashString "sha256" (builtins.toJSON (builtins.attrNames roster.<key>))'
  #
  # Compare the result against `expectedSurface.<key>` below. Equal ⇒ free rider, no regeneration
  # owed. Differ ⇒ the bump carries the regenerated line in the SAME commit as the pin move — the
  # intermediate state (pin moved, line stale) must not exist in history, exactly like the
  # regeneration route above.
  expectedSurface = {
    # gen-algebra cacf36e81f → 3940d61654 (den-hoag-markof-partial-preimage-znfjq): the surface
    # gained FOUR names, `componentsPreimage`, `preimageTagOf`, `sealedCollisionEq` and
    # `sealedMarker`, a composite's per-component preimage tags and its by-name sealed-collision
    # refusal. Nothing was removed.
    # gen-algebra d017bc30b2 → 5a8d8d5362 (den-hoag-b7u1v): the surface LOST one name, `search`,
    # the retired Search-monad namespace (gen-scope is the sole evaluator, ADR-0008 §1). Nothing
    # was added.
    algebra = "574bd0dc735f14d4df6386d1928d9c9cc6cc3380445f4b5ce803e7c7b56e69d3";
    # gen-aspects → 7c983f45 (the lock-currency relock): the surface gained ONE name,
    # `hasClassContent`, the class-content predicate over an aspect. No other member moved.
    aspects = "5c3122bd668746dffa2e5e7e30aaac4978f54c5be4d74feadfa14c9375c07106";
    assemble = "fc9d7d15711aef75161972c90ae9ced3b8beb520d2dc381b1c4074df80169fac";
    bind = "b208c57ed918aed942c1a778aa2d321b78a7eba8a6bd5b9b518d3f74281e40bc";
    class = "82391568b8217b01fa44faa7fd359ae818591e5bb12ee4e954da59b33958b5a2";
    delivery = "8b0f007d723a6023c14af50860e247cf9f5aef7a51cd5c7f2cdf654add84f8ab";
    dispatch = "b6b0c94a150ba0aadad4a22c85c8f189b542592710ea51201f3d9151f8d00cc2";
    # gen-graph cfc2a90d7b → 00fe4bf4e9 (den-hoag-lock-currency-ruling-ez1yq, taken by the
    # lock-currency relock): the surface gained ONE name, `lowlink`, a third SCC-partition arm
    # (Tarjan's DFS iterated over a persistent trie) published beside `fbNode` and `fbWork`.
    # Nothing was removed and no other member moved.
    graph = "9946fde84fe482a80a4237de91d842b9f874f37070a354201c8d1b14e9d6de2b";
    identity = "ae39363fd50eb2100013362d3d43563146bf24fe8539675c8e8a944d62eaa201";
    # gen-inspect, the roster's 22nd member and the 4th at `framework`: the library that
    # interrogates a materialized graph. Its surface is 13 names — the IR construction and its
    # gen-graph wrapper, the three-route compile rule with its reserved set, the door, the copied
    # parser's two entry points, the executor's two, the selector API and the renderers.
    inspect = "f7d77bca2538837379cb3fe80c22a12a48e2e008d68625491dd8beff1b93875c";
    link = "90b36cc605f281fd7dd1d2dcf9af76c2fcf5cebdead79376b724ee2958e930a4";
    memo = "b7342e22fec4f96698e5a88a755635be782fb27e3f4c0f7868eb1a7cca2b6166";
    # gen-merge 3aa6dacca9 → 7516886fcc (the lock-currency relock): the surface gained ONE name,
    # `declaredOptions`, the declared-option reader over an evaluated module tree. Nothing was
    # removed and no other member moved.
    #
    # gen-merge 0e6340fdfa → 888872807c (den-hoag-u92up, taken by the lock-currency relock): the
    # surface gained ONE name, `mergeTypes`, the engine's type-merge relation published for a
    # consumer holding two types it did not build. Nothing was removed and no other member moved.
    #
    # gen-merge 88919f8 → 50250c1 (den-hoag-bfc0k): the surface gained ONE name, `closuresFirst`,
    # the comparison subject of a value that can carry a type record. Nothing was removed.
    merge = "fc9aa174dc8be63b816fe6a7ec1487ed839b14fcf8dd007aff55a2e7e013b54f";
    prelude = "b8cbf955917bd58ef8cfc78720762b88e704a9ba43623e603155cd7e128e400c";
    product = "cc0703f389878e902f295bbb155ac4121f7889ba2f0c9ff4d14c9de06545ffbe";
    program = "64b8889dcc0e5a41f98537e24baeb3ba3a879686dd573eaf422b217dd3859596";
    # gen-schema 88c41cb → 168cf21 (den-hoag-pgpg8): the surface gained ONE name,
    # `identityKeysForKind`, the kind-boundary identity-key derivation. Nothing was removed and no
    # other member moved.
    #
    # gen-schema f8e0e17 → 056ee9b (the inheritance relocation, step 4): the surface gained ONE
    # name, `evalSchema` (lib/eval-schema.nix, the staged pass that resolves kind `inherits` by
    # name against the frozen output of a strictly earlier pass). Nothing was removed and no other
    # member moved.
    #
    # gen-schema f207b53 → 8fb5b42 (den-hoag-markof-partial-preimage-znfjq): the surface gained
    # ONE name, `kindEq`, the kind comparison that refuses a sealed-only collision by name.
    # Nothing was removed.
    #
    # gen-schema c9c5cc9 → 4b4244a (den-hoag-bfc0k): the surface gained TWO names,
    # `constructionRelation` (the merge relation of a type built per construction) and
    # `keySemanticsRecords` (the record positions its keySemantics grammar fixes). Nothing was
    # removed.
    schema = "630c922c7753e554ef4ca06509214d5eec179d89cc2b29f41e05921dc0d1bd39";
    # gen-scope d24e0d983f → 41c7d9f5ea (den-hoag-wk8g8): the hub relock onto the four
    # declaration-bearing members moved this member's published surface.
    #
    # gen-scope e64c00719a → e355bb866a (den-hoag-n6dh7 Unit 1, the recursive NTA channel): the
    # surface gained FOUR names, `childDepth`, `decodeNta`, `flattenChildren` and `mintNtaId`.
    # Nothing was removed and no other member moved.
    scope = "09a4a0e6afa73fb847dca869add3572755a190edfae37a8641ae26eb8bbfe1c7";
    select = "4facb22f69e61b329635dd742728988aec7b2d8566c3559ddce6763fb6440ff6";
    settings = "4c1d7b6a85da8dc75591b591767da073b3baf25884f24c163a231eaccbfdef66";
    # gen-types 1542e47126 → c8ea733eba (den-hoag-z3nrc, taken by the lock-currency relock): the
    # surface gained ONE name, `identityGuard`, the step-indexed guard that bounds type nesting for
    # identity. Nothing was removed and no other member moved.
    types = "c65360ca4734e07b2e5a8992fad8237f4358400633f4a202e89ef26c5ba41754";
    # gen-view 2656d3cc38 → eccb0d2a78 (den-hoag-wk8g8): same relock, this member's published
    # surface also moved. `gen-bind` and `gen-select` moved in the same relock but are free
    # riders here — their hashes are unchanged, so no line for them was touched.
    view = "8096b4aa7fe96047a1ab49783c3cb90aaccb60742b6318fd00c740d61546d348";
  };

  # EXPORTED below, and that export is the only route that regenerates what this arm compares. It is
  # not on the report list: the report is what the derivation carries, this is what a maintainer
  # reads at eval time.
  surfaceHashes = builtins.listToAttrs (
    map (k: {
      name = k;
      value = builtins.hashString "sha256" (builtins.toJSON surface.${k});
    }) memberKeys
  );
  # ── THE PREDICATE ──
  #
  # Lifted to a function of its two inputs so a SEEDED world runs THIS code and not a copy of it.
  # That is the arming construction `direction-of-dependence.nix` states and `sole-evaluator.nix`
  # repeats, and this file was named by both as the one that lacked it.
  #
  # Reported as a LIST, so a failure names the member instead of only denying — the same shape
  # `resolveFailed` and `strataMissing` already take. `builtins.attrNames surf` is `memberKeys` on
  # the live call (`surface` is built from them) and the recomputed hash is `surfaceHashes.${k}`, so
  # the live reading is unchanged; the `or null` branch is preserved verbatim, because it is the arm
  # that keeps a new roster member from defaulting into agreement.
  driftOf =
    expected: surf:
    builtins.filter (
      k: (expected.${k} or null) != builtins.hashString "sha256" (builtins.toJSON surf.${k})
    ) (builtins.attrNames surf);

  surfaceDrift = driftOf expectedSurface surface;
  surfaceDriftNames = builtins.listToAttrs (
    map (k: {
      name = k;
      value = surface.${k};
    }) surfaceDrift
  );
  # The roll-up. It is in the report for a reason the drift list cannot serve: after an
  # ACKNOWLEDGED bump (surface moved, `expectedSurface` re-pinned in the same commit) the drift list
  # is empty again and the rest of the report is unchanged, so without this field the derivation
  # would be byte-identical across the very bump it just observed.
  surfaceHash = builtins.hashString "sha256" (builtins.toJSON surface);

  # ── the arming ──
  #
  # A FULLY SYNTHETIC fixture, built in the file that consumes it. No repository outside this file can
  # move it, and the arming is a GATE CELL, so the only way to disarm it is to edit the fixture and
  # editing the fixture reds the gate.
  #
  # It replaces a shell recipe in AGENTS.md that overrode `gen/gen-view` onto a fixed foreign rev.
  # That construction has two death modes, both observed: an override naming an input that has LEFT
  # the roster warns on stderr and returns a CLEAN GREEN (how the predecessor died when `gen-resolve`
  # was retired), and an override onto a rev the lock has REACHED is a no-op, so the control expires
  # the moment upstream stops diverging past it.
  #
  # ★ EACH ROW READS ITS OWN SEED AND NOTHING LIVE. Seeding the live `surface` instead was authored
  # and driven red: under a genuine drift the seeded list carries the live member too, so every
  # arming row goes false at once — spurious reds masking the one true red. The fixture is therefore
  # disjoint from `surface`, and a correct build that moves a real export surface cannot break these
  # greens; the only cell such a build moves is `surface-pinned`, which is the one that should move.
  armSurface = {
    alpha = [
      "one"
      "two"
    ];
    beta = [ "three" ];
  };
  armPin = builtins.mapAttrs (_: v: builtins.hashString "sha256" (builtins.toJSON v)) armSurface;
  arming = {
    # The positive control on the five refusals below: without it a `driftOf` that named EVERY
    # member would satisfy all five and the arming would certify a predicate that never agrees.
    clean = driftOf armPin armSurface;
    added = driftOf armPin (armSurface // { alpha = armSurface.alpha ++ [ "four" ]; });
    removed = driftOf armPin (armSurface // { alpha = [ "one" ]; });
    renamed = driftOf armPin (
      armSurface
      // {
        alpha = [
          "one"
          "TWO"
        ];
      }
    );
    reordered = driftOf armPin (
      armSurface
      // {
        alpha = [
          "two"
          "one"
        ];
      }
    );
    unpinned = driftOf (builtins.removeAttrs armPin [ "alpha" ]) armSurface;
  };

  # The one LIVE-COUPLED arm, and the predecessor's OTHER death mode expressed as a cell: a pin entry
  # left behind for a member that has LEFT the roster keeps `surfaceDrift` empty — the filter ranges
  # over the live members — while the pin and the roster have stopped talking about the same thing.
  pinDomain = builtins.attrNames expectedSurface;

  # ★ WHAT THE ARMING DOES NOT REACH, stated here rather than left to be discovered. It proves
  # `driftOf` DISCRIMINATES. It does not prove that `surface` reads the published exports of the
  # PINNED libraries: the `genLibs` → `surfaceOf` → `surface` half runs on every live evaluation but
  # has no falsifier, and `arming-pin-covers-roster` closes only its domain — a `surfaceOf` whose
  # `tryEval` started swallowing would still be silent. Closing the rest means parameterising this
  # check over its `genLibs` the way `direction-of-dependence.nix` is parameterised over its
  # strata/rank/exception/edge set, which restructures the entry and gives every sibling arm a seeded
  # twin. That is an OPEN FORK (OQ-1 of
  # specs/2026-09-12-gen-arming-control-headroom-spec.md, den-hoag-l2yh0), not a decision taken here.

  # ── the published vocabulary ──
  #
  # ADR-0035: no host, user, system, machine, service, cluster or their synonyms appear in gen's
  # types, kinds, labels, options, error text or documentation as anything but an example a
  # framework might declare. `surface-pinned` cannot see this class: it hashes each member's
  # top-level names, and a den word sits as readily in a nested export (`crossing.*`, `fixtures.*`)
  # or in a formal.
  #
  # THE POPULATION: every roster member plus the hub's own `compose`, walked through PLAIN attrsets
  # (not `_type`, option-type or functor sets) to depth 4, and the attrset formals of every function
  # met on that walk. ★ WHAT IT DOES NOT SEE, stated rather than left to be discovered: fields of a
  # record a function RETURNS, curried and functor formals, sets inside lists, `_type` sets, `name`
  # strings, error text, option descriptions and docs prose, and the hub flakeModule's option names.
  # A clean read here is a claim about the population above and nothing wider.
  #
  # TWO PREDICATES over each name, both lifted to functions of their inputs (the `driftOf`
  # construction) so the arming below runs THIS code:
  #   TOKEN — split at case boundaries and at non-alphanumerics, lower-cased, a token EQUAL to a
  #     word. Equality and not substring, because a substring cannot tell `hosted` or `hostKind`
  #     (the hosting node, ADR-0008) from `host` (the fleet object); where spelling and meaning part,
  #     the register below decides, never the tokenizer.
  #   SUBSTRING — case-insensitive, over the words with no gen homonym. It catches what the token
  #     split cannot: `NixOS` splits to `nix o s`, and a lower-case compound (`hostname`) is one
  #     token. `home`, `den` and `cluster` stay token-only, for `homomorphism`, `hidden` and graph
  #     clustering. A digit-suffixed word (`host1`) is one token and is not caught.
  vocabularyWords = [
    "host"
    "hosts"
    "user"
    "users"
    "system"
    "systems"
    "machine"
    "machines"
    "service"
    "services"
    "cluster"
    "clusters"
    "flake"
    "flakes"
    "nixos"
    "darwin"
    "home"
    "den"
    "fleet"
  ];
  vocabularySubstrings = [
    "nixos"
    "darwin"
    "hostname"
    "username"
  ];
  vocabularyDepth = 4;

  chars = s: builtins.genList (i: builtins.substring i 1 s) (builtins.stringLength s);
  lower = builtins.replaceStrings (chars "ABCDEFGHIJKLMNOPQRSTUVWXYZ") (
    chars "abcdefghijklmnopqrstuvwxyz"
  );
  tokensOf =
    name:
    builtins.filter (t: builtins.isString t && t != "") (
      builtins.split "[^a-z0-9]+" (
        lower (
          builtins.concatStringsSep "" (
            map (p: if builtins.isList p then " " + builtins.head p else p) (builtins.split "([A-Z])" name)
          )
        )
      )
    );
  wordsIn =
    name:
    builtins.filter (w: builtins.elem w vocabularyWords) (tokensOf name)
    ++ builtins.filter (w: builtins.length (builtins.split w (lower name)) > 1) vocabularySubstrings;

  vocabularyWalk =
    member: depth: p: v:
    let
      t = builtins.tryEval (builtins.typeOf v);
      kind = if t.success then t.value else "throws";
      at = builtins.concatStringsSep "." p;
      hits =
        at': name:
        map (word: {
          inherit member word;
          at = at';
        }) (wordsIn name);
      own = if p == [ ] then [ ] else hits at (builtins.elemAt p (builtins.length p - 1));
      formals =
        if kind == "lambda" then
          builtins.concatMap (f: hits "${at}:${f}" f) (builtins.attrNames (builtins.functionArgs v))
        else
          [ ];
      plain = kind == "set" && !(v ? _type) && !(v ? type && v ? check) && !(v ? __functor);
      names = builtins.tryEval (builtins.attrNames v);
      kids =
        if plain && depth < vocabularyDepth && names.success then
          builtins.concatMap (n: vocabularyWalk member (depth + 1) (p ++ [ n ]) v.${n}) names.value
        else
          [ ];
    in
    own ++ formals ++ kids;

  # One offender per (member, locus, word): a name the two predicates both catch is listed once.
  offendersOf =
    surf:
    builtins.attrValues (
      builtins.listToAttrs (
        map (o: {
          name = "${o.member}.${o.at} [${o.word}]";
          value = o;
        }) (builtins.concatMap (m: vocabularyWalk m 0 [ ] surf.${m}) (builtins.attrNames surf))
      )
    );
  admits = e: o: e.member == o.member && e.at == o.at && e.word == o.word;
  unregisteredOf =
    register: offenders: builtins.filter (o: !(builtins.any (e: admits e o) register)) offenders;
  # The `retirementAt` rule one arm over: an entry with no live offender is STALE, so the register
  # cannot outlive the name it admits.
  staleOf =
    register: offenders: builtins.filter (e: !(builtins.any (o: admits e o) offenders)) register;
  showOffender = o: "${o.member}.${o.at} [${o.word}]";
  showEntry = e: "${e.member}.${e.at} [${e.word}]";

  # Each entry is ADMITTED BY A CLAUSE OF LAW, never by its spelling, and keys to the exact
  # (member, locus, word): a later name sharing the word at any other locus is not admitted.
  vocabularyRegister = [
    {
      member = "bind";
      at = "mergeStrategy.systemWins";
      word = "system";
      clause = "meaning cut: the hosted module system's value wins (ADR-0027, amended 2026-09-17), not a fleet object (ADR-0035)";
    }
    {
      member = "settings";
      at = "assembleHost";
      word = "host";
      clause = "ADR-0017: `assembleHost` retires as a name, and the retirement's execution is deferred";
    }
    {
      member = "bind";
      at = "crossing.mkFlakeTerminal";
      word = "flake";
      clause = "HELD: the construction's disposition awaits the owner's re-affirmation of ADR-0027's agnosticism ruling and ADR-0031 F2 at this point of use (den-hoag-52hn7)";
    }
    {
      member = "bind";
      at = "crossing.mkFlakeTerminal:evalFlakeModule";
      word = "flake";
      clause = "HELD: as `crossing.mkFlakeTerminal` (den-hoag-52hn7)";
    }
    {
      member = "bind";
      at = "crossing.mkFlakeTerminal:systems";
      word = "systems";
      clause = "HELD: as `crossing.mkFlakeTerminal` (den-hoag-52hn7)";
    }
  ];

  vocabularySurface = builtins.removeAttrs genLibs [ declKey ] // {
    hub = {
      inherit (gen.lib) compose;
    };
  };
  vocabularyOffenders = offendersOf vocabularySurface;
  vocabularyUnregistered = map showOffender (unregisteredOf vocabularyRegister vocabularyOffenders);
  vocabularyStale = map showEntry (staleOf vocabularyRegister vocabularyOffenders);

  # ── the vocabulary arming ── a synthetic fixture, disjoint from the live surface.
  armVocab = {
    alpha = {
      mkHostThing = x: x;
      g = { userName }: userName;
      fromNixOS = 1;
      hostname = 1;
      ok = 1;
    };
  };
  armVocabClean = {
    alpha = {
      mkNodeThing = x: x;
      g = { nodeName }: nodeName;
      ok = 1;
    };
  };
  vocabularyArming = {
    planted = map showOffender (unregisteredOf [ ] (offendersOf armVocab));
    clean = map showOffender (unregisteredOf [ ] (offendersOf armVocabClean));
    stale = map showEntry (
      staleOf [
        {
          member = "alpha";
          at = "gone";
          word = "host";
        }
      ] (offendersOf armVocab)
    );
  };
in
{
  # Flat gate record for the check helper: each actual key → wiring-ok, plus the roster tripwire and
  # the stratum-partition arms.
  gate = wired // {
    roster-ok = rosterOk;
    strata-total = strataMissing == [ ] && strataExtra == [ ];
    strata-enum = strataUnknown == [ ];
    buckets-match = bucketMismatch == [ ];
    buckets-disjoint = bucketOverlap == [ ];
    buckets-resolve = resolveFailed == [ ];
    buckets-agree = agreeFailed == [ ];
    surface-pinned = surfaceDrift == [ ];
    # ARMING — the comparison itself, over the synthetic fixture. A failing key here is the arming
    # having stopped firing, and it is RED: a guard that can no longer refuse is not a passing guard.
    arming-drift-silent-on-agreement = arming.clean == [ ];
    arming-drift-names-added = arming.added == [ "alpha" ];
    arming-drift-names-removed = arming.removed == [ "alpha" ];
    arming-drift-names-renamed = arming.renamed == [ "alpha" ];
    arming-drift-names-reordered = arming.reordered == [ "alpha" ];
    arming-drift-names-unpinned = arming.unpinned == [ "alpha" ];
    # ARMING — the pin's DOMAIN, the half `surfaceDrift` cannot see.
    arming-pin-covers-roster = pinDomain == memberKeys;
    retired-refusing = retirementFailed == [ ];
    # ADR-0035 over the published names; the register admits by clause.
    surface-vocabulary = vocabularyUnregistered == [ ];
    vocabulary-register-live = vocabularyStale == [ ];
    # ARMING — the predicates themselves, over the synthetic fixture. The planted set carries one
    # hit per route: a camel-case token, a formal, and the two the token split cannot see.
    arming-vocabulary-names-planted =
      vocabularyArming.planted == [
        "alpha.fromNixOS [nixos]"
        "alpha.g:userName [user]"
        "alpha.g:userName [username]"
        "alpha.hostname [hostname]"
        "alpha.mkHostThing [host]"
      ];
    arming-vocabulary-silent-on-clean = vocabularyArming.clean == [ ];
    arming-vocabulary-names-stale = vocabularyArming.stale == [ "alpha.gone [host]" ];
  };
  gateKeys = actualKeys ++ [
    "roster-ok"
    "strata-total"
    "strata-enum"
    "buckets-match"
    "buckets-disjoint"
    "buckets-resolve"
    "buckets-agree"
    "surface-pinned"
    "arming-drift-silent-on-agreement"
    "arming-drift-names-added"
    "arming-drift-names-removed"
    "arming-drift-names-renamed"
    "arming-drift-names-reordered"
    "arming-drift-names-unpinned"
    "arming-pin-covers-roster"
    "retired-refusing"
    "surface-vocabulary"
    "vocabulary-register-live"
    "arming-vocabulary-names-planted"
    "arming-vocabulary-silent-on-clean"
    "arming-vocabulary-names-stale"
  ];
  # Raw, for `nix eval ./ci#lib.mkGenLibsEval --json | jq`.
  keyCount = builtins.length actualKeys;
  memberCount = builtins.length memberKeys;
  keys = actualKeys;
  inherit expectedKeys missing extra;
  # The arming's own readings, so a red names WHICH half failed in one look — the live comparison or
  # the fixture that proves it can refuse.
  inherit arming pinDomain;
  inherit
    strata
    strataMissing
    strataExtra
    strataUnknown
    bucketMismatch
    bucketOverlap
    resolveFailed
    agreeFailed
    retirementFailed
    ;
  # ALIASED, not restated: the report's `inherit (g)` list takes an attribute of this LITERAL name, and
  # the binding above is `ruledRetirement`. The register prints on every run, including a run where it
  # refuses nothing — an entry that stops being printed is one nobody retires.
  retirementRegister = ruledRetirement;
  inherit
    surfaceHash
    surfaceHashes
    surfaceDrift
    surfaceDriftNames
    vocabularyUnregistered
    vocabularyStale
    vocabularyArming
    ;
  vocabularyRegister = map (e: "${showEntry e}: ${e.clause}") vocabularyRegister;
  bucketCounts = builtins.listToAttrs (
    map (s: {
      name = s;
      value = builtins.length (bucketMembers s);
    }) publishedStrata
  );
}
