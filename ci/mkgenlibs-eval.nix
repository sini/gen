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
    "dispatch"
    "edge"
    "flake"
    "graph"
    "link"
    "memo"
    "merge"
    "pipe"
    "prelude"
    "product"
    "resolve"
    "schema"
    "scope"
    "select"
    "settings"
    "strata"
    "types"
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
  };
  gateKeys = actualKeys ++ [
    "roster-ok"
    "strata-total"
    "strata-enum"
    "buckets-match"
    "buckets-disjoint"
    "buckets-resolve"
    "buckets-agree"
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
  bucketCounts = builtins.listToAttrs (
    map (s: {
      name = s;
      value = builtins.length (bucketMembers s);
    }) publishedStrata
  );
}
