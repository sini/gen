# architecture-library-graph — binds ARCHITECTURE.md's library-graph diagram to the roster of record
# and to the members' own declared inputs.
#
# ARCHITECTURE.md's figures are hand-written and have gone stale repeatedly: a retired library left
# standing as live, a roster enumeration one member short. The failure is silent — prose does not
# evaluate, so a member can join or leave the roster and the picture stays exactly as it was.
#
# This check reads the mermaid block back out of the committed file, between the
# `<!-- gen-library-graph:begin/end -->` markers (marker-delimited and not first-fence: the document
# carries other fenced blocks), and compares it in both directions against:
#
#   NODES — `gen.lib.mkGenLibs { }`'s member keys, `gen-`-prefixed. The roster of record is
#           `lib/mkGenLibs.nix` itself, never a count (ADR-0015); `mkgenlibs-eval.nix` is the tripwire
#           on the roster, and this file consumes the same value rather than restating it.
#   EDGES — each member's DECLARED root-flake input names, the same observable
#           `direction-of-dependence.nix` reads and for the same reason: the declaration is the fact,
#           and no revision, narHash or outPath is read here. A pin bump that changes no declared name
#           changes no result.
#
# A RETIRED member may appear in the diagram ADDITIONALLY — a reader meeting the name in old code has
# to find it somewhere — but only carrying mermaid's `:::retired` class assignment, which is also what
# makes it machine-distinguishable from a live one. A live member so marked is refused by name, so the
# marking cannot be used to excuse a member out of the live set.
{
  gen,
  lib,
}:
let
  doc = builtins.readFile ../ARCHITECTURE.md;

  beginMarker = "<!-- gen-library-graph:begin -->";
  endMarker = "<!-- gen-library-graph:end -->";

  # Marker-delimited window, guarded: a missing marker reports `region-present = false` and names the
  # marker, rather than aborting the evaluation on an out-of-bounds index where the reader would meet
  # a Nix trace instead of a finding.
  beginParts = lib.splitString beginMarker doc;
  endParts = lib.splitString endMarker (lib.elemAt beginParts 1);
  regionPresent = builtins.length beginParts > 1 && builtins.length endParts > 1;
  region = if regionPresent then lib.elemAt endParts 0 else "";
  regionLines = lib.splitString "\n" region;

  # ── the diagram, read back ──
  #
  # A node declaration is a whole line: an identifier, a bracketed quoted label naming the library,
  # and optionally mermaid's `:::retired` class assignment. Edge lines, `subgraph` lines and
  # `classDef` lines do not match this shape, so nothing else in the block is picked up.
  #
  # `[[]` and `[]]` rather than `\[` and `\]`: `builtins.match` is POSIX ERE, which accepts the
  # escaped OPENING bracket and refuses the escaped closing one — `builtins.match "\\[" "x"` returns
  # `null`, while `builtins.match "\\[x\\]" "x"` aborts with `invalid regular expression`. The
  # bracket-expression form is the portable spelling of a literal bracket.
  nodePattern = " *([A-Za-z0-9_]+)[[]\"(gen-[a-z-]+)\"[]](:::retired)? *";
  nodeMatches = builtins.filter (m: m != null) (map (l: builtins.match nodePattern l) regionLines);

  declaredNodes = map (m: {
    id = builtins.elemAt m 0;
    name = builtins.elemAt m 1;
    retired = builtins.elemAt m 2 != null;
  }) nodeMatches;

  liveNodes = builtins.filter (n: !n.retired) declaredNodes;
  retiredNodes = builtins.filter (n: n.retired) declaredNodes;

  declaredLive = map (n: n.name) liveNodes;
  declaredRetired = map (n: n.name) retiredNodes;

  # id → library name, over the LIVE nodes only: an edge is a statement about the roster, and an edge
  # drawn to a retired node would otherwise read as a live dependence.
  nameOfId = builtins.listToAttrs (
    map (n: {
      name = n.id;
      value = n.name;
    }) liveNodes
  );

  edgePattern = " *([A-Za-z0-9_]+) *--> *([A-Za-z0-9_]+) *";
  edgeMatches = builtins.filter (m: m != null) (map (l: builtins.match edgePattern l) regionLines);
  declaredEdges = map (m: {
    from = nameOfId.${builtins.elemAt m 0} or (builtins.elemAt m 0);
    to = nameOfId.${builtins.elemAt m 1} or (builtins.elemAt m 1);
  }) edgeMatches;

  # ── the roster of record, and the members' own declarations ──

  genLibs = gen.lib.mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)

  # `strata` is an attribute of the roster but not a member of it — the same subtraction
  # `mkgenlibs-eval.nix` makes, and for the same reason: without it the declaration reads as a
  # twenty-second library missing from the diagram.
  memberKeys = builtins.filter (k: k != "strata") (builtins.attrNames genLibs);

  # The roster keys are UNPREFIXED (`view = (input "gen-view")`); a node label names a repository, so
  # the prefix is restored here at the one place the two vocabularies meet.
  roster = map (k: "gen-${k}") memberKeys;

  genInputs = gen.inputs;
  declaredInputsOf =
    name:
    let
      i = genInputs.${name};
    in
    builtins.filter (d: lib.hasPrefix "gen-" d) (
      if i ? inputs then builtins.attrNames i.inputs else [ ]
    );

  actualEdges = builtins.concatMap (
    from: map (to: { inherit from to; }) (declaredInputsOf from)
  ) roster;

  render = e: "${e.from} --> ${e.to}";
  actualEdgeStrings = map render actualEdges;
  declaredEdgeStrings = map render declaredEdges;

  # ── the diffs, both directions, named rather than counted ──

  missing = builtins.filter (n: !(builtins.elem n declaredLive)) roster; # on the roster, not drawn
  extra = builtins.filter (n: !(builtins.elem n roster)) declaredLive; # drawn as live, not on the roster
  mismarked = builtins.filter (n: builtins.elem n roster) declaredRetired; # a live member marked retired

  edgesMissing = builtins.filter (e: !(builtins.elem e declaredEdgeStrings)) actualEdgeStrings;
  edgesExtra = builtins.filter (e: !(builtins.elem e actualEdgeStrings)) declaredEdgeStrings;
in
{
  gate = {
    region-present = regionPresent;
    graph-total = missing == [ ]; # every roster member is drawn as a live node
    graph-exact = extra == [ ]; # nothing is drawn as live that the roster does not carry
    graph-retired-marked = mismarked == [ ]; # no live member is excused by a retired marking
    edges-total = edgesMissing == [ ]; # every declared gen-to-gen input is drawn
    edges-exact = edgesExtra == [ ]; # nothing is drawn that no member declares
  };
  gateKeys = [
    "region-present"
    "graph-total"
    "graph-exact"
    "graph-retired-marked"
    "edges-total"
    "edges-exact"
  ];
  report = {
    inherit
      regionPresent
      roster
      declaredLive
      declaredRetired
      missing
      extra
      mismarked
      edgesMissing
      edgesExtra
      ;
    beginMarker = beginMarker;
    memberCount = builtins.length roster;
    declaredNodeCount = builtins.length declaredNodes;
    actualEdgeCount = builtins.length actualEdges;
    declaredEdgeCount = builtins.length declaredEdges;
  };
}
