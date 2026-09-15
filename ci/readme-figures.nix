# readme-figures — binds README.md's spelled-out roster-count figures to the roster of record and to
# the members' own declared structure (den-hoag-hub-readme-roster-count-words-k4ufw).
#
# WHAT WENT WRONG. Five sentences state a count against the roster — "N of the M roster
# libraries/members/flakes/repos" — and every one was wrong on the denominator: the roster is 21, and
# every site said 22 or 23. Because each figure was spelled in WORDS ("twenty-two"), it was invisible
# to every digit-anchored figure oracle this ecosystem has built (`gen-scope`'s own
# `readme-figures.nix`, the landed precedent this file follows, among them) — the drift went uncaught
# for exactly that reason. Converting to digits is necessary but not sufficient: a re-derived numeral
# with no oracle just re-creates the same silent-drift shape one edit later, which is why this file
# exists rather than a one-off correction.
#
# ★ THE NUMERATOR TRAP, live at the one site with a NAMED exception. The purity-scanner sentence used
# to read "21 of 22 ... carry it. gen-prelude needs none", naming gen-prelude as the sole holdout. But
# gen-prelude's own `ci/tests/purity.nix` (added 2026-09-01, a real scan of its own source — not a
# vacuous stand-in) makes that exception FALSE as well as the denominator: all 21 carry it. A repair
# that only fixed 22→21 while keeping gen-prelude as the named exception would have landed "20 of 21",
# wrong in the same way the layout spec's `gen-types`-filename miss was wrong (den-hoag-4dfsv) — a
# numeral asserted without checking the predicate it claims to report. ⇒ every count below is read
# from the roster's siblings directly, never carried over from the old prose by arithmetic alone.
{
  gen,
  genInputs,
  lib,
}:
let
  doc = builtins.readFile ../README.md;

  # ── the roster of record, the same subtraction every check here makes ──
  genLibs = gen.lib.mkGenLibs { };
  memberKeys = builtins.filter (k: k != "strata") (builtins.attrNames genLibs);
  names = map (k: "gen-" + k) memberKeys;
  rosterSize = builtins.length names;

  # ── reading a sibling's own tree, at CI's pin (genInputs, exactly like the checks beside this one) ──
  filesOf = d: if builtins.pathExists d then builtins.attrNames (builtins.readDir d) else [ ];
  fileAt = f: if builtins.pathExists f then builtins.readFile f else "";

  # "Carries a purity scanner": some `*purity*.nix` under `ci/tests/` — concept-bound, not the literal
  # filename `purity.nix`, which is exactly what missed gen-types's `types-purity.nix` at the sibling
  # site (den-hoag-4dfsv).
  carriesPurity =
    n:
    lib.any (f: lib.hasSuffix ".nix" f && lib.hasInfix "purity" f) (
      filesOf "${genInputs.${n}}/ci/tests"
    );
  purityMissing = builtins.filter (n: !carriesPurity n) names;
  purityCarriers = rosterSize - builtins.length purityMissing;

  # "Declares a `.lib` output": the resolved flake input itself carries the attribute — the same
  # observable the hub's own re-export reads, never a revision.
  libMissing = builtins.filter (n: !(genInputs.${n} ? lib)) names;
  libDeclarers = rosterSize - builtins.length libMissing;

  # "Gates on gen-harness's mkCi with a GitHub Actions workflow": `ci/flake.nix` cites `mkCi` and
  # `.github/workflows/` is non-empty.
  usesMkCi = n: lib.hasInfix "mkCi" (fileAt "${genInputs.${n}}/ci/flake.nix");
  hasWorkflow = n: filesOf "${genInputs.${n}}/.github/workflows" != [ ];
  mkCiMissing = builtins.filter (n: !(usesMkCi n && hasWorkflow n)) names;
  mkCiGated = rosterSize - builtins.length mkCiMissing;

  # "Carries an AGENTS.md sheet", roster plus the hub itself.
  carriesAgents = n: builtins.pathExists "${genInputs.${n}}/AGENTS.md";
  agentsMissing = builtins.filter (n: !carriesAgents n) names;
  hubCarriesAgents = builtins.pathExists ../AGENTS.md;
  agentsCarriers = (rosterSize - builtins.length agentsMissing) + (if hubCarriesAgents then 1 else 0);
  agentsDenominator = rosterSize + 1;

  # The two members the hub wires by a raw `import ".../lib"` rather than reading `.lib` — named in
  # the prose itself, so the check that matters is that BOTH names still sit on the live roster,
  # rather than re-deriving the pair from `mkGenLibs.nix`'s source (which the DELETION-GROUND OUT
  # clause keeps this row from editing, and which a source-text regex would only re-describe less
  # reliably than the roster membership test below already does).
  namedDirectImportExceptions = [
    "class"
    "assemble"
  ];
  exceptionsOnRoster = builtins.all (e: builtins.elem e memberKeys) namedDirectImportExceptions;
  directLibReaders = rosterSize - builtins.length namedDirectImportExceptions;

  # ── the five sentences, read back out of the committed README ──
  #
  # POSIX ERE: a literal parenthesis is backslash-escaped (`\(`/`\)`), the inverse of the bracket rule
  # `architecture-library-graph.nix` documents — measured here, not assumed.
  spansOf = re: s: lib.filter builtins.isList (builtins.split re s);
  readingOf = pattern: map (span: map lib.toInt span) (spansOf pattern doc);

  rules = [
    {
      label = "purity-carriers";
      pattern = "All ([0-9]+) roster libraries carry it, including";
      expected = [ [ purityCarriers ] ];
    }
    {
      label = "lib-direct-reads";
      pattern = "for ([0-9]+) of the ([0-9]+) roster members";
      expected = [
        [
          directLibReaders
          rosterSize
        ]
      ];
    }
    {
      label = "lib-output-declared";
      pattern = "All ([0-9]+) library flakes declare it today";
      expected = [ [ libDeclarers ] ];
    }
    {
      label = "mkci-gated";
      pattern = "All ([0-9]+) library repos build their `ci/flake[.]nix`";
      expected = [ [ mkCiGated ] ];
    }
    {
      label = "agents-md-all";
      pattern = "All ([0-9]+) repositories \\(the hub included\\) carry";
      expected = [ [ agentsCarriers ] ];
    }
  ];

  disagreeing = lib.filter (r: readingOf r.pattern != [ ] && readingOf r.pattern != r.expected) rules;
  unreached = lib.filter (r: readingOf r.pattern == [ ]) rules;

  # ── the scan discriminates: a synthetic pair differing only in the figure ──
  firstRule = builtins.head rules;
  syntheticFresh = "All ${toString purityCarriers} roster libraries carry it, including gen-prelude.";
  syntheticStale = "All ${toString (purityCarriers + 1)} roster libraries carry it, including gen-prelude.";
