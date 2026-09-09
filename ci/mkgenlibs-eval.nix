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
# `gen` is the hub itself (`path:..`) — the ci subflake can't `import ../lib` (escapes its flake root),
# so it reaches the root lib through an input, exactly like den-hoag's ci reaches den-hoag. This checks
# the ROOT flake.lock pins — the surface consumers actually get via `gen.lib.mkGenLibs`.
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
  # never defaulted into agreement. Regenerate through THIS flake — the arm compares what the ci
  # subflake's own `gen-*` nodes resolve to, and a command run against the root flake reads a
  # different lock:
  #   nix eval ./ci#lib.mkGenLibsEval.surfaceHashes --raw --apply \
  #     'h: builtins.concatStringsSep "\n" (map (k: "    ${k} = \"${h.${k}}\";") (builtins.attrNames h))'
  expectedSurface = {
    algebra = "3a484271b71a218419181bc5ce55cf593ab814e9abeab0914c5658532995bf86";
    aspects = "a51fb019bf402c246739f034649e1d09e890757f01cc8f6a12857753b2a2f107";
    assemble = "fc9d7d15711aef75161972c90ae9ced3b8beb520d2dc381b1c4074df80169fac";
    bind = "b208c57ed918aed942c1a778aa2d321b78a7eba8a6bd5b9b518d3f74281e40bc";
    class = "82391568b8217b01fa44faa7fd359ae818591e5bb12ee4e954da59b33958b5a2";
    delivery = "8b0f007d723a6023c14af50860e247cf9f5aef7a51cd5c7f2cdf654add84f8ab";
    dispatch = "b6b0c94a150ba0aadad4a22c85c8f189b542592710ea51201f3d9151f8d00cc2";
    graph = "bc24315b9783c2f1a6db815bb1668b6d3f0135c87c181af99161abcecad133cf";
    identity = "ae39363fd50eb2100013362d3d43563146bf24fe8539675c8e8a944d62eaa201";
    link = "90b36cc605f281fd7dd1d2dcf9af76c2fcf5cebdead79376b724ee2958e930a4";
    memo = "b7342e22fec4f96698e5a88a755635be782fb27e3f4c0f7868eb1a7cca2b6166";
    merge = "053639722c1a3b00c17acfaebfea9ad8c130162b6e81895c424238786bd201bc";
    prelude = "b70720c17dc31dc59889bcd30aa2e1bd4e9abc1eb397c018fb4038c04c387271";
    product = "cc0703f389878e902f295bbb155ac4121f7889ba2f0c9ff4d14c9de06545ffbe";
    program = "64b8889dcc0e5a41f98537e24baeb3ba3a879686dd573eaf422b217dd3859596";
    schema = "2823239d89aec5e2358f0edca0090bd5f80a11273c187ba6ba4634e38af21c32";
    scope = "e49df31e4ba4113bc773ba190c719357e9f70907fdd8db4e713f1c0495a89488";
    select = "4facb22f69e61b329635dd742728988aec7b2d8566c3559ddce6763fb6440ff6";
    settings = "4c1d7b6a85da8dc75591b591767da073b3baf25884f24c163a231eaccbfdef66";
    types = "41ddedce3dcf0628fd06dd634ca0c2a4a3b14319e0c422590e64841ccdfc7438";
    view = "eb8fb97a732d7b8741e39761f34c45d40781f86d0a5d741cfe96e3df93010817";
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
  # Reported as a LIST, so a failure names the member instead of only denying — the same shape
  # `resolveFailed` and `strataMissing` already take.
  surfaceDrift = builtins.filter (k: (expectedSurface.${k} or null) != surfaceHashes.${k}) memberKeys;
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
    retired-refusing = retirementFailed == [ ];
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
    "retired-refusing"
  ];
  # Raw, for `nix eval ./ci#lib.mkGenLibsEval --json | jq`.
  keyCount = builtins.length actualKeys;
  memberCount = builtins.length memberKeys;
  keys = actualKeys;
  inherit expectedKeys missing extra;
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
    ;
  bucketCounts = builtins.listToAttrs (
    map (s: {
      name = s;
      value = builtins.length (bucketMembers s);
    }) publishedStrata
  );
}
