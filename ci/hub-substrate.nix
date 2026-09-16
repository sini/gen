# hub-substrate — L3: the substrate the hub hands the three roster members whose flake `.lib` is
# published UNAPPLIED (`gen-assemble`, `gen-delivery`, `gen-program`).
#
# ── WHAT THIS IS FOR ──
# specs/2026-09-16-gen-hub-assemble-injection-spec.md §1.1's defect: until `./lib/hubSubstrate.nix`
# and `flake.nix`'s fold closed it, the hub applied all three to `{ }`, so each self-fetched its own
# substrate out of its own `ci/flake.lock` instead of the hub's shared instance — ADR-0008 §1's
# single-shared-substrate invariant. ADR-0018: "an oracle that gates the component being landed
# ships with it" — this cell ships in the same commit as `./lib/hubSubstrate.nix` and the fold.
#
# ── THREE EVALUATED HALVES, READ LIVE ──
# CLASS  — which roster members publish an unapplied `.lib`, read from `genInputs` (the pin
#          `mkgenlibs-eval.nix` and `hub-entry.nix` already force); never hand-named, so a member
#          that folds its arm back into an applied set drops out on its own.
# DEMAND — each unapplied member's OWN `functionArgs`, minus the four seam formals every member
#          root publishes (`inputs`, `src`, `dep`, `wire`). The live surface, never a restatement.
# SUPPLY — `./lib/hubSubstrate.nix` applied to a probe `members` set holding every roster key as
#          `null`; read by `attrNames`, so no leaf is ever forced. A member is UNDER-SUPPLIED where
#          DEMAND names a key SUPPLY does not.
# Comparing SUPPLY against DEMAND read from this file's own hand-written copy would be `x == x`
# (hub-entry.nix's phrase for the same mistake); DEMAND here is `genInputs`' live functionArgs, the
# only place that fact is stated outside `./lib/hubSubstrate.nix` itself.
#
# ── THE TEXT ARM (§3.2) ──
# `flake.nix`'s fold is checked by TEXT, because the defect was a call-site SHAPE — a mis-keyed
# application anywhere else in the file is invisible to a class/demand/supply reading that only
# looks at `./lib/hubSubstrate.nix`. Over the comment-stripped, whitespace-flattened file text: C
# counts every APPLIED `.lib` occurrence; B counts the one permitted call-site spelling
# (`inputs."gen-${k}".lib args`, unparenthesised); PASS iff C == 1 AND B == 1. L counts the unapplied
# bare-name bindings (`x = inputs.gen-x.lib;`) and is the ARMING KEY — below 18 the predicate could
# not have distinguished a folded roster from an unfolded one, so a pass would be meaningless.
#
# `builtins.split` runs std::regex (ECMAScript-flavoured), not glibc POSIX ERE: an escaped `}`
# (`\}`) is a COMPILE ERROR under this engine though `grep -oE` accepts it identically-spelled, so
# the close brace is left bare (`}`) below — driven red on this exact string first, then fixed.
# Verified byte-identical in behaviour against `grep -oE` on 9 reconstructed candidate texts plus
# this repository's own `flake.nix`, before landing (reports/den-hoag-uqhvm-row16-build-v0.md).
#
# ── THE ARMING IS IN THE CELL, AND IT GATES ──
# Three seeds, each a DELTA against the live reading printed beside it: one member's live SUPPLY
# reading with one demanded key stripped (never `./lib/hubSubstrate.nix` itself — the seed is data,
# the code under test is real); the live flake text with one spurious applied occurrence appended;
# and `../default.nix` read under the identical text predicate as a text that could never satisfy
# it. No seed reaches for a key that might be absent by unguarded selection — every check here is
# `elem`/`attrNames`/`or`-guarded, so none needs `tryEval` to stay catchable. A guard that can no
# longer fire is not a passing guard.
{
  gen,
  genInputs,
  lib,
}:
let
  roster = gen.lib.mkGenLibs { };
  rosterKeys = builtins.attrNames (builtins.removeAttrs roster [ "strata" ]);

  seamFormals = [
    "inputs"
    "src"
    "dep"
    "wire"
  ];

  isUnapplied = k: builtins.isFunction genInputs."gen-${k}".lib;
  unappliedClass = builtins.filter isUnapplied rosterKeys;

  demandOf =
    k:
    builtins.filter (f: !(builtins.elem f seamFormals)) (
      builtins.attrNames (builtins.functionArgs genInputs."gen-${k}".lib)
    );

  # Nothing is forced: every probed value is `null`, and `./lib/hubSubstrate.nix`'s body only
  # `inherit`s attribute NAMES out of `members`, never forcing a leaf.
  probeMembers = builtins.genAttrs rosterKeys (_: null);
  supply = import ../lib/hubSubstrate.nix probeMembers;
  supplyOnOf = sup: k: builtins.attrNames (sup.${k} or { });

  rowsOn =
    sup:
    map (k: {
      member = k;
      demand = demandOf k;
      supply = supplyOnOf sup k;
      underSupplied = builtins.filter (f: !(builtins.elem f (supplyOnOf sup k))) (demandOf k);
    }) unappliedClass;

  live = rowsOn supply;
  liveUnderSupplied = builtins.filter (r: r.underSupplied != [ ]) live;

  # ── THE TEXT ARM ──
  flakeText = builtins.readFile ../flake.nix;
  defaultText = builtins.readFile ../default.nix;

  stripFullLineComments =
    s:
    builtins.concatStringsSep "\n" (
      builtins.filter (l: builtins.match "[ \t]*#.*" l == null) (
        builtins.filter builtins.isString (builtins.split "\n" s)
      )
    );
  flatten =
    s: builtins.concatStringsSep " " (builtins.filter builtins.isString (builtins.split "[ \t\n]+" s));

  occ = re: s: builtins.length (builtins.filter builtins.isList (builtins.split re s));

  # `\}` compiles under `grep -oE` and NOT under `builtins.split` (std::regex, ECMAScript-flavoured) —
  # measured directly against this repository's own edited `flake.nix` before landing. The close
  # brace is left bare (`}`) in `patB`; behaviour is otherwise identical, verified cross-instrument.
  patC = ''\.lib[^;]'';
  patB = ''inputs\."gen-\$\{k}"\.lib args[^A-Za-z0-9_'-]'';
  patL = ''inputs\.gen-[a-z-]+\.lib;'';

  readingOf =
    text:
    let
      cs = flatten (stripFullLineComments text);
      raw = flatten text;
    in
    {
      c = occ patC cs;
      b = occ patB cs;
      l = occ patL raw;
    };

  liveText = readingOf flakeText;

  # ── SEED 1 — one demanded key stripped from one member's SUPPLY reading, never from the file ──
  controlMember = builtins.head unappliedClass;
  controlKey = builtins.head (demandOf controlMember);
  seededSupply = supply // {
    ${controlMember} = removeAttrs supply.${controlMember} [ controlKey ];
  };
  seeded = rowsOn seededSupply;
  seededUnderSupplied = builtins.filter (r: r.underSupplied != [ ]) seeded;

  # ── SEED 2 — one spurious applied `.lib` occurrence appended to the live text ──
  seededText = flakeText + "\n      rogue = inputs.gen-${controlMember}.lib { };\n";
  seededReading = readingOf seededText;

  # ── SEED 3 — the identical predicate driven over the wrong file, real content, no fabrication ──
  wrongFileReading = readingOf defaultText;

  arming = {
    underSupply = {
      inherit controlMember controlKey;
      liveNamed = liveUnderSupplied == [ ];
      seededNamed = builtins.elem controlMember (map (r: r.member) seededUnderSupplied);
      seededNamesKey = builtins.elem controlKey (
        (builtins.head (builtins.filter (r: r.member == controlMember) seeded)).underSupplied
      );
      delta = (builtins.length seededUnderSupplied) == (builtins.length liveUnderSupplied) + 1;
    };
    staleCallSite = {
      livePassed = liveText.c == 1 && liveText.b == 1;
      seededFailed = !(seededReading.c == 1 && seededReading.b == 1);
      delta = seededReading.c == liveText.c + 1;
    };
    wrongFile = {
      liveArmed = liveText.l >= 18;
      wrongFileArmingFails = wrongFileReading.l < 18;
      delta = wrongFileReading.l != liveText.l;
    };
  };

  gate = {
    # ── THE INVARIANT ITSELF ──
    class-is-nonempty = unappliedClass != [ ];
    every-demanded-key-is-supplied = liveUnderSupplied == [ ];
    fold-single-application = liveText.c == 1;
    fold-permitted-call-site = liveText.b == 1;
    fold-armed = liveText.l >= 18;

    # ── ARMING — a guard that cannot fire is not a passing guard ──
    arming-under-supply =
      arming.underSupply.liveNamed
      && arming.underSupply.seededNamed
      && arming.underSupply.seededNamesKey
      && arming.underSupply.delta;
    arming-stale-call-site =
      arming.staleCallSite.livePassed && arming.staleCallSite.seededFailed && arming.staleCallSite.delta;
    arming-wrong-file =
      arming.wrongFile.liveArmed && arming.wrongFile.wrongFileArmingFails && arming.wrongFile.delta;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "`./lib/hubSubstrate.nix` (the SUPPLY) against the live `functionArgs` of the roster's unapplied members (the DEMAND), and `flake.nix`'s fold (the TEXT arm)";
    property = "every roster member whose flake `.lib` is published unapplied is supplied every substrate key it demands, applied exactly once, at the one permitted call-site spelling";
    observable = "SUPPLY: `./lib/hubSubstrate.nix` applied to a probe `members` set, read by `attrNames`. DEMAND: `builtins.functionArgs genInputs.\"gen-\${k}\".lib` minus the four seam formals. TEXT: `flake.nix`, comment-stripped and whitespace-flattened, counted for `.lib` applications (C), the one permitted spelling (B), and unapplied bare-name bindings (L, the arming key)";
    direction = "HERMETIC over SUPPLY (nothing forced past `attrNames`); forces every roster member's `.lib` for CLASS/DEMAND, the same cost `mkgenlibs-eval.nix` and `hub-entry.nix` already pay via `gen.lib.mkGenLibs { }` and `genInputs`";
    domainSource = "CLASS is read from `genInputs`, never hand-named; the roster of record is `gen.lib.mkGenLibs { }`'s formals minus `strata`, the same source `hub-entry.nix` uses";
    ceiling = "SUPPLY is checked by KEY SET, never by VALUE — a member supplied the right key bound to the WRONG instance passes here. `flake.nix` residue (a function reaching the call site through a bound name, alias, inherit or `with`-scope) is explicitly out of scope, filed separately as den-hoag-nobfq";

    inherit unappliedClass;
    rows = live;
    underSupplied = map (r: {
      inherit (r) member underSupplied;
    }) liveUnderSupplied;

    text = {
      inherit (liveText) c b l;
    };

    inherit arming;
  };
}
