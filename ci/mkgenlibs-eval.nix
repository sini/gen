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

  # Force each key: deepSeq the lib's top-level attrset + values to WHNF — catches a broken import
  # wiring (missing dep arg, dep-signature drift) WITHOUT calling into each function. tryEval turns a
  # throw into `false`, so the check names WHICH key broke instead of aborting the whole eval. Forces
  # every ACTUAL key (not just the roster), so a newly-added broken key is exercised too.
  wired = builtins.listToAttrs (
    map (k: {
      name = k;
      value = (builtins.tryEval (builtins.deepSeq genLibs.${k} true)).success;
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
  # construction `wired` uses, so a bucket path that throws names the member.
  bucketResolve = builtins.listToAttrs (
    map (p: {
      name = "${p.s}.${p.k}";
      value = (builtins.tryEval (builtins.deepSeq buckets.${p.s}.${p.k} true)).success;
    }) bucketPairs
  );
  resolveFailed = builtins.filter (k: !bucketResolve.${k}) (builtins.attrNames bucketResolve);

  # AGREEMENT: a bucket entry is the same VALUE as the flat member, not a second evaluation of the
  # same source. This is the one property a names-and-types fingerprint cannot see — a library
  # re-imported at a different pin has identical names and identical types while being a different
  # build — so the arm compares values and tryEval keeps it total.
  agree = builtins.listToAttrs (
    map (
      p:
      let
        t = builtins.tryEval (buckets.${p.s}.${p.k} == genLibs.${p.k});
      in
      {
        name = "${p.s}.${p.k}";
        value = t.success && t.value;
      }
    ) bucketPairs
  );
  agreeFailed = builtins.filter (k: !agree.${k}) (builtins.attrNames agree);

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
    algebra = "79acb5ee07721fa7dcd468541d2a9c6a402e3ba42a8bbb0b21aa25bf912596a8";
    aspects = "a51fb019bf402c246739f034649e1d09e890757f01cc8f6a12857753b2a2f107";
    assemble = "fc9d7d15711aef75161972c90ae9ced3b8beb520d2dc381b1c4074df80169fac";
    bind = "b208c57ed918aed942c1a778aa2d321b78a7eba8a6bd5b9b518d3f74281e40bc";
    class = "82391568b8217b01fa44faa7fd359ae818591e5bb12ee4e954da59b33958b5a2";
    delivery = "8b0f007d723a6023c14af50860e247cf9f5aef7a51cd5c7f2cdf654add84f8ab";
    dispatch = "5b5968052b28f96d974dbc60549aaa9eef110323479bbfe235b75451ad0a4784";
    graph = "6f31e0f4603818a5e83a6563382c6057fdb678843817c03ef7dd873792f68454";
    identity = "ae39363fd50eb2100013362d3d43563146bf24fe8539675c8e8a944d62eaa201";
    link = "90b36cc605f281fd7dd1d2dcf9af76c2fcf5cebdead79376b724ee2958e930a4";
    memo = "b7342e22fec4f96698e5a88a755635be782fb27e3f4c0f7868eb1a7cca2b6166";
    merge = "b87d78c25e721bd348ecf696c0c866a6613f72ae290c558e5a7ad3f63490561a";
    prelude = "e5952bf9aeaf3603ae9a4641c71ad919e95cb5f7afaf24a968a58c8a85ddfd2f";
    product = "cc0703f389878e902f295bbb155ac4121f7889ba2f0c9ff4d14c9de06545ffbe";
    program = "7130554cb9c62b62122583e52459f46232d33b557b945388e60575abaa1cf952";
    schema = "96d6030ffe8cd5a4252a16989fe15d39dad5901cecbfb46d70ff8ac966f2463b";
    scope = "293b20b1b90fc8d27342d8265bd76e09a628c375520247abc396e99a47c7e2f8";
    select = "a1851c2323fa25fe4be9318d3dd0eec1a8ee10708eec82bdb2bb3cb0f0b27d86";
    settings = "8a88f4757c73da9483ceab95c2b7f8d5ec41579ef3c7457ed69f7e92890f2312";
    types = "6ea32cca70ade512882aad12f1c47a13202e0d460d543fa9134e84711344981e";
    view = "3e81112f6af688488ba8518d34928ddd538d6fafc39776d0b8598d6b21123bda";
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
    ;
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
