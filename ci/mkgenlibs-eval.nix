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
    "rules"
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
    {
      member = "schema";
      binding = "ref";
      cause = "a deliberate throwing tombstone for a renamed type constructor (gen-schema lib/ref.nix, `── THE RETIRED NAME ──`). The type's values are declarations and `ref` names the use side, inverting Neron et al. 2015, so the constructor is `declarationOf` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (TERM ruling 2026-09-25, refused-by-name alias)";
    }
    {
      member = "schema";
      binding = "fieldRef";
      cause = "a deliberate throwing tombstone for a renamed value constructor (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `mkFieldDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "schema";
      binding = "isFieldRef";
      cause = "a deliberate throwing tombstone for a renamed predicate (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `isFieldDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "schema";
      binding = "fieldRefsIn";
      cause = "a deliberate throwing tombstone for a renamed scan (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `fieldDeclarationsIn` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "schema";
      binding = "fieldRefMarker";
      cause = "a deliberate throwing tombstone for a renamed marker key (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `fieldDeclarationMarker` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "settings";
      binding = "ref";
      cause = "a deliberate throwing tombstone for a renamed value constructor (gen-settings lib/declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `mkDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "settings";
      binding = "isRef";
      cause = "a deliberate throwing tombstone for a renamed predicate (gen-settings lib/declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `isFieldDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "settings";
      binding = "refsIn";
      cause = "a deliberate throwing tombstone for a renamed scan (gen-settings lib/declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `fieldDeclarationsIn` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
    }
    {
      member = "scope";
      binding = "query";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the D<I<P selection is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "scope";
      binding = "queryAll";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the every-witness gather is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "scope";
      binding = "ambiguous";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the ambiguity test, redefined over distinct origins is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "scope";
      binding = "visibleFrom";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the visible-declaration read is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "scope";
      binding = "queryReverse";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the reverse-import gather, now the converse is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "graph";
      binding = "query";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): the labeled walk is gen-scope `resolve` over an evaluated scope (modes `all` / `paths` / `visible` are `reachable` / `witnesses` / `visible`), and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "graph";
      binding = "regex";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): a label expression is gen-scope `wellFormed`, built from a string or the published `wfl` constructors; the derivative engine is unpublished, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "graph";
      binding = "labeledFrom";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): a graph to resolve over is lifted into a gen-scope evaluated scope, and a labeled record kept for `forgetLabels` / `labeledTranspose` / `cyclicEdgesWhere` is written as data, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
    {
      member = "graph";
      binding = "boundedBy";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): boundary marks are read inside gen-scope `resolve` (each node declares `marks`, `bound` narrows, `withheld` names the mark, at the scopes `resolve` reached: a gen-graph `withheld` answered graph-total, including an edge withheld at a node the walk never visited, and gen-scope's does not), and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
    }
  ];
  # A GATE, not a notification: a lock bump must not be able to grow this set, because a tombstone
  # entering a published surface is a design decision and takes a ruling.
  retirementWidth = 18;

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
  # The form below mirrors the root `flake.nix` `outputs` (the members, `lib/hubSubstrate.nix`'s
  # applied fold, then `import ./.`), so it is total over every member. The ci flake has no input
  # named `gen`, and `lib/mkGenLibs.nix` takes resolved member values, not `genInputs`, so neither
  # can stand in for the root flake here. `plain` is the root flake's list of plain re-exports:
  #
  #   nix eval --impure --raw --expr '
  #     let
  #       hub = builtins.getFlake "git+file://<clone>/gen";
  #       gi = hub.inputs // { gen-<member> = builtins.getFlake "git+file://<clone>/gen-<member>?rev=<newRev>"; };
  #       plain = [ <the plain member keys, as in flake.nix `members`> ];
  #       members = builtins.listToAttrs (map (k: { name = k; value = gi."gen-${k}".lib; }) plain);
  #       applied = builtins.mapAttrs (k: args: gi."gen-${k}".lib args)
  #         (import "${hub}/lib/hubSubstrate.nix" (members // applied));
  #       roster = import "${hub}" (members // applied);
  #     in builtins.hashString "sha256" (builtins.toJSON (builtins.attrNames roster.<key>))'
  #
  # Arm it first: with `gi = hub.inputs` it must reproduce every pinned line below.
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
    # gen-algebra 6534ab3 → 18238b1 (relock 51, den-hoag-lwbb1 unit 1): the surface gained ONE name,
    # `term`, the first-order term algebra extracted from gen-bind's BodyTerm. Nothing was removed.
    # gen-algebra 18238b1 → 6orb8-u1 (den-hoag-6orb8 U1): the surface gained ONE name,
    # `hasDeclaredSubject`, the reader of a registered construction's declared comparison subject.
    # Nothing was removed.
    # gen-algebra e62747f → f1d208b (relock 68, den-hoag-dg8d1): the surface gained TWO names,
    # `hasMark` and `markOf`, the mark readers (decision and demand) beside `identityOf`. Nothing
    # was removed.
    algebra = "90c38511b4cdb3827057f22b53396798ab0918e1d3e4471dc84caae533372d61";
    # gen-aspects → 7c983f45 (the lock-currency relock): the surface gained ONE name,
    # `hasClassContent`, the class-content predicate over an aspect. No other member moved.
    # gen-aspects ff664f5 → 15f3f8e (den-hoag-5q36i U1): the surface gained ONE name, `isGuardLeaf`,
    # gen-aspects' own guard-leaf predicate, which delivery reuses. `includeSitesOf` and `nodeIdOf`
    # are `graphFacts` fields, not top-level names. Nothing was removed.
    # gen-aspects e466063 → 7ac3fd1 (relock 48, den-hoag-0cmbt U3): the surface gained ONE name,
    # `instanceOf`, which mints an aspect instance from its aspect and the sources of the keys it
    # receives. Nothing was removed and no other member moved.
    # gen-aspects 357249b → 7d6a009 (relock 49, den-hoag-0cmbt U4): the surface gained TWO names,
    # `instancesFor`, the instance relation over a scope's suppliers, and `includeSitesOfEntry`, the
    # one include-site classifier it lifts. Nothing was removed.
    # gen-aspects 0acfc5c → 1062acb (relock 51, den-hoag-lwbb1 unit 2): the surface LOST one name,
    # `toArgData`, retired with the custom guard forms now that a guard is a first-order term.
    # Nothing was added.
    # gen-aspects 9043da6 → 52e73a9 (relock 61, den-hoag-gywcg): the surface gained ONE name,
    # `parsePath`, the inverse of the one injective path rendering `pathKey` (a rendered key back to its
    # segment list). Nothing was removed.
    # gen-aspects 9d29ae7 → dd46b38 (den-hoag-8hlo3 U2, anonymous declarations are nodes): the surface
    # gained ONE name, `includeSitesOfInstance`, the include-site classifier keyed under an instance
    # id (each content site's `target` is `<iid>/includes/<i>`), and LOST ONE, `includeSitesOfEntry`,
    # which it replaces. No other member moved.
    aspects = "c947f8d11c227cbcafc7ba5ec03e3c5bf0c578e6244d5662eb3ecf8c445f811e";
    assemble = "fc9d7d15711aef75161972c90ae9ced3b8beb520d2dc381b1c4074df80169fac";
    bind = "b208c57ed918aed942c1a778aa2d321b78a7eba8a6bd5b9b518d3f74281e40bc";
    class = "82391568b8217b01fa44faa7fd359ae818591e5bb12ee4e954da59b33958b5a2";
    delivery = "8b0f007d723a6023c14af50860e247cf9f5aef7a51cd5c7f2cdf654add84f8ab";
    dispatch = "b6b0c94a150ba0aadad4a22c85c8f189b542592710ea51201f3d9151f8d00cc2";
    # gen-graph cfc2a90d7b → 00fe4bf4e9 (den-hoag-lock-currency-ruling-ez1yq, taken by the
    # lock-currency relock): the surface gained ONE name, `lowlink`, a third SCC-partition arm
    # (Tarjan's DFS iterated over a persistent trie) published beside `fbNode` and `fbWork`.
    # Nothing was removed and no other member moved.
    #
    # gen-graph 4649d8390b → 04993c2228 (den-hoag-gayc U1a): the surface gained ONE name, `key`, the
    # key formers with the refusal prefix a parameter, which gen-scope's calculus binds. Nothing was
    # removed.
    #
    # gen-graph ce977b5576 → ab81c86405 (den-hoag-gayc U3, gen-graph leaves the resolution
    # calculus): the surface lost SEVEN names, `queryArrivals`, `queryFold`, `ranksOf`, `rankOf`,
    # `rankWordOf`, `wordLess` and `pathLess`, which had no caller; `query`, `regex`, `labeledFrom`
    # and `boundedBy` became registered tombstones (retirementEntries above), so they are still
    # published names. Nothing was added.
    graph = "5d5ead1bc3b5cb92c788d0468fc90e0bf95908ba4922d39b893d21ce9dcd2041";
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
    #
    # gen-merge 1b95c7e → 9be19f2 (den-hoag-n6dh7 Unit 2, den-hoag-1n12c): the surface gained ONE
    # name, `moduleSyntax`, the reader's own structured/shorthand key lists, which gen-schema reads
    # instead of restating them. Nothing was removed and no other member moved.
    # gen-merge ec5a99d → aa61dd8 (den-hoag-zakjg U1, den-hoag-ydro3 arm (c)): the surface gained TWO
    # names, `priorityBand` and `bandedLeaves`, each contributor's leaves sorted into force, set,
    # default or unset. ydro3's `types.witnessRecord` is inside `types`, not a top-level name, so it
    # moves no digest here. Nothing was removed.
    # gen-merge c2405e0 → dd18d6b (relock 49, den-hoag-5kic): the surface gained ONE name,
    # `deriveType`, a type derived from a completed one and re-completed rather than overridden; it
    # is also `types.deriveType`. Nothing was removed.
    # gen-merge f282ed0 → 652acc0 (relock 68, den-hoag-gi421): the surface gained ONE name,
    # `importedCarried`, the one reader of what a type wraps in either vocabulary. Nothing was
    # removed.
    merge = "a9b0286daecbfbf45081ed0f65656ccc378f0c40b8499e97738ba0d757227aed";
    # gen-prelude eddf617 → 0ac7b66 (den-hoag-7gp66 P1): the surface gained THREE names,
    # `checkOptions`, `checkRequired` and `resolve`, the door constructs. Nothing was removed and no
    # other member moved.
    #
    # gen-prelude 0e2d39d → 02dc956 (den-hoag-7gp66 P2 L0): the surface gained ONE name, `door`,
    # the door constructor. `isFunction` and `functionArgs` keep their names and became nixpkgs'
    # functor-aware readers. Nothing was removed.
    #
    # gen-prelude 6487a87 → f7247d1 (den-hoag-7gp66 P2 v1.2): the surface gained ONE name,
    # `checkGuarded`, the misplaced-option guard `door`'s `optionsStep` applies. Nothing was removed.
    # gen-prelude b2962cb → 0bed837 (relock 53, den-hoag-fyx6m): the surface gained ONE name,
    # `isStringLike`, vendored from nixpkgs `lib.isStringLike` for gen-types' `path` and `pathLike`.
    # Nothing was removed.
    # gen-prelude 7f80026 → fe448bb (relock 68, den-hoag-7jltk): the surface gained ONE name,
    # `refusals`, the record of the text each door construct throws. Nothing was removed.
    prelude = "edd90797fa5171dd1c62659587ca80eb1b2020d9f3f7e60bbf50fa4b257307f1";
    product = "cc0703f389878e902f295bbb155ac4121f7889ba2f0c9ff4d14c9de06545ffbe";
    # gen-program (den-hoag-qq9vt): the surface gained ONE name, `ruleEdges`. Nothing was removed.
    # gen-program c913d05 → 04c9161 (relock 51, den-hoag-lwbb1 unit 3): the surface gained TWO names,
    # `groundInstances`, which resolves a terms-only policy body at a context, and
    # `codomainBreaches`, the per-firing codomain check the gen-rules door applies. Nothing was
    # removed.
    program = "e4cf1540eb0d2be27eb306eb487cf395fbe2f4a42b47fb38501aa11547a48704";
    # gen-rules, the roster's 23rd member and the 5th at `framework`: the one closure crossing. Its
    # surface was 5 names — the loader lowering and its registration table, the door, and the two
    # catalogue patterns. gen-rules d473539 → relock 64 (den-hoag-lwbb1 S1 (a), den-hoag-1wdng): the
    # surface gained TWO names, `lambdasMount`, the registration table mounted inside the aspect
    # submodule, and `registrations`, the tables a load-time closure's site names. Nothing was removed.
    rules = "2a9bce7a102ab1196f5d58fd19b5ca837ded06096240bae431cf80d35e675fb0";
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
    #
    # gen-schema f99df45 → f7ecf39 (den-hoag-2zjg1): the surface gained ONE name,
    # `declarationOf`; `ref` became a registered tombstone (retirementEntries above), so it is still
    # a published name and nothing was removed.
    #
    # gen-schema 749cfdd → 620bf64 (den-hoag-2zjg1, the TERM ruling reaching the value constructor):
    # the surface gained the declaration-named `mkFieldDeclaration`, `isFieldDeclaration`,
    # `fieldDeclarationsIn` and `fieldDeclarationMarker`, and the four names they replace, `fieldRef`,
    # `isFieldRef`, `fieldRefsIn` and `fieldRefMarker`, became registered tombstones
    # (retirementEntries above): still published names, so nothing was removed.
    #
    # gen-schema 620bf64 → 4c30e07 (den-hoag-8x97u, relock 47): the surface gained ONE name,
    # `entryReservation`, the reservation a kind entry's import closure is checked against. Nothing
    # was removed and no other member's names moved.
    schema = "d6259d6dc90d1dd8d683b9c2658b064a4e44a4a065f401e38cb375290593ace9";
    # gen-scope d24e0d983f → 41c7d9f5ea (den-hoag-wk8g8): the hub relock onto the four
    # declaration-bearing members moved this member's published surface.
    #
    # gen-scope e64c00719a → e355bb866a (den-hoag-n6dh7 Unit 1, the recursive NTA channel): the
    # surface gained FOUR names, `childDepth`, `decodeNta`, `flattenChildren` and `mintNtaId`.
    # Nothing was removed and no other member moved.
    #
    # gen-scope f5f2b6550c → a650104f6f (kinds minted by a staged fold): the surface lost ONE name,
    # `isKindSet`, the registry provenance test the fold made redundant. Nothing was added and no
    # other member moved.
    #
    # gen-scope c25d0e6db2 → b4418fa822 (den-hoag-4kh.53.54): the surface lost ONE name, `paramAttr`,
    # the retired parameter-attribute accessor. Nothing was added and no other member moved.
    #
    # gen-scope 70c286a → 5afbb0f (relock 48, den-hoag-0cmbt U5): the surface gained ONE name,
    # `argumentBinding`. Nothing was removed.
    #
    # gen-scope 7ab60ef → 995461f (den-hoag-gayc, the one resolution calculus): the surface gained
    # `wellFormed`, `labelOrder`, `neron` and `wfl`; `resolve` names the calculus where it named the
    # D<I<P selector; `query`, `queryAll`, `ambiguous`, `visibleFrom` and `queryReverse` are
    # tombstones (`retirementEntries`).
    scope = "a5393968311a63822c332337c0fc5221c37d5c13430cc71942483f93576cc9eb";
    # gen-select 8ab4b1d → 37eccfc (relock 48, den-hoag-l0y U3): the surface gained ONE name, `subkind`,
    # the selector matching a kind or any subkind of it. Nothing was removed.
    select = "5df8bc671b37fec1a92a3c159fab3a2575411430300a146cd90f3667e760dbeb";
    # gen-settings 3449bfa → e7cafdd (den-hoag-2zjg1): the surface gained `mkDeclaration`,
    # `isFieldDeclaration` and `fieldDeclarationsIn`; `ref`, `isRef` and `refsIn` became registered
    # tombstones (retirementEntries above), so nothing was removed.
    settings = "0ad19eb12ce7cc7851c97fb00a9b2a756cf95d2806a556c1892414852da383b8";
    # gen-types 1542e47126 → c8ea733eba (den-hoag-z3nrc, taken by the lock-currency relock): the
    # surface gained ONE name, `identityGuard`, the step-indexed guard that bounds type nesting for
    # identity. Nothing was removed and no other member moved.
    #
    # gen-types 048dd55fb → ef69ea948 (the construction-payload reader, taken by the lock-currency
    # relock): the surface gained ONE name, `payloadOf`, the certifying reader of a checker's
    # `__payload`. Nothing was removed. gen-merge re-exports it inside its `types` namespace only,
    # so its own published names did not move.
    #
    # gen-types 496d882 → f6115ec (den-hoag-ydro3): the surface gained TWO names, `rewritesCheck` and
    # `witnessedCheck`, the check-witness protocol that detects a wrapper rewriting a record's
    # `check`. Nothing was removed.
    # gen-types f6115ec → 3f8b7ca (den-hoag-ydro3 arm (c)): the surface gained ONE name,
    # `witnessRecord`, the one record `witnessedCheck` publishes twice, for a producer that publishes
    # it itself. Nothing was removed.
    # gen-types d1930bf → 6orb8-u1 (den-hoag-6orb8 U1): the surface gained TWO names, `mkIdentity`,
    # the per-component identity half a producer outside gen-types builds through, and
    # `comparisonSubject`, the compared regime's subject. Nothing was removed.
    # gen-types 6orb8-u1 → 6orb8-u1b (den-hoag-6orb8 U1b): the surface gained ONE name, `stampOk`,
    # the completion stamp's reader a rebuilding boundary consults. Nothing was removed.
    # gen-types → 6orb8-a1 (den-hoag-6orb8 A1): the surface gained ONE name, `idOf`, the identity
    # demand (a projection over `__mint` / `__sealed`) that replaced the retired `__id` field. Nothing
    # was removed.
    types = "14dc8e18ddba1ba25e1ece2f9216a4d593ffdcd470bc087f5369ecc721e7714b";
    # gen-view 2656d3cc38 → eccb0d2a78 (den-hoag-wk8g8): same relock, this member's published
    # surface also moved. `gen-bind` and `gen-select` moved in the same relock but are free
    # riders here — their hashes are unchanged, so no line for them was touched.
    # gen-view 5d0835a → 47106a8 (den-hoag-zakjg U2/U3): the surface gained TWO names,
    # `headPositions` and `joinedTrace`. Nothing was removed.
    # gen-view 83796dc → gayc-u2a (den-hoag-gayc U2a, D14): the surface lost TWO names,
    # `labelWellFormedness` and `labelOrder`. E and < are the resolution calculus's own parameters
    # and gen-scope builds them (`wellFormed`, `labelOrder`); they are removed, not re-exported.
    # Nothing was added.
    view = "ea9490675935a131800e05e0de5af68aa317a9fa45597a2fddb22bb9057fed72";
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
  # met on that walk. A FUNCTOR DOOR's formals are read too: a published door that takes a record
  # step publishes its field contract as data (`prelude.door`, den-hoag-49yxv), so the walk reads
  # its `__functionArgs` where `builtins.functionArgs` reads nothing. That is the owner's C′ ruling
  # (2026-09-27, "accept C'"), which also decided den-hoag-2xg6e as (β): the contract doors
  # reshape like every other door and publish their contract as data. ★ WHAT IT DOES NOT SEE,
  # stated rather than left to be discovered: fields of a record a function RETURNS, the steps
  # behind a POSITIONAL first step (`memo.runScc`, den-hoag-ak8va OQ-1, until den-hoag-n7ax),
  # a record's field-level contracts (a field that is itself checked by a door), sets inside lists,
  # `_type` sets, `name` strings, error text, option descriptions and docs prose, and the hub
  # flakeModule's option names. A chained door's later steps ARE read, from `__contract.next`.
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

  vocabularyWalk = walkWith wordsIn;
  # `walkWith wordsOf` is the walk over any name predicate: `wordsIn` for the vocabulary, and the
  # every-name predicate for the reach arm below, so the reach arm runs THIS walk.
  walkWith =
    wordsOf: member: depth: p: v:
    let
      t = builtins.tryEval (builtins.typeOf v);
      kind = if t.success then t.value else "throws";
      at = builtins.concatStringsSep "." p;
      hits =
        at': name:
        map (word: {
          inherit member word;
          at = at';
        }) (wordsOf name);
      own = if p == [ ] then [ ] else hits at (builtins.elemAt p (builtins.length p - 1));
      formals = builtins.concatMap (f: hits "${at}:${f}" f) (
        builtins.attrNames (
          if kind == "lambda" then
            builtins.functionArgs v
          else if kind == "set" && v ? __functor && v ? __functionArgs then
            v.__functionArgs
          else
            { }
        )
      );
      # A chained door's later steps (den-hoag-ak8va; OQ16 "nest", owner 2026-09-28): `door`
      # publishes each next step's contract as `__contract.next`, so the walk reads step k's fields
      # at the locus `<at>:next:…:<field>` with no application of any step.
      # A positional node (`{ positional; next; }`, a plain-lambda step between two record steps)
      # contributes its operand's name, and counts as a step in the locus.
      nextFormals =
        pre: c:
        if builtins.isAttrs c && c ? next && builtins.isAttrs c.next then
          (
            if c.next ? positional then
              hits "${at}:${pre}next:${c.next.positional}" c.next.positional
            else
              builtins.concatMap (f: hits "${at}:${pre}next:${f}" f) (c.next.required ++ c.next.optional)
          )
          ++ nextFormals "${pre}next:" c.next
        else
          [ ];
      later =
        if kind == "set" && v ? __functor && v ? __contract then nextFormals "" v.__contract else [ ];
      plain = kind == "set" && !(v ? _type) && !(v ? type && v ? check) && !(v ? __functor);
      names = builtins.tryEval (builtins.attrNames v);
      kids =
        if plain && depth < vocabularyDepth && names.success then
          builtins.concatMap (n: walkWith wordsOf member (depth + 1) (p ++ [ n ]) v.${n}) names.value
        else
          [ ];
    in
    own ++ formals ++ later ++ kids;

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
      member = "scope";
      at = "mintNtaId:host";
      word = "host";
      clause = "meaning cut: the NTA's hosting node — the node an `nta` child is minted under, the coordinate `decodeNta` answers (Vogt, Swierstra & Kuiper 1989; ADR-0008) — not a fleet object (ADR-0035); a record field since den-hoag-7gp66 P2 L2";
    }
    {
      member = "settings";
      at = "assembleHost";
      word = "host";
      clause = "ADR-0017: `assembleHost` retires as a name, and the retirement's execution is deferred";
    }
  ];

  # The `hub` arm walks `compose` only. `lib.flakePartsEvaluate` is outside it DELIBERATELY: it is
  # ADR-0031 F1's interim flake-parts surface (re-affirmed 2026-09-28: "the one flake-parts binding
  # lives in the marked-interim hub surface"), unwalked like `flakeModules.default`, whose native
  # vocabulary it binds for gen-bind's `crossing.mkOutputsTerminal` (den-hoag-52hn7).
  vocabularySurface = builtins.removeAttrs genLibs [ declKey ] // {
    hub = {
      inherit (gen.lib) compose;
    };
  };
  vocabularyOffenders = offendersOf vocabularySurface;
  # Every formal locus the walk reads on one member; `transitiveClosure:maxIter` (step 1) is the
  # live control that the reach arm's walk is not dead.
  vocabularyGraphLoci = map (o: o.at) (walkWith (_: [ "*" ]) "graph" 0 [ ] genLibs.graph);
  vocabularyNextLoci = builtins.filter (
    at: builtins.length (builtins.split ":next:" at) > 1
  ) vocabularyGraphLoci;
  vocabularyUnregistered = map showOffender (unregisteredOf vocabularyRegister vocabularyOffenders);
  vocabularyStale = map showEntry (staleOf vocabularyRegister vocabularyOffenders);

  # ── the vocabulary arming ── a synthetic fixture, disjoint from the live surface. `doorOf` is
  # the roster's own door constructor, so the functor-formals route is armed on the construct the
  # live surface uses.
  doorOf =
    name: required:
    genLibs.prelude.door {
      inherit name required;
    } (a: a);
  chainOf =
    name: field:
    let
      recordSpec = {
        inherit name;
        required = [ field ];
        open = true;
      };
    in
    genLibs.prelude.door {
      inherit name;
      optional = [ "depth" ];
      next = recordSpec;
    } (o: genLibs.prelude.door recordSpec (r: r));
  armVocab = {
    alpha = {
      c = chainOf "alpha.c" "hostName";
      mkHostThing = x: x;
      g = { userName }: userName;
      d = doorOf "alpha.d" [ "hostName" ];
      fromNixOS = 1;
      hostname = 1;
      ok = 1;
    };
  };
  armVocabClean = {
    alpha = {
      c = chainOf "alpha.c" "nodeName";
      mkNodeThing = x: x;
      g = { nodeName }: nodeName;
      d = doorOf "alpha.d" [ "nodeName" ];
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
    # hit per route: a camel-case token, a formal, a functor door's published formal, and the two
    # the token split cannot see.
    arming-vocabulary-names-planted =
      vocabularyArming.planted == [
        "alpha.c:next:hostName [host]"
        "alpha.c:next:hostName [hostname]"
        "alpha.d:hostName [host]"
        "alpha.d:hostName [hostname]"
        "alpha.fromNixOS [nixos]"
        "alpha.g:userName [user]"
        "alpha.g:userName [username]"
        "alpha.hostname [hostname]"
        "alpha.mkHostThing [host]"
      ];
    arming-vocabulary-silent-on-clean = vocabularyArming.clean == [ ];
    arming-vocabulary-names-stale = vocabularyArming.stale == [ "alpha.gone [host]" ];
    # REACH, on the LIVE surface: the walk reads a real chained door's step-2 fields. Red while any
    # landing leaves `transitiveClosure` publishing its first step only.
    vocabulary-reaches-next = builtins.elem "transitiveClosure:next:edges" vocabularyNextLoci;
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
    "vocabulary-reaches-next"
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
    vocabularyGraphLoci
    vocabularyNextLoci
    ;
  vocabularyRegister = map (e: "${showEntry e}: ${e.clause}") vocabularyRegister;
  bucketCounts = builtins.listToAttrs (
    map (s: {
      name = s;
      value = builtins.length (bucketMembers s);
    }) publishedStrata
  );
}