in
{
  gate = {
    figures-agree = disagreeing == [ ]; # every sentence's digits equal the live count
    every-rule-reaches = unreached == [ ]; # every pattern matches at least one span of the shipped README
    scan-accepts-correct =
      readingOf firstRule.pattern != [ ]
      && (map (s: map lib.toInt s) (spansOf firstRule.pattern syntheticFresh)) == firstRule.expected;
    scan-refuses-wrong =
      (map (s: map lib.toInt s) (spansOf firstRule.pattern syntheticStale)) != firstRule.expected;
    purity-all-covered = purityMissing == [ ]; # backs the "All ... including gen-prelude" wording
    lib-output-all-covered = libMissing == [ ];
    mkci-all-covered = mkCiMissing == [ ];
    agents-all-covered = agentsMissing == [ ] && hubCarriesAgents;
    exceptions-on-roster = exceptionsOnRoster; # gen-class / gen-assemble are still live roster members
  };
  gateKeys = [
    "figures-agree"
    "every-rule-reaches"
    "scan-accepts-correct"
    "scan-refuses-wrong"
    "purity-all-covered"
    "lib-output-all-covered"
    "mkci-all-covered"
    "agents-all-covered"
    "exceptions-on-roster"
  ];
  report = {
    inherit
      rosterSize
      purityCarriers
      purityMissing
      libDeclarers
      libMissing
      mkCiGated
      mkCiMissing
      agentsCarriers
      agentsMissing
      hubCarriesAgents
      agentsDenominator
      directLibReaders
      namedDirectImportExceptions
      ;
    disagreeing = map (r: r.label) disagreeing;
    unreached = map (r: r.label) unreached;
  };
}
