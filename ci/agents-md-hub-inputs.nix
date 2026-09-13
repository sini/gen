# agents-md-hub-inputs — binds every roster projection AGENTS.md carries to the flake's OWN gen-*
# input set and to the hub's roster of record (den-hoag-bzcb4, successor to den-hoag-8j5b: the
# inputs block is prose and drifted once, 19-vs-21, caught only because the owner counted it by
# hand; den-hoag-0mjo7: the sheet carried the roster SIX times and the check read one of them, so
# the bound block passed while every unbound copy was wrong).
#
# AGENTS.md publishes, for a reader who will not run Nix, four projections of the roster: the
# fenced gen-* input enumeration (`<!-- gen-inputs:begin/end -->`), the roster REGION of three
# tables — concern rows, the retired register, the sibling register (`<!-- gen-roster:begin/end -->`)
# — the stratum assignment (`<!-- gen-strata:begin/end -->`) and the Drift-check's recorded output
# (`<!-- gen-drift:begin/end -->`). Each is a DECLARED WINDOW whose content this check re-derives
# from the flake: the input set through `genInputs` (the root flake's own input SET, resolved at
# `ci/flake.lock`'s copy of its pins — the route every check in ci/flake.nix uses except
# `lock-agreement`, which reads both lock files directly because comparing them is its subject);
# each member's description from `(import "${genInputs.<name>}/flake.nix").description` (plain data,
# ADR-0014); the partition from `(gen.lib.mkGenLibs { }).strata`; the root-flake shape from `gen`
# itself. Never by re-shelling the sheet's own `nix eval --impure` command from inside a pure eval.
#
# Windows are read structurally (marker first, THEN the fence inside it), so a second ```json fence
# elsewhere in the file cannot be picked up by accident; a missing or duplicated marker THROWS,
# never reads as empty. Inside the roster region only a KNOWN header (first cell `Concern (roster
# key)`, `Former key`, `Repo`) opens a table; any other non-separator, non-backticked line is
# reported verbatim as `unknownRows` and CLOSES the current table, so the rows beneath it are never
# attributed to the table above.
#
# Text OUTSIDE the four windows, HTML comments stripped, is LIVE CONTEXT: every `gen-[a-z]+` token in
# it must be a live input, a retired-register repo, a sibling-register repo or one of the marker
# families this check and gen-harness's citations check own; and no backticked bare key from the
# retired register may appear in it (a historical sentence writes `gen-pipe`, never `pipe`). The
# arming direction: a retirement adds a register row and that row reds every backticked live-context
# mention of the key; a new member reds the inputs block, the concern table and the strata block.
# What the check cannot see, stated: unbackticked words, bare words inside a plain fence outside a
# window, and counts in prose (the sheet carries none of the first two; the counts were deleted, not
# checked — ADR-0015).
#
# ★ WHICH PINS: the live set and the descriptions are read at `ci/flake.lock`'s copy of the `gen`
# node's inputs (den-hoag-y21zz), so a root-input removal is silent here until the ci relock that
# `ci/lock-agreement.nix` already requires.
{
  gen, # the hub itself (`path:..`): the roster of record and the root-flake shape
  genInputs,
  lib,
}:
let
  agentsSheet = builtins.readFile ../AGENTS.md;

  # ── declared windows ──
  window =
    begin: end: text:
    let
      p = lib.splitString begin text;
    in
    if builtins.length p != 2 then
      throw "marker ${begin}: expected exactly 1, found ${toString (builtins.length p - 1)}"
    else
      let
        q = lib.splitString end (builtins.elemAt p 1);
      in
      if builtins.length q != 2 then
        throw "marker ${end}: expected exactly 1, found ${toString (builtins.length q - 1)}"
      else
        {
          inside = builtins.elemAt q 0;
          outside = builtins.elemAt p 0 + "\n" + builtins.elemAt q 1;
        };
  markerOf = f: "<!-- ${f}:begin -->";
  endOf = f: "<!-- ${f}:end -->";

  wInputs = window (markerOf "gen-inputs") (endOf "gen-inputs") agentsSheet;
  wRoster = window (markerOf "gen-roster") (endOf "gen-roster") wInputs.outside;
  wStrata = window (markerOf "gen-strata") (endOf "gen-strata") wRoster.outside;
  wDrift = window (markerOf "gen-drift") (endOf "gen-drift") wStrata.outside;

  # A comment may contain `>`; ERE has no lazy quantifier, so "anything but `-->`" is spelled out.
  stripComments =
    t:
    builtins.concatStringsSep "" (
      builtins.filter builtins.isString (builtins.split "<!--([^-]|-[^-]|--[^>])*-->" t)
    );
  liveCtx = stripComments wDrift.outside; # everything outside the four declared windows

  matchesOf =
    re: t: lib.unique (map builtins.head (builtins.filter builtins.isList (builtins.split re t)));
  fenceJson =
    w: builtins.elemAt (lib.splitString "```" (builtins.elemAt (lib.splitString "```json" w) 1)) 0;
  fencePlain = w: lib.trim (builtins.elemAt (lib.splitString "```" w) 1);

  # ── the roster region: three tables, told apart by their header's first cell ──
  cellsOf =
    l:
    let
      cs = lib.splitString "|" l;
    in
    map lib.trim (lib.sublist 1 (builtins.length cs - 2) cs);
  rows = builtins.filter (l: lib.hasPrefix "|" l) (lib.splitString "\n" wRoster.inside);
  knownTables = [
    "Concern (roster key)"
    "Former key"
    "Repo"
  ];
  tagged =
    builtins.foldl'
      (
        acc: l:
        let
          c = cellsOf l;
          h = builtins.head c;
        in
        if builtins.elem h knownTables then
          acc // { cur = h; }
        else if lib.hasPrefix "-" h then
          acc
        else if lib.hasPrefix "`" h && acc.cur != null then
          acc
          // {
            out = acc.out ++ [
              {
                table = acc.cur;
                cells = c;
              }
            ];
          }
        else
          acc
          // {
            cur = null;
            unknown = acc.unknown ++ [ l ];
          }
      )
      {
        cur = null;
        out = [ ];
        unknown = [ ];
      }
      rows;
  ofTable = h: map (r: r.cells) (builtins.filter (r: r.table == h) tagged.out);
  unknownRows = tagged.unknown; # the offending lines, verbatim

  tick =
    c:
    let
      m = builtins.match "`([^`]*)`.*" c;
    in
    if m == null then throw "cell not backticked: ${c}" else builtins.head m;
  quoted =
    c:
    let
      m = builtins.match ".*\"(.*)\"" c;
    in
    if m == null then throw "cell carries no quoted description: ${c}" else builtins.head m;
  # A table cell is CommonMark, and a backslash before ASCII punctuation is an escape (CommonMark
  # §2.4): the formatter writes a `<` inside a cell as `\<`. The description compared is the cell's
  # TEXT, escapes decoded — what the reader sees, and the flake's description verbatim.
  unescape =
    s:
    builtins.concatStringsSep "" (
      map (x: if builtins.isList x then builtins.head x else x) (builtins.split "\\\\([[:punct:]])" s)
    );

  concern = map (c: {
    key = tick (builtins.elemAt c 0);
    repo = tick (builtins.elemAt c 1);
    desc = unescape (quoted (builtins.elemAt c 1));
  }) (ofTable "Concern (roster key)");
  retired = map (c: {
    key = tick (builtins.elemAt c 0);
    repo = tick (builtins.elemAt c 1);
  }) (ofTable "Former key");
  sibling = map (c: { repo = tick (builtins.elemAt c 0); }) (ofTable "Repo");

  # ── the flake's side of every window ──
  actual = builtins.filter (n: lib.hasPrefix "gen-" n) (builtins.attrNames genInputs);
  actualKeys = map (lib.removePrefix "gen-") actual;
  descriptions = lib.genAttrs actual (n: (import "${genInputs.${n}}/flake.nix").description);
  roster = gen.lib.mkGenLibs { };
  strata = roster.strata;
  driftShape = {
    outputs = builtins.attrNames gen.outputs;
    lib = builtins.attrNames gen.lib;
    flakeModules = builtins.attrNames gen.flakeModules;
    roster = builtins.attrNames roster;
  };

  concernKeys = map (r: r.key) concern;
  retiredKeys = map (r: r.key) retired;
  retiredRepos = map (r: r.repo) retired;
  siblingRepos = map (r: r.repo) sibling;
  # The marker families are this check's own vocabulary (and gen-harness's), not repositories.
  markerFamilies = [
    "gen-inputs"
    "gen-roster"
    "gen-strata"
    "gen-drift"
    "gen-citations"
  ];
  registered = actual ++ retiredRepos ++ siblingRepos ++ markerFamilies;

  # ── the inputs block (the original predicate, unchanged) ──
  documented = builtins.fromJSON (fenceJson wInputs.inside);
  missing = builtins.filter (n: !(builtins.elem n documented)) actual; # in the flake, not the sheet
  extra = builtins.filter (n: !(builtins.elem n actual)) documented; # in the sheet, not the flake

  # ── the roster region ──
  concernMissing = builtins.filter (k: !(builtins.elem k concernKeys)) actualKeys;
  concernExtra = builtins.filter (k: !(builtins.elem k actualKeys)) concernKeys;
  concernRepoDrift = builtins.filter (r: r.repo != "gen-${r.key}") concern;
  concernDescDrift = builtins.filter (
    r: !(descriptions ? ${r.repo}) || r.desc != descriptions.${r.repo}
  ) concern;
  retiredStillLive = builtins.filter (
    r: builtins.elem r.key actualKeys || builtins.elem r.repo actual
  ) retired;
  siblingStillLive = builtins.filter (r: builtins.elem r.repo actual) sibling;

  # ── the live context ──
  unregistered = builtins.filter (n: !(builtins.elem n registered)) (
    matchesOf "(gen-[a-z]+)" liveCtx
  );
  retiredInLiveContext = builtins.filter (k: builtins.elem k retiredKeys) (
    matchesOf "`([a-z]+)`" liveCtx
  );

  # ── the Drift-check record and the stratum assignment ──
  driftDocumented = lib.trim (fenceJson wDrift.inside);
  driftActual = builtins.toJSON driftShape;
  # One line per non-empty bucket, buckets sorted, keys sorted, `<bucket>  <keys>`; an empty bucket
  # has no line. No hand list of bucket names: the buckets are `attrValues strata`.
  buckets = lib.unique (lib.sort lib.lessThan (builtins.attrValues strata));
  strataActual = builtins.concatStringsSep "\n" (
    map (
      b:
      "${b}  ${
        builtins.concatStringsSep " " (builtins.filter (k: strata.${k} == b) (builtins.attrNames strata))
      }"
    ) buckets
  );
  strataDocumented = fencePlain wStrata.inside;
