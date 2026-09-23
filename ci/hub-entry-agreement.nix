# hub-entry-agreement — the hub's two published entry paths give one query one answer.
#
# ── WHAT THIS IS FOR ──
# The hub publishes two ways in: `import <gen> { }`, the L1 standalone root a non-flake consumer
# reaches, and `(getFlake <gen>).lib.mkGenLibs { }`, the two-stage flake surface a flake consumer
# reaches. They are two SUPPLIERS of one construction, so a library answering differently through
# them is the failure itself (`den-hoag-hub-entry-paths-disagree-silently-oii6u`). The subject is a
# property of THIS tree's two entry paths, which is why the cell lives in this ci: it takes the tree
# as `gen = path:..` and adds no edge. It lived in gen-inspect's ci, which had to declare the hub to
# reach both paths while the hub pins gen-inspect — an oracle-graph cycle ADR-0037 forbids
# (den-hoag-mxbv4).
#
# ── HOW EACH ARM IS BUILT ──
# The subject is gen-inspect's published `examples/fleet`, read from the gen-inspect this ci already
# reaches, applied ONCE PER PATH to that path's own `inspect` AND its own `program`. On the standalone
# path `inspect` is gen-inspect's shim resolving its dependencies from gen-inspect's own root lock; on
# the flake path it is `.lib` applied to `lib/hubSubstrate.nix`'s `inspect`, over the hub's members.
# `program` is taken per path too: a cell that fed both arms one path's `program` read green under a
# gen-program seed on the other path (measured, den-hoag-mxbv4 spec §2.2).
#
# Each answer is FORCED AND CLASSIFIED — `tryEval (deepSeq q q)` ⇒ `{ ok = … }` or `{ threw = true }`
# — so a catchable `throw` on one path is NAMED as a disagreement instead of crashing the gate. An
# UNCATCHABLE error (a missing function argument, a missing attribute) still aborts evaluation, and
# the check then reds as a crash rather than by name.
#
# ── REACH, STATED SO IT IS NOT OVER-READ ──
# ONE-QUERY WITNESS. It asserts that the ANSWERS agree, never that the two closures do.
# The flake arm reaches every sibling at `ci/flake.lock`'s COPY of the root pins; it is the PUBLISHED
# flake path only where `lock-agreement` holds, and that cell gates direct edges only. Given a green
# `lock-agreement`, every change to either arm's value is a change to this hub commit.
# SILENT on a dependency divergence that leaves this query's answer unchanged: seeding gen-scope
# `ab21984` or gen-graph `6208e89` into both hub locks reads green here, correctly — the answers agree.
# A seed of `gen/gen-program` into `ci/flake.lock` alone reds this check as a crash; that is ci-copy
# drift, which `lock-agreement` also refuses, and not oii6u's mechanism.
# The fixture is a published example of the PINNED gen-inspect, so a change to its formals reds here
# at the next relock, as a crash.
#
# ── THE ARMING IS IN THE CELL, AND IT GATES ──
# Three seeded disagreements are evaluated on every run, each a DELTA against the live reading: the
# flake arm's fleet silenced, the flake arm's `program` replaced by a `throw`, and the standalone
# arm's fleet silenced. Each must read `paths-agree = false` while the untouched arm still answers. A
# guard that can no longer fire is not a passing guard, so an arming failure exits 1.
{ gen }:
let
  # ENTRY PATH 1 — the L1 standalone root. ENTRY PATH 2 — the published two-stage flake surface.
  hubStandalone = import "${gen}" { };
  hubFlake = gen.lib.mkGenLibs { };

  fleetOn =
    hub: silenced:
    (import "${gen.inputs.gen-inspect}/examples/fleet" {
      genInspect = hub.inspect;
      genProgram = hub.program;
      inherit silenced;
    }).inspector;

  ask =
    inspector: q:
    let
      r = builtins.tryEval (builtins.deepSeq (inspector.query q) (inspector.query q));
    in
    if r.success then { ok = r.value; } else { threw = true; };

  theQuery = "SELECT src, dst FROM edge WHERE label = 'rings'";
  expected.ok = [
    {
      src = "hemony";
      dst = "bourdon";
    }
  ];
  # A well-formed query over a known column whose value nothing carries: `[]` is an ANSWER, and the
  # live control on the same column is what says the instrument fires.
  negControl = "SELECT name FROM tocsin WHERE weight = 'NEGCTL'";
  liveControl = "SELECT name FROM tocsin WHERE weight = 'heavy'";
  liveExpected.ok = [
    { name = "angelus"; }
    { name = "bourdon"; }
  ];

  readingOn =
    { standalone, flake }:
    let
      s = ask standalone theQuery;
      f = ask flake theQuery;
    in
    {
      answers = {
        standalone = s;
        flake = f;
      };
      standalone-answers = s == expected;
      flake-answers = f == expected;
      paths-agree = s == f;
      negative-control-empty-both =
        ask standalone negControl == { ok = [ ]; } && ask flake negControl == { ok = [ ]; };
      live-control-fires-both =
        ask standalone liveControl == liveExpected && ask flake liveControl == liveExpected;
    };

  standaloneFleet = fleetOn hubStandalone false;
  flakeFleet = fleetOn hubFlake false;

  live = readingOn {
    standalone = standaloneFleet;
    flake = flakeFleet;
  };

  # ── THE SEEDS ── each replaces ONE arm and leaves the other live.
  seededSilencedFlake = readingOn {
    standalone = standaloneFleet;
    flake = fleetOn hubFlake true;
  };
  seededThrowingFlake = readingOn {
    standalone = standaloneFleet;
    flake = fleetOn (hubFlake // { program = throw "hub-entry-agreement: seeded throw"; }) false;
  };
  seededSilencedStandalone = readingOn {
    standalone = fleetOn hubStandalone true;
    flake = flakeFleet;
  };

  gate = {
    standalone-answers = live.standalone-answers;
    flake-answers = live.flake-answers;
    # THE DISAGREEMENT ITSELF, as one equality: two cells against one literal both pass if the
    # literal is what drifted; this one cannot.
    paths-agree = live.paths-agree;
    negative-control-empty-both = live.negative-control-empty-both;
    live-control-fires-both = live.live-control-fires-both;
    # Stated because if this is false, every agreement above is about one value reached twice. Names
    # alone cannot discriminate a disagreement: the silenced seeds leave them equal.
    same-roster-names = builtins.attrNames hubStandalone == builtins.attrNames hubFlake;

    # ── ARMING — a guard that cannot fire is not a passing guard ──
    arming-silenced-flake-arm =
      !seededSilencedFlake.paths-agree && seededSilencedFlake.standalone-answers;
    arming-throwing-flake-arm =
      !seededThrowingFlake.paths-agree
      && seededThrowingFlake.answers.flake == { threw = true; }
      && seededThrowingFlake.standalone-answers;
    arming-silenced-standalone-arm =
      !seededSilencedStandalone.paths-agree && seededSilencedStandalone.flake-answers;
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "the hub's two published entry paths: `import <gen> { }` and `(getFlake <gen>).lib.mkGenLibs { }`";
    property = "gen-inspect's published fleet, applied per path to that path's own `inspect` and `program`, answers one query identically on both";
    direction = "ONE-QUERY WITNESS: the answers agree, never the closures. The flake arm is the published flake path only where `lock-agreement` holds (direct edges). SILENT on dependency divergences that leave this query's answer unchanged";
    inherit (live) answers;
    arming = {
      silencedFlake = seededSilencedFlake.answers;
      throwingFlake = seededThrowingFlake.answers;
      silencedStandalone = seededSilencedStandalone.answers;
    };
  };
}
