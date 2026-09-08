# sole-evaluator — readiness-bar term T2(a)'s instrument: a scan for evaluation entry points outside
# gen-scope, with its domain stated (R§3.7) and armed against planted violations (R§7.2).
#
# The rule is ADR-0006's: gen-scope is the SOLE EVALUATOR and nothing else evaluates. It is written
# down in the ADRs and asserted by no CI cell anywhere in the ecosystem — the per-repository
# `purity.nix` scans forbid a nixpkgs/module-system tier and range only over their own `lib/`, and
# `direction-of-dependence.nix` beside this file ranks DECLARED INPUTS and says nothing about what a
# member computes. This file is the missing cell.
#
# ── THE RULED DOMAIN IS A PROPERTY, AND THIS INSTRUMENT APPROXIMATES IT ──
# Owner ruling, 2026-09-05: "the domain is anything that evaluates, wherever hosted". That is a
# SEMANTIC property, not a set, and it is not statically decidable (Vogt 1989 §3.3, the
# undecidability R§3.7 already rests on). Everything below is an approximation of it and never a
# definition of it. Two words therefore do two jobs here: the RULED DOMAIN is the property; the
# SCAN'S DOMAIN — `scanned`, below — is the extent this instrument ranges over, and it
# UNDER-APPROXIMATES the ruled one.
#
# ★ DIRECTION OF APPROXIMATION: COARSER, AND COARSER IS UNSOUND. The scan refuses a SUBSET of what
# satisfies the property, so its characteristic failure is the MISS — a tree that evaluates and
# reads green. The comfortable direction would be the other one: a finer, wasteful residue does
# exist (a construct named inside a string literal counts as a hit) but it is BOUNDED, printed with
# file and line, and dismissible by a person at the report, while the coarse residue leaves no trace
# at all. Three layers narrow it: the criterion, the reader's ruled exclusion, and the tree
# enumeration. A `no-second-evaluator` green is a statement about the approximation and NEVER about
# the property.
#
# ── THE REPAIRING DISCIPLINE, which is what makes an unsound gate safe to rely on ──
# ADR-0030's shape, instantiated at the three granularities the narrowing happens at:
#   (1) TREE — INSTRUMENTED. `domain-total` compares the enumerated domain against a second,
#       independently moving object (the lock). A tree the check would be blind to is RED, not
#       absent.
#   (2) FILE — NOTIFIED, not gated. The per-tree `read`/`excluded` counts and the exclusion's
#       entries print on every run, so a tree that starts publishing from a new directory moves a
#       printed number. Narrowing or widening the exclusion is one ruling.
#   (3) CRITERION — NOT INSTRUMENTED, and saying so IS the discipline. `criterion-not-dead` shows
#       the criterion matches inside gen-scope; NOTHING here bounds what it misses. The criterion's
#       width is owned by a RULING and never by an agent tuning the token list. A missed evaluator
#       is discovered by a person reading the same trees — there is no dynamic counterpart, the
#       property being about how a library is BUILT rather than about what a run DOES. At tree
#       granularity the second instrument is a lock; at criterion granularity it is the owner.
#   (4) WHEN THE TWO DISAGREE, THE PROPERTY WINS AND THE INSTRUMENT IS THE FINDING. A scanned tree
#       that evaluates through a construct the criterion does not carry is a DEFECT IN THE
#       CRITERION, repaired by widening it under (3). And the converse, which is the reading this
#       instrument meets FIRST: a tree the criterion DOES refuse is the ruled property being TRUE OF
#       THAT TREE, not instrument error to be tuned away. Narrowing the criterion until a tree
#       passes is exactly what this direction statement exists to make visible.
{
  gen,
  hubSource,
  lib,
}:
let
  roster = gen.lib.mkGenLibs { };

  # `strata` is an attribute of the roster and not a member of it — the same meta-key filter
  # `direction-of-dependence.nix` applies, for the same reason.
  rosterMetaKeys = [ "strata" ];
  members = builtins.filter (k: !(builtins.elem k rosterMetaKeys)) (builtins.attrNames roster);

  # The backtracking-free infix test. nixpkgs' `lib.hasInfix` is `match ".*<needle>.*"`, whose
  # leading and trailing `.*` backtrack to a depth proportional to the subject's length and overflow
  # the C stack on whole readFile'd source files. This scan's subjects ARE whole files, so it uses
  # the linear one the ecosystem already ships for precisely this failure.
  inherit (roster.prelude) hasInfix;

  # ── THE CRITERION, AT INTRODUCTION, WITH ITS CAUSE ──
  # ★ The owner ruled the DOMAIN, and ruled that the criterion's CONTENT is BUILT rather than ruled:
  # "Introduction scope is correct; widening stays ruled". So this list is an engineering choice made
  # once, here, and every later move of it is a RULING carrying a cause and a carrier.
  #
  # THE CHOICE: the three constructs by which a Nix expression drives an evaluation to a fixpoint —
  # `builtins.genericClosure` (a demand-driven closure), nixpkgs' `evalModules` and gen-merge's
  # `evalModuleTree` (the two module-system engines).
  #
  # THE CAUSE, measured at these pins, and the reason it is a UNION rather than one token: the three
  # single-token criteria's refusal sets are PAIRWISE DISJOINT — `{genericClosure}` refuses `graph`,
  # `{evalModules}` refuses `bind`, `{evalModuleTree}` refuses `class hub merge schema`; union six
  # trees, intersection EMPTY. So every single-construct criterion reads GREEN on trees another one
  # refuses, with nothing seeded and no plant involved: it is measurably a MISS and must not be
  # presented as the property. Taking the union is taking the coarsest-reaching measured criterion
  # that still satisfies `criterion-not-dead` — the direction the statement above demands.
  #
  # WHAT IS DELIBERATELY NOT HERE, so the next reader does not read the absence as an oversight:
  # `foldl'` refuses 16 of the 22 trees, none of which ADR-0006 measured and none of which the owner
  # has read as an evaluator — that is what a criterion WIDER than the property looks like.
  # `converge`/`fixpoint`/`maxIter` are fixpoint-iteration vocabulary that also names non-evaluating
  # helpers. And the lattice-shaped ascent criterion (`bottom` ∧ `join`/`leq` ∧ `maxIter`/`height`)
  # reaches the one surface the owner has already read as mishosted kernel computation, but at
  # gen-scope's PINNED rev no file in gen-scope exhibits the triple, so it fails `criterion-not-dead`
  # today: it would red this check as a DEAD PREDICATE rather than on the property. Each of those is
  # a widening, and a widening is a ruling.
  criterion = [
    "genericClosure"
    "evalModules"
    "evalModuleTree"
  ];

  # ADR-0006's licensed evaluator, by name. The one tree the criterion is EXPECTED to match in; a
  # match here is the licence being exercised, not a refusal.
  evaluatorKey = "scope";

  # ── THE SCAN'S DOMAIN: THE ROSTER BY EVALUATION, ∪ THE HUB ──
  # The roster is the ENUMERATOR, not a locus (owner, 2026-09-05) — it enumerates the trees to look
  # in, and it is read BY EVALUATION from the libraries' own record, `gen/lib/mkGenLibs.nix`, never
  # from a list in this file and never from a CI artefact ("ci exists in service of the libraries").
  #
  # ★ THE HUB IS INSIDE THIS DOMAIN. `gen/lib/compose.nix` calls `engine.evalModuleTree` on a live
  # line and `gen/flake.nix` publishes it as `lib.compose` by owner ruling (ADR-0031 F2), so a domain
  # that cannot SEE a published engine invocation cannot be trusted to have missed one.
  # `direction-of-dependence.nix` puts the hub outside ITS domain soundly, because that check's
  # property is member-scoped; this one's is not. A true claim at the source, false at the
  # destination.
  #
  # ★★ AND THE HUB'S SOURCE IS `self.sourceInfo.outPath`, NOT THE `gen` INPUT'S. Measured 2026-09-05:
  # the hub enters `ci/flake.lock` as `path:..`, and the PATH fetcher copies the raw directory —
  # `.git`, `.direnv`, `result` symlinks and any `.worktrees/` checkout come with it. A reader over
  # that outPath read 222 files where the tracked tree publishes 217, five of them a second checkout
  # of this very repository, and the figure moved with a developer's local state rather than with the
  # hub. `self.sourceInfo.outPath` is the git source — the tree the flake actually publishes — and it
  # is what the sibling `agents-md-citations` wiring already reaches for, for the same reason.
  scanned =
    map (k: {
      key = k;
      repo = "gen-${k}";
      src = gen.inputs."gen-${k}".outPath;
    }) members
    ++ [
      {
        key = "hub";
        repo = "gen";
        src = hubSource;
      }
    ];
  scannedKeys = map (t: t.key) scanned;

  # `declared` is derived from the roster read at the hub PLUS the hub itself — never from the walk
  # list `scanned` builds. The failure this rules out is subtle: where `declared` comes from the same
  # list the walk uses, dropping a tree from that list leaves the sum BALANCED, and a totality check
  # passes over a tree it can no longer see.
  declared = builtins.length members + 1;

  # ── THE RULED ENTRY SETS ──
  # Three of them, from ONE constructor: an entry MUST carry its key field, a `cause` and a `carrier`
  # or it is REFUSED rather than admitted; the width is asserted so an appended entry takes this
  # check red at the line naming the authority it would have to change; and every entry is PRINTED on
  # every run, including on a run where it refuses nothing — an entry that stops being printed is one
  # nobody retires.
  #
  # They are kept APART on purpose and collapsing any two would be the defect:
  #   · the EXCEPTION SET is keyed by SCANNED tree and forgives an IN-DOMAIN reading — the criterion
  #     fired and a ruling says this one is admitted anyway;
  #   · the OUT-OF-DOMAIN REGISTER is keyed by RESOLVED tree and declares a tree the criterion was
  #     never applied to. Nothing was measured there, so nothing can be forgiven there;
  #   · the READ-SCOPE EXCLUSION is keyed by DIRECTORY COMPONENT and declares source the reader does
  #     not open INSIDE a tree it does scan.
  #
  # ★ THE THREE WIDTHS ARE PINNED TO DIFFERENT AUTHORITIES. The exception set's is pinned to a RULING
  # (opened empty; 8 as of the 2026-09-08 graph ruling, den-hoag-1n3tw) and the exclusion's to a
  # RULING. THE REGISTER'S IS PINNED TO A MEASUREMENT — it
  # is 2 because 2 is what the lock resolves outside the roster today, and `domain-total` exists
  # precisely so that number can move when the lock moves. A register entry appearing or leaving is a
  # LOCK event, not a ruling event, and the width assertion on it is a NOTIFICATION rather than a
  # gate.
  mkRuledSet =
    {
      label,
      keyField,
      width,
    }:
    entries:
    let
      required = [
        keyField
        "cause"
        "carrier"
      ];
      checked = map (
        x:
        let
          missing = builtins.filter (f: !(x ? ${f}) || x.${f} == "") required;
        in
        if missing == [ ] then
          x
        else
          throw "sole-evaluator: a ${label} entry (${x.${keyField} or "?"}) omits required field(s): ${builtins.concatStringsSep ", " missing}. An entry with no stated cause and no carrier is the unbounded allow-list this check refuses."
      ) entries;
    in
    if builtins.length checked == width then
      checked
    else
      throw "sole-evaluator: the ${label} holds ${toString (builtins.length checked)} entries; its ruled width is ${toString width}. A further entry is a NEW RULING and takes this line with it.";

  # Opened empty; any tree the criterion refuses enters HERE, carrying a cause and a carrier —
  # never by quietly narrowing the criterion until the tree passes. Narrowing is invisible in a
  # report; an entry is printed on every run.
  #
  # ★ POPULATED 2026-09-08 (owner-ruled, den-hoag-1n3tw): gen-graph's 8 `genericClosure` sites are
  # `genericClosure` calls over an ALREADY-MATERIALIZED id/edge graph (ancestors/descendants/query
  # traversals), not Nix-expression evaluation to a semantic fixpoint — ADR-0008 §3 separately
  # licenses graph-native analysis queries over the graph the engine already exposes. The set's
  # own key is TREE, not site (that is the shape this constructor supports — see the "THE RULED
  # ENTRY SETS" note above), so all 8 entries carry `tree = "graph"`; each still names its exact
  # site so a NEW construct appearing anywhere else in gen-graph is not silently swept in by the
  # same ruling — a reader auditing this list against a future refusal compares by `site`, not by
  # tree membership alone.
  exceptionEntries =
    let
      graphCause = "ADR-0008 §3 graph-native analysis query over a materialized graph; owner-ruled 2026-09-08 (den-hoag-1n3tw)";
      graphCarrier = "den-hoag-1n3tw";
      graphSite = site: {
        tree = "graph";
        inherit site;
        cause = graphCause;
        carrier = graphCarrier;
      };
    in
    map graphSite [
      "lib/global.nix:161"
      "lib/query.nix:274"
      "lib/query.nix:359"
      "lib/query.nix:466"
      "lib/traverse.nix:47"
      "lib/traverse.nix:88"
      "lib/traverse.nix:100"
      "lib/traverse.nix:267"
    ];
  exceptionWidth = 8;
  mkExceptionSet = mkRuledSet {
    label = "exception set";
    keyField = "tree";
    width = exceptionWidth;
  };
  ruledException = mkExceptionSet exceptionEntries;

  registerEntries = [
    {
      resolved = "gen-harness";
      cause = "the CI extraction this gate is built from: gen-harness is the harness the hub CONSUMES, not a library of the ecosystem, and it publishes no `lib/` at its pin. Scanning it would range the property over the instrument's own scaffolding";
      carrier = "the gen-harness extraction block in ci/flake.nix";
    }
    {
      resolved = "gen-schema-orig";
      cause = "a FROZEN PRIOR REVISION of roster member `schema`, held as the golden witness for the re-host parity comparison. Scanning it would read one library twice, the second time at a revision no consumer gets";
      carrier = "ci/rehost-den-parity.nix's stated exclusion";
    }
  ];
  registerWidth = 2;
  mkRegister = mkRuledSet {
    label = "out-of-domain register";
    keyField = "resolved";
    width = registerWidth;
  };
  ruledRegister = mkRegister registerEntries;

  # Keyed by TOP-LEVEL directory component. The two entries are DERIVED and not assumed: across the
  # scanned trees at their pins the only directories holding `.nix` files at all are `lib`, `ci`,
  # `examples`, `flakeModules` and `reference`, plus tree-root files — so the exclusion is exactly
  # the check trees and the consumer demonstrations, and everything else is read.
  exclusionEntries = [
    {
      dir = "ci";
      cause = "a check tree is the instrument's own scaffolding: it carries plants and forbidden-token lists BY DESIGN, so a criterion ranging over it would refuse every repository that ships a guard";
      carrier = "OQ-6 of specs/2026-09-05-gen-sole-evaluator-scan-spec.md";
    }
    {
      dir = "examples";
      cause = "an examples tree is a CONSUMER, and a consumer legitimately calls an evaluator — that is what the ecosystem publishes one for";
      carrier = "OQ-6 of specs/2026-09-05-gen-sole-evaluator-scan-spec.md";
    }
  ];
  exclusionWidth = 2;
  mkExclusion = mkRuledSet {
    label = "read-scope exclusion";
    keyField = "dir";
    width = exclusionWidth;
  };
  ruledExclusion = mkExclusion exclusionEntries;
  excludedDirs = map (e: e.dir) ruledExclusion;

  # ── THE READER ──
  # ★ IT HAS NO SCOPE OF ITS OWN: its extent is THE TREE MINUS THE RULED EXCLUSION. A scope written
  # into the walk is invisible — a published surface outside `lib/` would be unread, unnamed, and
  # undetectable by `domain-total`, which is total at TREE granularity and cannot see inside one.
  walk =
    prefix: dir:
    lib.concatLists (
      lib.mapAttrsToList (
        entry: type:
        if type == "directory" then
          walk "${prefix}${entry}/" (dir + "/${entry}")
        else if lib.hasSuffix ".nix" entry then
          [ "${prefix}${entry}" ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  topEntries = src: lib.mapAttrsToList (entry: type: { inherit entry type; }) (builtins.readDir src);

  namesIn =
    t:
    let
      es = topEntries t.src;
      roots = builtins.filter (e: e.type != "directory" && lib.hasSuffix ".nix" e.entry) es;
      dirs = builtins.filter (e: e.type == "directory" && !(builtins.elem e.entry excludedDirs)) es;
    in
    map (e: e.entry) roots ++ lib.concatMap (e: walk "${e.entry}/" (t.src + "/${e.entry}")) dirs;

  excludedNamesIn =
    t:
    lib.concatMap (e: walk "${e.entry}/" (t.src + "/${e.entry}")) (
      builtins.filter (e: e.type == "directory" && builtins.elem e.entry excludedDirs) (topEntries t.src)
    );

  # ── THE STRIP: `#` LINE COMMENTS AND STRING-LITERAL BODIES, INTERPOLATION-AWARE ──
  # A `#` starts a comment only OUTSIDE any string — Nix gives it no meaning inside one, so a
  # stripper that cuts on a bare `#` regardless of context truncates live code whenever a string
  # contains one (`"aspect(${a.name}#${h})"` was a real, measured instance: the naive cut read
  # that line as ending at the `#`, discarding everything after with no signal). A string's own
  # text is not evaluated code either, so it is blanked from matching for the same reason a
  # comment is — EXCEPT a `${ ... }` interpolation inside a string IS evaluated code, and
  # blanking it would be exactly the MISS this file's opening section warns against: a construct
  # reached only through a string interpolation must still be caught. Blanking replaces a
  # character with a space and NEVER a newline, so line numbers and line COUNT stay identical to
  # the raw text — the downstream `imap1` over `kept` depends on that count matching `raw`'s.
  #
  # A small stack, not one flat mode, because an interpolation nests inside a string and can
  # itself hold a nested string (`"${builtins.toString "x"}"`) or nested braces
  # (`"${f { a = 1; }}"`) — a flat mode cannot tell a nested string's closing quote from the
  # enclosing one, or an interpolation's own closing `}` from a nested attrset's. Each `interp`
  # frame therefore carries its own brace depth, and only a `}` at depth zero closes it.
  # Indented-string (`''...''`) escapes are recognised (`'''` for a literal `''`, `''$` for a
  # literal `$`, `''\<c>` for an escaped character) so none of them is misread as the terminator
  # or as an interpolation opener.
  #
  # Output is built as SEGMENTS (runs of one classification), not character-by-character, so a
  # file of ordinary size does not pay for `n` list appends: one append per MODE CHANGE, not per
  # character.
  stripText =
    text:
    let
      lines = lib.splitString "\n" text;

      # Per-CHARACTER decision, unchanged from the flat design and unit-verified there: given the
      # current frame stack / comment state and the three lookahead characters, decide this
      # character's classification and the next state. Only the SCOPE changed — one line's
      # characters, not the whole file's — because that scope is what the reach fix below needs.
      decideAt =
        s: chars: n: i:
        let
          at = j: if j >= 0 && j < n then builtins.elemAt chars j else "";
          top = lib.head s.stack;
          c = at i;
          c1 = at (i + 1);
          c2 = at (i + 2);
        in
        if s.inComment then
          {
            kind = "blank";
            stack = s.stack;
            inComment = true;
            skip = 0;
          }
        else if top.t == "top" || top.t == "interp" then
          if c == "#" then
            {
              kind = "blank";
              stack = s.stack;
              inComment = true;
              skip = 0;
            }
          else if c == "\"" then
            {
              kind = "blank";
              stack = [ { t = "dstr"; } ] ++ s.stack;
              inComment = false;
              skip = 0;
            }
          else if c == "'" && c1 == "'" then
            {
              kind = "blank";
              stack = [ { t = "istr"; } ] ++ s.stack;
              inComment = false;
              skip = 1;
            }
          else if top.t == "interp" && c == "{" then
            {
              kind = "keep";
              stack = [ (top // { depth = top.depth + 1; }) ] ++ (lib.tail s.stack);
              inComment = false;
              skip = 0;
            }
          else if top.t == "interp" && c == "}" && top.depth == 0 then
            {
              kind = "blank";
              stack = lib.tail s.stack;
              inComment = false;
              skip = 0;
            }
          else if top.t == "interp" && c == "}" then
            {
              kind = "keep";
              stack = [ (top // { depth = top.depth - 1; }) ] ++ (lib.tail s.stack);
              inComment = false;
              skip = 0;
            }
          else
            {
              kind = "keep";
              stack = s.stack;
              inComment = false;
              skip = 0;
            }
        else if top.t == "dstr" then
          if c == "\\" then
            {
              kind = "blank";
              stack = s.stack;
              inComment = false;
              skip = 1;
            }
          else if c == "\"" then
            {
              kind = "blank";
              stack = lib.tail s.stack;
              inComment = false;
              skip = 0;
            }
          else if c == "$" && c1 == "{" then
            {
              kind = "blank";
              stack = [
                {
                  t = "interp";
                  depth = 0;
                }
              ]
              ++ s.stack;
              inComment = false;
              skip = 1;
            }
          else
            {
              kind = "blank";
              stack = s.stack;
              inComment = false;
              skip = 0;
            }
        else
        # top.t == "istr"
        if c == "'" && c1 == "'" && (c2 == "'" || c2 == "$") then
          {
            kind = "blank";
            stack = s.stack;
            inComment = false;
            skip = 2;
          }
        else if c == "'" && c1 == "'" && c2 == "\\" then
          {
            kind = "blank";
            stack = s.stack;
            inComment = false;
            skip = 3;
          }
        else if c == "'" && c1 == "'" then
          {
            kind = "blank";
            stack = lib.tail s.stack;
            inComment = false;
            skip = 1;
          }
        else if c == "$" && c1 == "{" then
          {
            kind = "blank";
            stack = [
              {
                t = "interp";
                depth = 0;
              }
            ]
            ++ s.stack;
            inComment = false;
            skip = 1;
          }
        else
          {
            kind = "blank";
            stack = s.stack;
            inComment = false;
            skip = 0;
          };

      # ★ THE REACH FIX — one `lib.foldl'` per FILE CHARACTER overflows the evaluator's own C
      # stack on a real corpus file: gen-merge's `lib/modules.nix` is 98,901 bytes, well past the
      # ~60,000-element depth this project measured safe for a trivial accumulator (a `foldl'` over
      # a plain number). `lib.foldl'` forces its ACCUMULATOR to WHNF each step, which is a genuine
      # per-element C stack frame regardless of accumulator shape — it is not stack-safe without
      # bound the way the earlier probe's arithmetic case suggested; that probe measured a smaller
      # `n` than the corpus's largest file, not a different property. Splitting into an OUTER fold
      # over LINES (≈1,700 for that file, comfortably inside the measured-safe range) and an INNER
      # fold over one line's characters (≈58 on average, trivially safe even for a much longer
      # single line) keeps BOTH folds' depth far under the ceiling, for any file this scan reads.
      # A `#` comment cannot span a line by Nix's own grammar, so `inComment` is reset at every
      # line boundary by construction — no line carries it forward. `stack` (open string/
      # interpolation frames) and `skip` (a multi-character escape landing on the line's own
      # trailing newline) DO cross line boundaries, and are threaded through the outer fold.
      processLine =
        carry: lineText:
        let
          chars = lib.stringToCharacters lineText;
          n = builtins.length chars;

          step =
            s: i:
            if s.skip > 0 then
              s // { skip = s.skip - 1; }
            else
              let
                decision = decideAt s chars n i;
                closesRun = decision.kind != s.segKind;
                # Same reasoning as the file-level fold this replaces: force `stack`/`segments` to
                # WHNF HERE, one line's worth of chain at most, never deferred to the outer join.
                nextStack = decision.stack;
                nextSegments =
                  if closesRun then
                    s.segments
                    ++ [
                      {
                        start = s.segStart;
                        end = i;
                        kind = s.segKind;
                      }
                    ]
                  else
                    s.segments;
              in
              {
                stack = builtins.seq nextStack nextStack;
                inComment = decision.inComment;
                skip = decision.skip;
                segStart = if closesRun then i else s.segStart;
                segKind = decision.kind;
                segments = builtins.seq nextSegments nextSegments;
              };

          final = lib.foldl' step {
            stack = carry.stack;
            inComment = false;
            skip = carry.skip;
            segStart = 0;
            segKind = "";
            segments = [ ];
          } (if n == 0 then [ ] else lib.range 0 (n - 1));

          allSegments = final.segments ++ [
            {
              start = final.segStart;
              end = n;
              kind = final.segKind;
            }
          ];
          renderSeg =
            seg:
            let
              sub = builtins.substring seg.start (seg.end - seg.start) lineText;
            in
            if seg.kind == "keep" then
              sub
            else
              builtins.concatStringsSep "" (map (c: " ") (lib.stringToCharacters sub));
          rendered = builtins.concatStringsSep "" (map renderSeg allSegments);

          # The newline this line ends on is one of the ORIGINAL character stream's positions
          # (removed by `splitString`, not by the scan): if a multi-character escape's `skip` is
          # still counting when the line's own characters run out, that newline is the next
          # position it consumes.
          skipAfterNewline = if final.skip > 0 then final.skip - 1 else 0;
          nextRenderedLines = carry.renderedLines ++ [ rendered ];
        in
        {
          stack = final.stack;
          skip = skipAfterNewline;
          # Same amortizing force as the inner fold's `stack`/`segments`, cheap insurance at the
          # OUTER scope: this list's length is the file's LINE count, already far under the
          # measured-safe fold depth for the largest file in the corpus, but the deferred-force
          # shape that overflowed the character-level fold is exactly this shape too.
          renderedLines = builtins.seq nextRenderedLines nextRenderedLines;
        };

      finalCarry = lib.foldl' processLine {
        stack = [ { t = "top"; } ];
        skip = 0;
        renderedLines = [ ];
      } lines;
    in
    builtins.concatStringsSep "\n" finalCarry.renderedLines;

  # ★ THE READ AND THE STRIP ARE ONE STAGE PER FILE, AND EVERY WORLD BELOW SHARES IT. `raw` is kept
  # beside `kept` because a second read of the same tree is a second population that can disagree
  # with the first, and because the arming below compares stripped text against the original.
  prep =
    name: text:
    let
      raw = lib.splitString "\n" text;
      strippedText = stripText text;
      kept = lib.splitString "\n" strippedText;
    in
    {
      inherit name raw kept;
      code = strippedText;
    };

  # THE SOURCE READER, the parameter every seeded world below substitutes for.
  trueFiles = t: map (n: prep n (builtins.readFile (t.src + "/${n}"))) (namesIn t);

  # ── THE OBSERVABLE, PARAMETERISED over its criterion, its tree set and its source reader ──
  # A seeded world runs THIS code and not a copy of it. That is the arming construction, and it is
  # why the arming is not a second implementation.
  #
  # ★ A REFUSED TREE IS NAMED WITH THE FILE AND LINE OF EVERY MATCH, not with a count. The reader
  # strips comments and string-literal bodies (interpolations still scanned as code — see
  # `stripText`), but it is still a blunt substring match against real code, so a criterion CAN
  # match a library's own re-export or definition of a construct's NAME without that construct
  # being invoked there; printing the site is what lets such a reading be dismissed AT THE
  # REPORT, by a person, rather than by narrowing the criterion until the tree passes.
  #
  # The whole-file test gates the per-line one: the file-level pass is one linear comparison per
  # token per file, and only a file that hits pays for line positions.
  hitsIn =
    crit: f:
    if !(builtins.any (tok: hasInfix tok f.code) crit) then
      [ ]
    else
      lib.concatLists (
        lib.imap1 (
          i: kept: lib.optional (builtins.any (tok: hasInfix tok kept) crit) "${f.name}:${toString i}"
        ) f.kept
      );

  # ★ A WORLD IS `criterion` APPLIED TO A SOURCE READER, SCANNED ONCE. The spec's signature is
  # `classify : criterion -> readSource -> evaluator -> tree -> class`; `classOf (scanWorld crit
  # readSrc) ev` IS that function with the read and the scan hoisted out of the four call sites that
  # would otherwise re-read every tree. Hoisting changes the cost and not the predicate: `sites` is
  # `concatMap (hitsIn crit)` over exactly the files the reader returns.
  scanWorld =
    crit: readSrc:
    builtins.listToAttrs (
      map (
        t:
        let
          files = readSrc t;
          perFile = map (f: {
            inherit (f) name;
            hits = hitsIn crit f;
          }) files;
        in
        {
          name = t.key;
          value = {
            inherit files;
            sites = lib.concatMap (x: x.hits) perFile;
            # The same reading at FILE granularity. It is carried beside `sites` because the arming
            # below compares a seeded world against the live one, and a difference taken over TREES
            # cannot see a plant in a tree the live criterion already refuses.
            hitFiles = map (x: x.name) (builtins.filter (x: x.hits != [ ]) perFile);
          };
        }
      ) scanned
    );

  classOf =
    world: ev: k:
    if world.${k}.files == [ ] then
      "unreadable"
    else if k == ev then
      "evaluator"
    else if world.${k}.sites != [ ] then
      (if builtins.any (x: x.tree == k) ruledException then "excepted" else "refused")
    else
      "clean";

  classes = [
    "evaluator"
    "clean"
    "refused"
    "excepted"
    "unreadable"
  ];

  # Every class is seeded at zero, so a count of none is PRINTED rather than being an absent key. The
  # class that matters most here is the one that must read zero on a clean run.
  tally =
    world: ev: keys:
    lib.foldl' (acc: k: acc // { ${classOf world ev k} = acc.${classOf world ev k} + 1; }) (
      builtins.listToAttrs
      (
        map (c: {
          name = c;
          value = 0;
        }) classes
      )
    ) keys;

  accountedIn =
    world: ev: keys:
    lib.foldl' (a: c: a + (tally world ev keys).${c}) 0 classes;
  inClass =
    c: world: ev: keys:
    builtins.filter (k: classOf world ev k == c) keys;

  # `tree(n)` — the shape a census reads in, so a refusal set is legible on one line. The sites
  # themselves are printed beside it, keyed by tree.
  census = world: keys: map (k: "${k}(${toString (builtins.length world.${k}.sites)})") keys;
  siteMap =
    world: keys:
    builtins.listToAttrs (
      map (k: {
        name = k;
        value = world.${k}.sites;
      }) keys
    );

  # ── THE TRIPWIRE: `domain-total` ──
  # RESOLVED is read from `ci/flake.lock` — the gen-shaped ROOT inputs together with the gen-shaped
  # inputs of its `gen` node, which is what `mkGenLibs`'s `genInputs.gen-X` reaches. Deeper
  # transitive revisions of the same repository are not separately readable and are not members.
  #
  # ★★ THAT IS THE LOCK AS A TRIPWIRE, NOT AS THE DOMAIN, and the distinction is the whole point. The
  # lock does not say which trees this check ranges over; it says which trees the check would be
  # SILENTLY BLIND TO if it ranged over the roster alone. The roster ENUMERATES and the lock
  # NOTIFIES. A check that took its EXTENT from a packaging artefact would be inverted; one that
  # takes its extent from the libraries and reports a DISAGREEMENT with a lock is not.
  #
  # ★ AND IT COMPARES TWO OBJECTS. The build `resolved := scanned ∪ registered` is REJECTED here:
  # under it `unaccounted` is empty BY CONSTRUCTION and this arm can never fire — which is why the
  # rejected build's return is computed beside the real one and asserted to differ. The two objects
  # move independently: a gen-shaped input added to this CI flake grows RESOLVED and leaves the
  # roster untouched.
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  lockInputsOf =
    node:
    if lock.nodes ? ${node} && lock.nodes.${node} ? inputs then lock.nodes.${node}.inputs else { };
  genShaped = builtins.filter (n: n == "gen" || lib.hasPrefix "gen-" n);
  rootInputs = lockInputsOf lock.root;
  resolved = lib.unique (
    genShaped (builtins.attrNames rootInputs)
    ++ genShaped (builtins.attrNames (lockInputsOf (rootInputs.gen or "")))
  );

  sorted = builtins.sort (a: b: a < b);
  coveredBy = trees: register: lib.unique (map (t: t.repo) trees ++ map (e: e.resolved) register);
  unaccountedIn =
    trees: register: res:
    sorted (builtins.filter (n: !(builtins.elem n (coveredBy trees register))) res);
  unresolvedIn =
    trees: register: res:
    sorted (builtins.filter (n: !(builtins.elem n res)) (coveredBy trees register));

  # ── THE ARMING ──
  # `refused == [ ]` is an ABSENCE CLAIM, so it travels with live controls in the same run and in the
  # same instrument. Each arm below is the IDENTICAL predicate over a seeded world; each must FIRE,
  # and each fires on a different axis of the construction.

  # Axis 1 — THE SOURCE. Three plants, because the scanned set is partitioned on two axes — roster vs
  # hub, and `lib/` vs the rest of the published tree — and an arming that covers one cell of that
  # partition leaves the others unproven. `select` reads zero on every construct probed, so an arm
  # that fires there fires on the plant and not on residue; the hub outside `lib/` is the tree whose
  # membership in the domain and whose file region are BOTH new here, so the two repairs are armed at
  # their intersection; and `memo/reference/` is a roster member outside `lib/`, in a directory only
  # one tree carries, so the arm does not rest on a surface form every tree happens to share.
  #
  # The plants are appended to the READER'S OUTPUT and nothing here writes to a repository — a seeded
  # world that mutated one would hand every concurrent reader of these trees a false reading. The
  # plant text sits in THIS FILE, which lives under `ci/` and is therefore outside the read scope by
  # the ruled exclusion: the scan cannot see its own plants.
  plantBody = ''
    { declarations }:
    {
      solve = builtins.genericClosure {
        startSet = map (d: { key = d.name; inherit (d) name deps; }) declarations;
        operator = item: item.deps;
      };
    }
  '';
  plants = {
    select = [ (prep "lib/planted-evaluator.nix" plantBody) ];
    hub = [ (prep "flakeModules/planted-evaluator.nix" plantBody) ];
    memo = [ (prep "reference/planted-evaluator.nix" plantBody) ];
  };
  plantedKeys = sorted (builtins.attrNames plants);
  # The plants named as the scan names a hit: `<tree>/<file>`, derived from `plants` itself rather
  # than written out a second time beside it.
  plantedQualified = sorted (
    lib.concatMap (k: map (f: "${k}/${f.name}") plants.${k}) (builtins.attrNames plants)
  );

  # Axis 2 — THE TREE SET. A scanned tree dropped from the walk must leave `partition-total` FALSE,
  # because `declared` is derived from the roster and not from the walk list.
  seedDroppedTree = "settings";
  seedShortKeys = builtins.filter (k: k != seedDroppedTree) scannedKeys;

  # Axis 3 — READABILITY. A scanned tree publishing no readable Nix source is NAMED, never skipped,
  # and stays ACCOUNTED — an absence that leaves the partition balanced is the shape this check
  # exists to refuse.
  seedUnreadableKey = "select";

  # Axis 4 — THE CRITERION'S LIVENESS. A criterion that matches nothing anywhere returns
  # `refused = [ ]` FOR FREE — a clean green, indistinguishable at the gate from a correct tree.
  #
  # ★ THE CONTROL TOKEN IS COINED IN THE RUN AND APPEARS IN NO FILE, THIS ONE INCLUDED. It is a hash
  # of the scanned key list, so its value is not writable in advance and cannot be quoted into the
  # corpus by a later reader: a literal negative-control token, once written into a spec or a report,
  # is IN the corpus, and every later sweep quoting it gets a plausible non-zero that reads exactly
  # like a live control firing.
  deadToken = "z" + builtins.hashString "sha256" (builtins.concatStringsSep "," scannedKeys);
  deadCriterion = [ deadToken ];

  # Axis 5 — THE ENTRY-SET CONSTRUCTOR, shared by all three ruled sets. An uncaused entry, an
  # uncarried entry and an appended one must each be REFUSED; the ruled set itself must be ACCEPTED,
  # which is the positive control that makes those three refusals readings rather than a broken
  # constructor.
  #
  # ★ THE MALFORMED SEEDS MUTATE THE HEAD AND KEEP THE TAIL, so they carry the ruled width at any
  # width: a seed that also changed the count would be refused by the WIDTH line and the arm would
  # pass for the wrong cause — a control firing on the wrong cause is not a control. The exception
  # set opened empty and had no head to mutate; since the 2026-09-08 graph ruling (den-hoag-1n3tw)
  # gave it 8, all three ruled sets are non-empty and all three claim the shared constructor's
  # field arms — a conjunction that quietly skipped one set's field arms as unclaimed would be
  # reporting an arm that never ran.
  accepts = mk: entries: (builtins.tryEval (builtins.deepSeq (mk entries) true)).success;
  withoutField =
    entries: f: [ (builtins.removeAttrs (builtins.head entries) [ f ]) ] ++ builtins.tail entries;
  widenedWith =
    entries: extra:
    entries
    ++ [
      (
        extra
        // {
          cause = "an entry appended by edit rather than by ruling";
          carrier = "den-hoag-none";
        }
      )
    ];

  entrySetArms = {
    exception = {
      ruledSetAccepted = accepts mkExceptionSet exceptionEntries;
      fieldArmsClaimed = true;
      uncausedAccepted = accepts mkExceptionSet (withoutField exceptionEntries "cause");
      uncarriedAccepted = accepts mkExceptionSet (withoutField exceptionEntries "carrier");
      widenedAccepted = accepts mkExceptionSet (widenedWith exceptionEntries { tree = "select"; });
    };
    register = {
      ruledSetAccepted = accepts mkRegister registerEntries;
      fieldArmsClaimed = true;
      uncausedAccepted = accepts mkRegister (withoutField registerEntries "cause");
      uncarriedAccepted = accepts mkRegister (withoutField registerEntries "carrier");
      widenedAccepted = accepts mkRegister (widenedWith registerEntries { resolved = "gen-widget"; });
    };
    exclusion = {
      ruledSetAccepted = accepts mkExclusion exclusionEntries;
      fieldArmsClaimed = true;
      uncausedAccepted = accepts mkExclusion (withoutField exclusionEntries "cause");
      uncarriedAccepted = accepts mkExclusion (withoutField exclusionEntries "carrier");
      widenedAccepted = accepts mkExclusion (widenedWith exclusionEntries { dir = "reference"; });
    };
  };

  # Axis 6 — THE TRIPWIRE, both of its objects, seeded independently. (a) the REGISTER short by one
  # entry; (b) the LOCK gaining one gen-shaped root input while roster and register stay put. (b) is
  # the stronger arm: it is the only one that distinguishes this build from the rejected
  # `resolved := scanned ∪ registered`, which reads `domain-total=true` on the same seeded lock.
  seedRegisterShort = builtins.filter (e: e.resolved != "gen-harness") ruledRegister;
  seedResolvedWidened = resolved ++ [ "gen-widget" ];

  # Axis 7 — THE STRIP ITSELF. Comments and string bodies must stop matching, and — the arm that
  # makes this a repair rather than a preference — a construct reached only through a string
  # INTERPOLATION must still match: a stripper that blanked interpolations too would trade one
  # miss for another, exactly the direction this file's header calls unsound. `prep`/`hitsIn` are
  # the real functions the scan uses on every file; this text is not rescanned by any tree, so it
  # cannot be confused with a planted evaluator (axis 1).
  stripSoundnessText = ''
    # a line comment naming genericClosure must not count
    dstr = "a string literal naming genericClosure must not count";
    interp = "value: ''${toString (genericClosure { startSet = [ ]; operator = x: [ ]; })}";
    live = genericClosure { startSet = [ ]; operator = x: [ ]; };
  '';
  stripSoundnessSites = hitsIn criterion (prep "stripSoundness.nix" stripSoundnessText);

  # ── THE WORLDS ──
  # The live one is scanned; the three seeded ones are DERIVED from it by the same algebra the scan
  # itself obeys, so no tree is read or scanned twice. `concatMap` distributes over `++`, so the
  # planted world's sites are exactly what a rescan of `files ++ plants` returns; a site is
  # `"<file>:<line>"`, so filtering sites by file prefix is exactly what rescanning only those files
  # returns.
  liveWorld = scanWorld criterion trueFiles;
  plantedWorld = lib.mapAttrs (
    k: v:
    let
      extra = plants.${k} or [ ];
      hit = builtins.filter (f: hitsIn criterion f != [ ]) extra;
    in
    {
      files = v.files ++ extra;
      sites = v.sites ++ lib.concatMap (hitsIn criterion) extra;
      hitFiles = v.hitFiles ++ map (f: f.name) hit;
    }
  ) liveWorld;
  # The reader as it stood BEFORE the extent was widened past `lib/`, over the IDENTICAL seeded
  # world. This is the arm that makes the widening a repair rather than a preference: it must miss
  # exactly the two plants outside `lib/`, and if it ever stops missing them the comparison has gone
  # blind and this arm is red.
  libOnlyWorld = lib.mapAttrs (_: v: {
    files = builtins.filter (f: lib.hasPrefix "lib/" f.name) v.files;
    sites = builtins.filter (s: lib.hasPrefix "lib/" s) v.sites;
    hitFiles = builtins.filter (n: lib.hasPrefix "lib/" n) v.hitFiles;
  }) plantedWorld;
  unreadableWorld = liveWorld // {
    ${seedUnreadableKey} = {
      files = [ ];
      sites = [ ];
      hitFiles = [ ];
    };
  };
  deadWorld = lib.mapAttrs (
    _: v:
    let
      perFile = map (f: {
        inherit (f) name;
        hits = hitsIn deadCriterion f;
      }) v.files;
    in
    {
      inherit (v) files;
      sites = lib.concatMap (x: x.hits) perFile;
      hitFiles = map (x: x.name) (builtins.filter (x: x.hits != [ ]) perFile);
    }
  ) liveWorld;

  # ── THE VERDICTS ──
  liveRefusedKeys = inClass "refused" liveWorld evaluatorKey scannedKeys;
  liveExceptedKeys = inClass "excepted" liveWorld evaluatorKey scannedKeys;
  liveUnreadable = inClass "unreadable" liveWorld evaluatorKey scannedKeys;
  liveTally = tally liveWorld evaluatorKey scannedKeys;
  accounted = accountedIn liveWorld evaluatorKey scannedKeys;
  evaluatorSites = liveWorld.${evaluatorKey}.sites;

  # A seeded arm counts as fired only when the seeded reading EXCEEDS the live one by EXACTLY the
  # plants. `seeded == [ plant ]` — the form `direction-of-dependence.nix` uses — is sound there
  # because that check's live refusal set is empty BY DESIGN; this check's is non-empty under every
  # criterion measured, so that form would be permanently red. The set difference carries the same
  # guarantee (a count alone would pass on an arm that refused the whole domain) without the
  # precondition.
  #
  # ★★ AND THE DIFFERENCE IS TAKEN OVER FILES, NOT OVER TREES, BECAUSE A TREE-LEVEL DIFFERENCE CANNOT
  # SEE A PLANT IN AN ALREADY-REFUSED TREE. Measured here: the hub is live-refused under this
  # criterion (`lib/compose.nix`, `flakeModules/default.nix`), so the tree-level difference reads
  # `[memo, select]` and the hub plant — the one arming the two repairs at their intersection —
  # contributes NOTHING to it. The arm would then pass with a third of the arming silently dead. The
  # file-level difference names all three, is strictly stronger, and does not depend on which trees
  # the criterion happens to refuse today. The tree-level figure is still printed, as context.
  liveQualified = qualifiedOf liveWorld;
  qualifiedOf =
    world: sorted (lib.concatMap (k: map (n: "${k}/${n}") world.${k}.hitFiles) scannedKeys);
  minusLive = ks: sorted (builtins.filter (k: !(builtins.elem k liveRefusedKeys)) ks);
  minusLiveFiles = q: sorted (builtins.filter (n: !(builtins.elem n liveQualified)) q);

  liveUnaccounted = unaccountedIn scanned ruledRegister resolved;
  liveUnresolved = unresolvedIn scanned ruledRegister resolved;

  arming = {
    # The live control on every arm below: the identical predicate on the true trees.
    liveControl = liveRefusedKeys;
    liveControlFiles = liveQualified;
    plantedTrees = plantedKeys;
    plantedFiles = plantedQualified;
    seededPlanted = inClass "refused" plantedWorld evaluatorKey scannedKeys;
    # Context, not the assertion: the hub is already live-refused, so this cannot name its plant.
    seededPlantedMinusLive = minusLive (inClass "refused" plantedWorld evaluatorKey scannedKeys);
    # THE ASSERTION: every plant, named, at the granularity a live refusal cannot mask.
    seededPlantedMinusLiveFiles = minusLiveFiles (qualifiedOf plantedWorld);
    # The pre-widening reader over the SAME seeded world: it must see only the `lib/` plant.
    libOnlyReaderMinusLive = minusLive (inClass "refused" libOnlyWorld evaluatorKey scannedKeys);
    libOnlyReaderMinusLiveFiles = minusLiveFiles (qualifiedOf libOnlyWorld);
    seededShortTreeSet = {
      dropped = seedDroppedTree;
      accounted = accountedIn liveWorld evaluatorKey seedShortKeys;
      inherit declared;
      partitionTotal = accountedIn liveWorld evaluatorKey seedShortKeys == declared;
    };
    seededUnreadable = {
      tree = seedUnreadableKey;
      named = inClass "unreadable" unreadableWorld evaluatorKey scannedKeys;
      accounted = accountedIn unreadableWorld evaluatorKey scannedKeys;
    };
    seededDeadCriterion = {
      method = "sha256 of the scanned key list, coined in this run — the literal is never written down, because a written control token is IN the corpus and every later sweep quoting it reads a plausible non-zero";
      evaluatorHits = builtins.length deadWorld.${evaluatorKey}.sites;
      refused = inClass "refused" deadWorld evaluatorKey scannedKeys;
    };
    seededEntrySets = entrySetArms;
    seededDomain = {
      registerShort = unaccountedIn scanned seedRegisterShort resolved;
      lockWidened = unaccountedIn scanned ruledRegister seedResolvedWidened;
      rejectedOneObjectBuild = unaccountedIn scanned ruledRegister (coveredBy scanned ruledRegister);
    };
    seededStripSoundness = {
      sites = stripSoundnessSites;
      expected = [
        "stripSoundness.nix:3"
        "stripSoundness.nix:4"
      ];
    };
  };

  # Every key MUST be true. The check builder is handed `builtins.attrNames` of this rather than a
  # hand-kept list beside it: a second register would let an arm be added here and left out of the
  # enforced set — an unchecked arm that reads exactly like a passing one.
  #
  # ★ EACH KEY CONJOINS ITS READING WITH ITS OWN ARMING, so a failing key is EITHER the lint firing
  # OR the arming having stopped firing, and both are red — a guard that can no longer refuse is not
  # a passing guard. The `arming` block above prints every sub-arm, so which half failed is one look.
  gate = {
    # O1 — THE LINT ITSELF. Green reads: no tree in the scanned domain exhibits, at these pins, the
    # criterion this instrument carries. It NEVER reads "nothing else evaluates".
    no-second-evaluator = liveRefusedKeys == [ ];

    # O2 — the seeded world reads EXACTLY the plants and nothing else, against the live control in
    # the same run; and the pre-widening reader over that same world misses the two that sit outside
    # `lib/`, which is what makes the widened extent a repair rather than a preference.
    arming-planted-violation =
      arming.seededPlantedMinusLiveFiles == plantedQualified
      && arming.libOnlyReaderMinusLiveFiles == [ "select/lib/planted-evaluator.nix" ];

    # O3 — the classes sum to the scanned-set size DERIVED FROM THE ROSTER PLUS THE HUB, and a walk
    # short by one tree leaves that sum unbalanced rather than balanced.
    partition-total = accounted == declared && !arming.seededShortTreeSet.partitionTotal;

    # O4 — a scanned tree publishing no readable Nix source is NAMED, never skipped, and stays
    # accounted.
    unreadable-tree-named =
      liveUnreadable == [ ]
      && arming.seededUnreadable.named == [ seedUnreadableKey ]
      && arming.seededUnreadable.accounted == declared;

    # O5 — the criterion matches IN GEN-SCOPE. A criterion that matches nothing gives `refused = [ ]`
    # for free; the token coined in this run is what makes the reading a reading.
    criterion-not-dead =
      evaluatorSites != [ ]
      && arming.seededDeadCriterion.evaluatorHits == 0
      && arming.seededDeadCriterion.refused == [ ];

    # O6 — the three ruled entry sets are accepted; an uncaused, an uncarried and an appended entry
    # are each refused. All three sets are non-empty (axis 5), so field arms are claimed on all
    # three.
    exception-arms =
      builtins.all
        (
          s:
          s.fieldArmsClaimed
          && s.ruledSetAccepted
          && !s.uncausedAccepted
          && !s.uncarriedAccepted
          && !s.widenedAccepted
        )
        [
          entrySetArms.exception
          entrySetArms.register
          entrySetArms.exclusion
        ];

    # O7 — SCANNED ∪ REGISTERED == RESOLVED, the roster enumerating and the lock notifying. Armed on
    # BOTH objects, plus the rejected one-object build's return, because an arm that moved only the
    # register would pass under that build too.
    domain-total =
      liveUnaccounted == [ ]
      && liveUnresolved == [ ]
      && arming.seededDomain.registerShort == [ "gen-harness" ]
      && arming.seededDomain.lockWidened == [ "gen-widget" ]
      && arming.seededDomain.rejectedOneObjectBuild == [ ];

    # O8 — THE STRIP IS SOUND: a comment and a plain string body must stop matching, and a
    # construct reached only through a string interpolation must still match. Either half failing
    # is red — a strip that also blanked interpolations would be quieter, not safer.
    strip-sound = arming.seededStripSoundness.sites == arming.seededStripSoundness.expected;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  # The report, printed on every run. `clean` is counted and not enumerated — a name there asks
  # nothing of anyone. Every class a reader must act on is named tree by tree, with the file and line
  # of every match.
  report = {
    governs = "the hub's pinned library revisions, plus the hub itself at the tree this CI flake sits in — which has no pin, by construction";
    property = "RULED DOMAIN: anything that evaluates, wherever hosted (owner, 2026-09-05). This instrument APPROXIMATES it";
    direction = "UNDER-APPROXIMATES: it MISSES. A green is a statement about the instrument's reach and never about the property";
    observable = "the ruled criterion over comment- and string-literal-stripped published `.nix` source (a string's own text is blanked; a `\${...}` interpolation inside one is still scanned as code), every match named with its file and line";
    inherit criterion;
    criterionCause = "the three constructs by which a Nix expression drives an evaluation to a fixpoint. A UNION because the single-token refusal sets are pairwise disjoint at these pins, so every one-token criterion reads green on trees another refuses. Widening it is a RULING, never a tuning";
    evaluator = evaluatorKey;

    declaredCount = declared;
    accountedCount = accounted;
    resolvedCount = builtins.length resolved;
    tally = liveTally;

    refused = census liveWorld liveRefusedKeys;
    refusedSites = siteMap liveWorld liveRefusedKeys;
    excepted = census liveWorld liveExceptedKeys;
    exceptedSites = siteMap liveWorld liveExceptedKeys;
    unreadable = liveUnreadable;
    evaluatorSiteCount = builtins.length evaluatorSites;
    inherit evaluatorSites;

    # The tripwire, both directions, so a disagreement names which side it fell on.
    unaccounted = liveUnaccounted;
    unresolved = liveUnresolved;
    inherit resolved;

    exceptionWidthRuled = exceptionWidth;
    exceptionSet = ruledException;
    registerWidthRuled = registerWidth;
    outOfDomainRegister = ruledRegister;
    exclusionWidthRuled = exclusionWidth;
    readScopeExclusion = ruledExclusion;

    # The FILE-granularity notification: a tree that starts publishing from a new directory moves a
    # printed number here. There is no second object at file granularity to assert totality against,
    # so this is a notification and not a gate.
    perTree = map (t: {
      inherit (t) key repo;
      class = classOf liveWorld evaluatorKey t.key;
      read = builtins.length liveWorld.${t.key}.files;
      excluded = builtins.length (excludedNamesIn t);
    }) scanned;
    readCount = lib.foldl' (a: t: a + builtins.length liveWorld.${t.key}.files) 0 scanned;
    excludedCount = lib.foldl' (a: t: a + builtins.length (excludedNamesIn t)) 0 scanned;

    excludedAxis = "everything under a ruled `ci` or `examples` directory of a scanned tree; every gen-shaped tree the lock resolves that carries a register entry; every gen* repository NO lock this check resolves names, which cannot even be registered; any evaluator assembled from primitives the criterion does not name, or reached through an injected formal the caller fills. All but the last two are counted and named above";

    inherit arming;
  };
}
