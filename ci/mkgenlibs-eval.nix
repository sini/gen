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
# It also checks the PUBLISHED EXPORT SURFACE: the name-paths each member publishes, at every depth,
# compared against a hand-maintained pin (`expectedSurface`, `ci/surface-paths.nix`). The forcing arms
# above catch a pin bump that THROWS; this one catches a pin bump that merely CHANGES — an export
# removed, added or renamed, or a member replaced by a different library, none of which breaks the
# wiring — and refuses a LOST path by name (`surface-kept`). The observable is names, never a
# rev/narHash/outPath, so a docs-only bump leaves the pin's reading byte-identical; a behaviour change under an unchanged export surface is outside this arm by
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
  #
  # A `binding` and a `successor` are NAME-PATHS, keyed as gen-harness's `rootSurface.retired` keys
  # them (den-hoag-o6b81): a top-level name is its own path, and a nested one is `"show.cell"`, each
  # segment rendered as nixpkgs `showAttrPath` renders it. A path is compared by its rendering and
  # never parsed (`render`, `lookupPath` and `minusPaths` below).
  retirementEntries = [
    {
      member = "scope";
      binding = "buildNodes";
      cause = "a deliberate throwing tombstone for a retired constructor (gen-scope lib/build-nodes.nix, `── THE RETIRED NAME ──`). `buildRoots` returns `{ nodes, nodeOrder }` where this returned a bare node map, so a silent redirect would let every enumerating read answer `[ \"nodeOrder\" \"nodes\" ]` with no error: refusing the name means the call cannot be WRITTEN rather than being detected after it is";
      carrier = "OQ-1 of specs/2026-09-05-gen-hub-relock-migration-spec.md, ruled 2026-09-08";
      successor = "buildRoots";
    }
    {
      member = "schema";
      binding = "ref";
      cause = "a deliberate throwing tombstone for a renamed type constructor (gen-schema lib/ref.nix, `── THE RETIRED NAME ──`). The type's values are declarations and `ref` names the use side, inverting Neron et al. 2015, so the constructor is `declarationOf` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (TERM ruling 2026-09-25, refused-by-name alias)";
      successor = "declarationOf";
    }
    {
      member = "schema";
      binding = "fieldRef";
      cause = "a deliberate throwing tombstone for a renamed value constructor (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `mkFieldDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "mkFieldDeclaration";
    }
    {
      member = "schema";
      binding = "isFieldRef";
      cause = "a deliberate throwing tombstone for a renamed predicate (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `isFieldDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "isFieldDeclaration";
    }
    {
      member = "schema";
      binding = "fieldRefsIn";
      cause = "a deliberate throwing tombstone for a renamed scan (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `fieldDeclarationsIn` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "fieldDeclarationsIn";
    }
    {
      member = "schema";
      binding = "fieldRefMarker";
      cause = "a deliberate throwing tombstone for a renamed marker key (gen-schema lib/field-declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `fieldDeclarationMarker` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "fieldDeclarationMarker";
    }
    {
      member = "settings";
      binding = "ref";
      cause = "a deliberate throwing tombstone for a renamed value constructor (gen-settings lib/declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `mkDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "mkDeclaration";
    }
    {
      member = "settings";
      binding = "isRef";
      cause = "a deliberate throwing tombstone for a renamed predicate (gen-settings lib/declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `isFieldDeclaration` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "isFieldDeclaration";
    }
    {
      member = "settings";
      binding = "refsIn";
      cause = "a deliberate throwing tombstone for a renamed scan (gen-settings lib/declaration.nix, `── THE RETIRED NAMES ──`). The value is a declaration (Neron et al. 2015) and the old name inverted that term, so it is `fieldDeclarationsIn` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-2zjg1 (Q1 \"a\" 2026-10-01; arm text \"keeping the old names as refused-by-name aliases\")";
      successor = "fieldDeclarationsIn";
    }
    {
      member = "scope";
      binding = "query";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the D<I<P selection is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "scope";
      binding = "queryAll";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the every-witness gather is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "scope";
      binding = "ambiguous";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the ambiguity test, redefined over distinct origins is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "scope";
      binding = "visibleFrom";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the visible-declaration read is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "scope";
      binding = "queryReverse";
      cause = "a deliberate throwing tombstone for a surface retired by the one resolution calculus (gen-scope lib/resolve.nix, `RETIRED BY THE ONE CALCULUS`): the reverse-import gather, now the converse is `resolve` under a stated `wf` and `mode`, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "graph";
      binding = "query";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): the labeled walk is gen-scope `resolve` over an evaluated scope (modes `all` / `paths` / `visible` are `reachable` / `witnesses` / `visible`), and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "graph";
      binding = "regex";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): a label expression is gen-scope `wellFormed`, built from a string or the published `wfl` constructors; the derivative engine is unpublished, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "graph";
      binding = "labeledFrom";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): a graph to resolve over is lifted into a gen-scope evaluated scope, and a labeled record kept for `forgetLabels` / `labeledTranspose` / `cyclicEdgesWhere` is written as data, and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "graph";
      binding = "boundedBy";
      cause = "a deliberate throwing tombstone for a surface retired when gen-graph left the resolution calculus (gen-graph lib/default.nix, `RETIRED BY THE ONE CALCULUS`): boundary marks are read inside gen-scope `resolve` (each node declares `marks`, `bound` narrows, `withheld` names the mark, at the scopes `resolve` reached: a gen-graph `withheld` answered graph-total, including an edge withheld at a node the walk never visited, and gen-scope's does not), and the tombstone names that spelling, so an un-migrated call is refused where it is written rather than answering";
      carrier = "den-hoag-gayc D16, unit U3 (build spec 2026-09-28, owner-approved design; renamed exports keep refused-by-name aliases)";
      successor = null;
    }
    {
      member = "types";
      binding = "listOf";
      cause = "a deliberate throwing tombstone for a renamed checker (gen-types lib/default.nix, `── THE RETIRED NAMES ──`). A checker is a predicate over one value and gen-merge's `listOf` folds definitions across modules: two values of one sort with different meanings, so gen-merge keeps the nixpkgs-parity name and the checker is `checkedListOf`, the old name refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 L1 (grammar R10 rule 3, O4 defaulted 2026-10-07; old names stay as refused-by-name aliases)";
      successor = "checkedListOf";
    }
    {
      member = "types";
      binding = "attrsOf";
      cause = "a deliberate throwing tombstone for a renamed checker (gen-types lib/default.nix, `── THE RETIRED NAMES ──`). A checker is a predicate over one value and gen-merge's `attrsOf` folds definitions across modules, so the checker is `checkedAttrsOf` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 L1 (grammar R10 rule 3, O4 defaulted 2026-10-07; old names stay as refused-by-name aliases)";
      successor = "checkedAttrsOf";
    }
    {
      member = "types";
      binding = "option";
      cause = "a deliberate throwing tombstone for a renamed checker (gen-types lib/default.nix, `── THE RETIRED NAMES ──`). A checker is a predicate over one value and gen-merge's `option` is an option type, so the checker is `checkedOption` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 L1 (grammar R10 rule 3, O4 defaulted 2026-10-07; old names stay as refused-by-name aliases)";
      successor = "checkedOption";
    }
    {
      member = "types";
      binding = "attrs";
      cause = "a deliberate throwing tombstone for a renamed checker (gen-types lib/default.nix, `── THE RETIRED NAMES ──`). A checker is a predicate over one value and gen-merge's nullary `attrs` folds definitions across modules, so the checker is `checkedAttrs` and the old name is refused by name, never silently aliased; gen-merge's `types` link admits its shadow only because the loser is this tombstone";
      carrier = "den-hoag-y9vzt (owner arm (D) 2026-10-18: R10 rule 3 applied to the one same-sort pair the L1 sweep never reached; link admits a shadow only over a registered tombstone)";
      successor = "checkedAttrs";
    }
    {
      member = "select";
      binding = "any";
      cause = "a deliberate throwing tombstone for a renamed selector constructor (gen-select lib/constructors.nix, `── THE RETIRED NAME ──`). gen-prelude's `any` is the list predicate and keeps the name by parity, so the disjunction is `anyOf` and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 L1 (grammar R10 rule 3, O5 provenance group defaulted 2026-10-07; old names stay as refused-by-name aliases)";
      successor = "anyOf";
    }
    {
      member = "product";
      binding = "cell";
      cause = "a deliberate throwing tombstone for a renamed addressing door (gen-product lib/default.nix, `── THE RETIRED NAMES ──`). A product's cell is the node a graph query takes, so the door takes the node's word, `nodeAt`, and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 L1 (grammar R8, O3 defaulted 2026-10-07; old names stay as refused-by-name aliases)";
      successor = "nodeAt";
    }
    {
      member = "product";
      binding = "cells";
      cause = "a deliberate throwing tombstone for a renamed enumeration door (gen-product lib/default.nix, `── THE RETIRED NAMES ──`). A product's cell is the node a graph query takes, so the enumeration of node coordinates is `nodeCoordinates`, and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 L1 (grammar R8, O3 defaulted 2026-10-07; old names stay as refused-by-name aliases)";
      successor = "nodeCoordinates";
    }
    {
      member = "product";
      binding = "show.cell";
      cause = "a deliberate throwing tombstone for a renamed display helper (gen-product lib/show.nix, `── THE RETIRED NAME ──`). A product's cell is the node a graph query takes, so the helper that names one in a refusal takes the node's word, `show.node`, and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-7gp66 P3 trailing row 15 (grammar R8; old names stay as refused-by-name aliases), admissible below the top level by den-hoag-o6b81";
      successor = "show.node";
    }
    {
      member = "aspects";
      binding = "includeSitesOfEntry";
      cause = "a deliberate throwing tombstone for a renamed include-site classifier (gen-aspects lib/default.nix, `── THE RETIRED NAME ──`). Anonymous include content became nodes keyed by declaration address (den-hoag-8hlo3 U2), so the classifier takes the instance id the content is keyed under, `includeSitesOfInstance cnf aspects iid entry`, and the old name is refused by name, never silently aliased";
      carrier = "den-hoag-4akh9 (law batch v1 C9, ADR-0011's rider: a renamed export keeps a refused-by-name alias during migration)";
      successor = "includeSitesOfInstance";
    }
  ];
  # A GATE, not a notification: a lock bump must not be able to grow this set, because a tombstone
  # entering a published surface is a design decision and takes a ruling.
  retirementWidth = 27;

  ruledRetirement =
    let
      required = [
        "member"
        "binding"
        "cause"
        "carrier"
        # The binding path of the same member that replaces this one, or `null` for a name that retires
        # with none (den-hoag-7gp66 rule S). A present `null` passes this presence check.
        "successor"
      ];
      checked = map (
        x:
        let
          missing' = builtins.filter (f: !(x ? ${f}) || x.${f} == "") required;
        in
        if missing' == [ ] && removalRefusal x == null then
          x
        else if missing' == [ ] then
          throw "mkgenlibs-eval: a retirement register entry (${x.member}.${x.binding}): ${removalRefusal x}"
        else
          throw "mkgenlibs-eval: a retirement register entry (${x.member or "?"}.${x.binding or "?"}) omits required field(s): ${builtins.concatStringsSep ", " missing'}. An entry with no stated cause and no carrier is the unbounded allow-list this check refuses."
      ) retirementEntries;
    in
    if builtins.length checked == retirementWidth then
      checked
    else
      throw "mkgenlibs-eval: the retirement register holds ${toString (builtins.length checked)} entries; its ruled width is ${toString retirementWidth}. A further entry is a NEW RULING and takes this line with it.";

  retiredIn = k: map (e: e.binding) (builtins.filter (e: e.member == k) ruledRetirement);

  # A protocol field: its rendered segment begins `__` (a `__` name is a plain identifier, so `seg` leaves
  # it unquoted, and the last segment of a rendered path is what follows its last `.`).
  isDunder = n: builtins.substring 0 2 n == "__";
  pathIsDunder = k: builtins.match "(.*\\.)?__[^.\"]*" k != null;
  # ★ THE REMOVAL FORM. An entry with `tombstone = false` publishes NO tombstone: it admits that the path
  # is gone. It is open to a `__` path only. C9 holds for every other export (a retired name keeps a
  # refused-by-name alias), and for a `__` field a tombstone is the harm the walk's header names. The
  # entry's binding must be ABSENT at every locus and HELD by the pin (`retirementFailed`), so it cannot
  # outlive the removal or admit a path that was never published. `surface-kept` subtracts exactly these
  # paths from a member's lost set.
  isRemoval = e: !(e.tombstone or true);
  removalRefusal =
    e:
    if e ? tombstone && !(builtins.isBool e.tombstone) then
      "`tombstone` is ${builtins.toJSON e.tombstone}, not a boolean"
    else if isRemoval e && !(pathIsDunder e.binding) then
      "`tombstone = false` admits the removal of a `__` protocol field only; a retired export keeps a refused-by-name tombstone (C9)"
    else
      null;
  admittedRemovals = builtins.foldl' (
    acc: e: acc // { ${e.member} = (acc.${e.member} or [ ]) ++ [ e.binding ]; }
  ) { } (builtins.filter isRemoval ruledRetirement);

  # nixpkgs `lib.strings.escapeNixIdentifier`, the segment rendering of `showAttrPath`, as
  # gen-harness `root-surface.nix` renders a `retired` key.
  seg =
    n:
    if builtins.match "[a-zA-Z_][a-zA-Z0-9_'-]*" n != null then
      n
    else
      builtins.replaceStrings [ "$" ] [ "\\$" ] (builtins.toJSON n);
  render = p: n: if p == "" then seg n else "${p}.${seg n}";
  # `k` lies strictly under the rendered path `q`. `seg` is prefix-free, so at most one name of a
  # namespace renders as `k` or as a path `k` lies under.
  under = q: k: builtins.substring 0 (builtins.stringLength q + 1) k == "${q}.";
  # The value at the rendered path `k`, forcing only the namespaces on the way, each under
  # `tryEval`: a path through a throwing or non-attrset value is not found.
  lookupPath =
    p: v: k:
    let
      hits = builtins.filter (n: render p n == k || under (render p n) k) (builtins.attrNames v);
      n = builtins.head hits;
      t = builtins.tryEval v.${n};
    in
    if !(builtins.isAttrs v) || hits == [ ] then
      { found = false; }
    else if render p n == k then
      {
        found = true;
        value = v.${n};
      }
    else if t.success && builtins.isAttrs t.value then
      lookupPath (render p n) t.value k
    else
      { found = false; };
  # `v` minus the rendered paths `ks`, by `removeAttrs` at each level the paths reach: every value the
  # narrowing keeps is the same value, so `agree`'s `==` still compares a kept member by identity.
  minusPaths =
    p: ks: v:
    let
      names = builtins.attrNames v;
      drop = builtins.filter (n: builtins.elem (render p n) ks) names;
      into = builtins.filter (n: !(builtins.elem n drop) && builtins.any (under (render p n)) ks) names;
    in
    builtins.removeAttrs v drop
    // builtins.listToAttrs (
      map (n: {
        name = n;
        value =
          let
            x = v.${n};
          in
          if builtins.isAttrs x then minusPaths (render p n) ks x else x;
      }) into
    );
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
    if r == [ ] then v else minusPaths "" r v;

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
    let
      l = lookupPath "" v e.binding;
    in
    if isRemoval e then
      (if l.found then [ "${label}: registered as removed, and the binding is present" ] else [ ])
    else if !l.found then
      [ "${label}: registered, and the binding is absent" ]
    else if (builtins.tryEval (builtins.deepSeq l.value true)).success then
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
    (
      if isRemoval e && !(builtins.elem e.binding (expectedSurface.${e.member} or [ ])) then
        [ "${e.member}.${e.binding}: registered as removed, and the pin does not hold the path" ]
      else
        [ ]
    )
    ++ retirementAt "${e.member}.${e.binding}" (genLibs.${e.member} or null) e
    ++ builtins.concatMap (
      s: retirementAt "${s}.${e.member}.${e.binding}" (buckets.${s}.${e.member} or null) e
    ) (bucketPathsOf e.member)
  ) ruledRetirement;

  # ── rule C: every registered tombstone names a LIVE successor (den-hoag-7gp66 A3) ──
  #
  # Read from the register's `successor` field, never parsed from a throw message: prose is not data.
  # A `null` successor is a retirement with none and is exempt by its value, not by a hand list. A
  # successor is live when the member publishes it, it forces to WHNF, and it is not itself a
  # registered tombstone of that member: a tombstone naming another tombstone sends its caller from
  # one refusal to a second.
  deadSuccessorsOf =
    libs: entries:
    map (e: "${e.member}.${e.binding}") (
      builtins.filter (
        e:
        e.successor != null
        && (
          let
            l = lookupPath "" (libs.${e.member} or { }) e.successor;
          in
          !l.found
          || !(builtins.tryEval (builtins.typeOf l.value)).success
          || builtins.any (r: r.member == e.member && r.binding == e.successor) entries
        )
      ) entries
    );
  successorDead = deadSuccessorsOf genLibs ruledRetirement;
  # ARMING: one live successor, one planted entry whose successor is itself registered, one absent
  # successor, one whose successor throws without being registered, and one retirement with none.
  # Exactly the registered, the absent and the throwing ones are named, one per clause.
  successorArming =
    deadSuccessorsOf
      {
        alpha = {
          new = 1;
          old = throw "alpha: old";
          older = throw "alpha: older";
          broken = throw "alpha: broken";
          ns = {
            new = 1;
            old = throw "alpha: ns.old";
          };
        };
      }
      [
        {
          member = "alpha";
          binding = "old";
          successor = "new";
        }
        {
          member = "alpha";
          binding = "older";
          successor = "old";
        }
        {
          member = "alpha";
          binding = "oldest";
          successor = "missing";
        }
        {
          member = "alpha";
          binding = "gone";
          successor = null;
        }
        # a successor that throws and is NOT registered: only the `tryEval` clause names it
        {
          member = "alpha";
          binding = "stale";
          successor = "broken";
        }
        # paths one namespace down: a live nested successor, and one absent under a live namespace
        {
          member = "alpha";
          binding = "ns.old";
          successor = "ns.new";
        }
        {
          member = "alpha";
          binding = "ns.older";
          successor = "ns.missing";
        }
      ];

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
  # ★ A PUBLISHED NAME IS A PATH THROUGH PLAIN NAMESPACES (den-hoag-hr4yg arm (a)). The walk is gen-harness
  # `root-surface.nix`'s: a namespace is an attrset that is not `_type`-tagged and not a derivation, a
  # `__functor` set included, and every other value is a leaf, forced to WHNF only to tell which it is
  # (under `tryEval`, so a tombstone is a leaf and still a path). One difference: a `__`-prefixed name
  # (`__functor`, `__functionArgs`, a door's `__contract`, a type's `__typeSelf`) is a LEAF path. It is
  # pinned, and it is never descended. It is pinned because it is consumed surface: measured 2026-11-04
  # (reports/den-hoag-loadi-stale-after-loadmax-raise-5mq5q-m3-landing-gate-v0.md, files reading the field
  # as `.<name>` or `? <name>`), production lib/ reads it across member boundaries. gen-merge reads gen-types'
  # `__typeSelf` (6 files), `__sealed` (6) and `__payload` (3); gen-schema reads `__mint` (31); gen-dispatch
  # reads gen-select's `__sel` (1). gen-demo cells read `__contract` (6) and `__mint` (15). Unpinned, a lost
  # `types.int.__typeSelf` left every gate green while gen-merge's `t ? __typeSelf` silently took its other
  # branch. It is never descended because its interior is a representation, not a name a consumer
  # addresses: a door's formals live under `__functionArgs`, and walking them would make a removed formal
  # a "lost export". A C9 tombstone cannot remedy that, and for a `__` field it is HARMFUL, because
  # `t ? __typeSelf` turns true and the read throws. A deliberate `__` removal is therefore admitted by a
  # register entry with `tombstone = false` (the register, above), never by a tombstone.
  pathsOf =
    p: v:
    builtins.concatMap (
      n:
      let
        q = render p n;
        t = builtins.tryEval (
          let
            x = v.${n};
          in
          builtins.isAttrs x && !(x ? _type) && (x.type or null) != "derivation"
        );
      in
      [ q ] ++ (if !(isDunder n) && t.success && t.value then pathsOf q v.${n} else [ ])
    ) (builtins.attrNames v);
  surfaceOf =
    k:
    let
      t = builtins.tryEval (
        let
          v = genLibs.${k};
          l =
            if builtins.isAttrs v then
              builtins.sort builtins.lessThan (pathsOf "" v)
            else
              [ (builtins.typeOf v) ];
        in
        builtins.deepSeq l l
      );
    in
    if t.success then t.value else [ "<throws>" ];

  surface = builtins.listToAttrs (
    map (k: {
      name = k;
      value = surfaceOf k;
    }) memberKeys
  );

  # Hand-maintained on the SAME contract as `expectedKeys`: the moved member's paths move in the same
  # commit as the pin bump that moved them, so this stays a tripwire rather than silent drift. A member
  # with no entry drifts by construction (`or null`): a new roster member is pinned or it is named, never
  # defaulted into agreement. The pin is a SET of name-paths per member (`ci/surface-paths.nix`), so a
  # drift names the paths that moved, at any depth, and a nested rename (`show.cell` → `show.node`) is a
  # drift where the top-level hash it replaced was blind to it.
  #
  # ★ A LOST PATH IS NOT RE-PINNED AWAY. C9 (law batch v1; ADR-0011's rider): a renamed or retired export
  # keeps a refused-by-name alias, a registered tombstone, which is still a published path. So a pinned
  # path the live surface no longer publishes is an unaliased loss, and `surface-kept` refuses it by
  # name. The one regeneration route, `surfaceRepin`, writes the UNION of the pin and the live paths:
  # it adds what a bump gained and never drops what it lost, so the routine re-pin cannot accept a loss
  # (the hash re-pin did, at gen-aspects 84400bf, `includeSitesOfEntry`). A path leaves the pin only by
  # a hand deletion of its line, the act that retires its tombstone and its register entry with it. A
  # `__` path has no tombstone (the walk's header says why): its deliberate removal is admitted by a
  # register entry with `tombstone = false`, and its pin line stays as the record.
  # Regenerate one member through THIS flake, which resolves every member from the root `flake.lock`:
  #   nix eval ./ci#lib.mkGenLibsEval.surfaceRepin.<key> --json
  expectedSurface = import ./surface-paths.nix;

  # EXPORTED below, and that export is the only route that regenerates the pin: per member, the pin's
  # paths and the live ones, sorted, so it never drops a lost path (above).
  repinOf =
    expected: surf:
    builtins.mapAttrs (k: live: builtins.attrNames (setOf ((expected.${k} or [ ]) ++ live))) surf;
  # a list of strings as a set; its `attrNames` is the sorted, de-duplicated list
  setOf =
    xs:
    builtins.listToAttrs (
      map (x: {
        name = x;
        value = null;
      }) xs
    );
  surfaceRepin = repinOf expectedSurface surface;
  # ── THE PREDICATE ──
  #
  # Lifted to a function of its two inputs so a SEEDED world runs THIS code and not a copy of it.
  # That is the arming construction `direction-of-dependence.nix` states and `sole-evaluator.nix`
  # repeats. Per drifted member, the paths it LOST (pinned, no longer published) and GAINED (published,
  # unpinned); a member with no pin entry drifts with every path gained, the `or null` arm that keeps a
  # new roster member from defaulting into agreement. `admitted` is the register's removal entries per
  # member: a pinned path they name is not lost, and the pin keeps its line as the record.
  driftOf =
    admitted: expected: surf:
    let
      one =
        k:
        let
          pin = expected.${k} or null;
          live = setOf surf.${k};
          pinned = setOf (if pin == null then [ ] else pin);
          gone = setOf (admitted.${k} or [ ]);
        in
        {
          lost = if pin == null then [ ] else builtins.filter (q: !(live ? ${q}) && !(gone ? ${q})) pin;
          gained = builtins.filter (q: !(pinned ? ${q})) surf.${k};
          unpinned = pin == null;
        };
      all = builtins.mapAttrs (k: _: one k) surf;
    in
    builtins.removeAttrs all (
      builtins.filter (k: !(all.${k}.unpinned || all.${k}.lost != [ ] || all.${k}.gained != [ ])) (
        builtins.attrNames all
      )
    );
  lostOf = d: builtins.concatMap (k: map (q: "${k}.${q}") d.${k}.lost) (builtins.attrNames d);

  surfaceDriftNames = driftOf admittedRemovals expectedSurface surface;
  surfaceDrift = builtins.attrNames surfaceDriftNames;
  surfaceLost = lostOf surfaceDriftNames;
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
  # The fixture is a LIBRARY, so the arming runs the walk too: a nested namespace, a `__functor` set
  # (descended), a `__` protocol field (a leaf, not descended), a `_type` value and a throwing tombstone
  # (leaves).
  armLib = {
    alpha = {
      one = 1;
      two = 2;
      ns = {
        cell = 1;
        node = 2;
        __contract = {
          required = [ ];
        };
      };
      door = {
        __functor = _: x: x;
        step = 1;
      };
      opt = {
        _type = "option";
        inner = 1;
      };
      gone = throw "alpha: gone";
    };
    beta = {
      three = 3;
    };
  };
  noContract = builtins.removeAttrs armLib.alpha.ns [ "__contract" ];
  armSurface = builtins.mapAttrs (_: v: builtins.sort builtins.lessThan (pathsOf "" v)) armLib;
  armPin = armSurface;
  armWith =
    alpha:
    builtins.mapAttrs (_: v: builtins.sort builtins.lessThan (pathsOf "" v)) (
      armLib // { inherit alpha; }
    );
  arming = {
    # The walk itself: the paths above, `ns.__contract` and `door.__functor` as leaves, and none of
    # `ns.__contract.required` or `opt.inner`.
    walk = armSurface.alpha;
    # The positive control on the refusals below: without it a `driftOf` that named EVERY member
    # would satisfy them all and the arming would certify a predicate that never agrees.
    clean = driftOf { } armPin armSurface;
    added = driftOf { } armPin (armWith (armLib.alpha // { four = 4; }));
    removed = lostOf (driftOf { } armPin (armWith (builtins.removeAttrs armLib.alpha [ "two" ])));
    # The nested rename with no alias (`ns.cell` → `ns.cellNode`): the class a top-level pin cannot see.
    renamedNested = lostOf (
      driftOf { } armPin (
        armWith (
          armLib.alpha
          // {
            ns = builtins.removeAttrs armLib.alpha.ns [ "cell" ] // {
              cellNode = 1;
            };
          }
        )
      )
    );
    # The same rename under C9: `ns.cell` kept as a throwing tombstone. Nothing is lost; the new name
    # is a gain the re-pin takes.
    aliasedNested = driftOf { } armPin (
      armWith (
        armLib.alpha
        // {
          ns = armLib.alpha.ns // {
            cell = throw "alpha: ns.cell is ns.cellNode";
            cellNode = 1;
          };
        }
      )
    );
    unpinned = driftOf { } (builtins.removeAttrs armPin [ "alpha" ]) armSurface;
    # A `__` field lost reds by name; the same loss with its removal admitted (the register's
    # `tombstone = false` form) loses nothing.
    removedDunder = lostOf (driftOf { } armPin (armWith (armLib.alpha // { ns = noContract; })));
    removedDunderAdmitted = driftOf { alpha = [ "ns.__contract" ]; } armPin (
      armWith (armLib.alpha // { ns = noContract; })
    );
    # The removal form is open to `__` paths only.
    removalScope = map pathIsDunder [
      "__x"
      "ns.__contract"
      "show.cell"
      "ns.\"__x.y\""
    ];
    # The re-pin keeps a lost path: the routine route cannot accept a loss.
    repinKeepsLost = builtins.elem "two" (
      (repinOf armPin (armWith (builtins.removeAttrs armLib.alpha [ "two" ]))).alpha
    );
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
  # framework might declare. `surface-pinned` cannot see this class: it pins which name-paths
  # exist, not the words they spell, and a den word sits as readily in a formal.
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
    # C9 at every depth: no pinned path is lost without its refused-by-name alias (den-hoag-hr4yg).
    surface-kept = surfaceLost == [ ];
    # ARMING — the comparison itself, over the synthetic fixture. A failing key here is the arming
    # having stopped firing, and it is RED: a guard that can no longer refuse is not a passing guard.
    arming-surface-walk =
      arming.walk == [
        "door"
        "door.__functor"
        "door.step"
        "gone"
        "ns"
        "ns.__contract"
        "ns.cell"
        "ns.node"
        "one"
        "opt"
        "two"
      ];
    arming-drift-silent-on-agreement = arming.clean == { };
    arming-drift-names-added =
      arming.added == {
        alpha = {
          lost = [ ];
          gained = [ "four" ];
          unpinned = false;
        };
      };
    arming-drift-names-removed = arming.removed == [ "alpha.two" ];
    arming-drift-names-nested-loss = arming.renamedNested == [ "alpha.ns.cell" ];
    arming-drift-alias-loses-nothing =
      arming.aliasedNested == {
        alpha = {
          lost = [ ];
          gained = [ "ns.cellNode" ];
          unpinned = false;
        };
      };
    arming-drift-names-unpinned = builtins.attrNames arming.unpinned == [ "alpha" ];
    arming-repin-keeps-lost = arming.repinKeepsLost;
    arming-drift-names-dunder-loss = arming.removedDunder == [ "alpha.ns.__contract" ];
    arming-drift-admits-removal = arming.removedDunderAdmitted == { };
    arming-removal-dunder-only =
      arming.removalScope == [
        true
        true
        false
        false
      ];
    # ARMING — the pin's DOMAIN, the half `surfaceDrift` cannot see.
    arming-pin-covers-roster = pinDomain == memberKeys;
    retired-refusing = retirementFailed == [ ];
    retirement-successor-live = successorDead == [ ];
    arming-successor-names-dead =
      successorArming == [
        "alpha.older"
        "alpha.oldest"
        "alpha.stale"
        "alpha.ns.older"
      ];
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
    "surface-kept"
    "arming-surface-walk"
    "arming-drift-silent-on-agreement"
    "arming-drift-names-added"
    "arming-drift-names-removed"
    "arming-drift-names-nested-loss"
    "arming-drift-alias-loses-nothing"
    "arming-drift-names-unpinned"
    "arming-repin-keeps-lost"
    "arming-drift-names-dunder-loss"
    "arming-drift-admits-removal"
    "arming-removal-dunder-only"
    "arming-pin-covers-roster"
    "retired-refusing"
    "retirement-successor-live"
    "arming-successor-names-dead"
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
    successorDead
    successorArming
    ;
  # ALIASED, not restated: the report's `inherit (g)` list takes an attribute of this LITERAL name, and
  # the binding above is `ruledRetirement`. The register prints on every run, including a run where it
  # refuses nothing — an entry that stops being printed is one nobody retires.
  retirementRegister = ruledRetirement;
  inherit
    surfaceHash
    surfaceRepin
    surfaceDrift
    surfaceDriftNames
    surfaceLost
    admittedRemovals
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