in
{
  gate = {
    sheet-total = missing == [ ]; # every actual gen-* input is named in the inputs block
    sheet-exact = extra == [ ]; # the block names nothing the flake doesn't actually have
    sheet-ordered = documented == actual; # byte-for-byte: same set AND same order
    roster-tables-known = unknownRows == [ ]; # only the three known headers open a table in the region
    concern-total = concernMissing == [ ]; # every live member has a concern row
    concern-exact = concernExtra == [ ]; # no concern row names a non-member
    concern-repo = concernRepoDrift == [ ]; # each row's repo is `gen-<key>`
    concern-description = concernDescDrift == [ ]; # each description is that input's flake.nix description
    retired-not-live = retiredStillLive == [ ]; # no registered retirement is a live input
    sibling-not-live = siblingStillLive == [ ]; # no registered sibling is a live input
    names-registered = unregistered == [ ]; # every gen-* token in live context is live, registered or a marker family
    retired-not-in-live-context = retiredInLiveContext == [ ]; # no backticked retired key in live context
    drift-output-exact = driftDocumented == driftActual; # the recorded JSON is the root flake's shape
    strata-assignment-exact = strataDocumented == strataActual; # the fence is the derived partition
  };
  gateKeys = [
    "sheet-total"
    "sheet-exact"
    "sheet-ordered"
    "roster-tables-known"
    "concern-total"
    "concern-exact"
    "concern-repo"
    "concern-description"
    "retired-not-live"
    "sibling-not-live"
    "names-registered"
    "retired-not-in-live-context"
    "drift-output-exact"
    "strata-assignment-exact"
  ];
  inherit
    documented
    actual
    missing
    extra
    concernMissing
    concernExtra
    unregistered
    retiredInLiveContext
    retiredKeys
    siblingRepos
    unknownRows
    driftDocumented
    driftActual
    strataDocumented
    strataActual
    ;
  concernRepoDrift = map (r: r.key) concernRepoDrift;
  concernDescDrift = map (r: r.key) concernDescDrift;
  retiredStillLive = map (r: r.key) retiredStillLive;
  siblingStillLive = map (r: r.repo) siblingStillLive;
}
