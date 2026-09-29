# pins-compose — the pinned set COMPOSES: every roster member's own ci `tests` plane, evaluated at the
# revision this hub pins, with every roster input that ci declares bound to THIS hub's pin of it.
#
# ── WHY AN EVALUATION AND NOT A PIN CHECK ──
# The hub's pin set is the product's version: a consumer of `gen` receives exactly `gen.inputs.*`. A
# member's suite states that member's promises, and composability is the proposition that they hold
# when every other member is at the product's revision. Each member's own CI evaluates its suite
# against its own `ci/flake.lock`, so without this the hub ships a set of revisions that no evaluation
# has seen together. `pin-coherence` reading (2) compares those locks with the root and stays
# observe-only: agreement is ergonomics, and a disagreement proves no break (ADR-0014, ADR-0037). The
# owner's ruling, now ADR-0037: gen is coherent at HEAD because it promises composability, and the
# defect is the drift. This re-binds the member's TEST graph onto the product's pins, so test-graph
# drift can no longer hide a break.
#
# ── THE CONSTRUCTION ──
# `own` is the member's ci flake at the hub's pin, read by `getFlake` of the pinned source at its own
# narHash with `dir=ci` (the pure-mode form `flake.nix` uses for `gen`). Its roster-NAMED direct inputs
# are replaced by `gen.inputs.<name>`, and the member's `ci/flake.nix` `outputs` is applied to the
# result with a flake-compat-style `self` fixpoint. The root lock `follows` every roster edge of every
# roster node to root, so `gen.inputs.A.inputs.B` is `gen.inputs.B`: a member reached only through a
# sibling is re-bound too. Every OTHER input stays at the member's own ci lock.
#
# ── WHAT IS AT ONE REVISION, AND WHAT IS NOT ──
# Only the roster-NAMED inputs. A roster REPOSITORY bound under a non-roster name is deliberately left
# alone: gen-assemble's `gen-scope-unmet` is `github:sini/gen-scope` pinned by rev one commit before
# the declared vertex order landed, the fixture that arms its precondition refusal. Its closure holds
# roster libraries at non-hub revisions, and substituting it would disarm that oracle. So the closure
# is at one revision over roster-named inputs, and rev-pinned roster aliases are frozen fixtures, the
# class of the hub's own `gen-schema-orig`. Non-roster tools (gen-harness, nixpkgs, gen-differential)
# stay at each member's own lock: they are not part of the product's version. An alias WITHOUT a rev
# would track a branch and escape substitution silently; no cell refuses one yet.
#
# ── REACH ──
# Each member ci imports `../lib` with arguments taken from `inputs`, so substitution reaches the
# library under test. A ci that instead imported the root `default.nix` would resolve through the
# member's ROOT lock and bypass it; `pin-coherence`'s gating `root-plane-coherent` holds that lock at
# the hub's revision anyway.
#
# ── ONE CHECK PER MEMBER ──
# The failures of this class (a missing attribute, calling a set, `max-call-depth exceeded`) are not
# catchable by `tryEval`, so one aggregate check would die on the first and name one member. Separate
# checks let `nix flake check ./ci --keep-going` name every failing member in one run. The red is raised
# while the check's derivation is EVALUATED (the member's `checks.default` is the in-eval batch
# asserter), so no warm store output can stand in for it; a green's report records the hub revisions,
# so a pin change is a new derivation.
#
# ── WHAT IT DOES NOT COVER ──
# The error plane (`testsError`, `checks.tests-error`): the harness refuses any direct ci input whose
# in-memory revision differs from the file lock, so a substituted member cannot run it as it stands.
{
  gen,
  rosterMetaKeys,
  pkgs,
  lib,
  system,
}:
let
  # The roster of record, as `pin-coherence.nix` derives it: bare keys minus that file's
  # `rosterMetaKeys`, mapped through `"gen-" + k` (see its header for why the map is load-bearing).
  rosterKeys = builtins.attrNames (builtins.removeAttrs (gen.lib.mkGenLibs { }) rosterMetaKeys);
  memberNames = map (k: "gen-" + k) rosterKeys;
  pinned = gen.inputs;

  check =
    m:
    let
      src = pinned.${m};
      own = builtins.getFlake (
        builtins.unsafeDiscardStringContext "path:${src.outPath}?dir=ci&narHash=${src.narHash}"
      );
      substituted = builtins.filter (n: builtins.elem n memberNames) (builtins.attrNames own.inputs);
      inputs = own.inputs // lib.genAttrs substituted (n: pinned.${n}) // { inherit self; };
      outputs = (import "${src.outPath}/ci/flake.nix").outputs inputs;
      self =
        own.sourceInfo
        // outputs
        // {
          # A real flake's `sourceInfo`, and its `outPath` at the flake's own directory (`<root>/ci`).
          inherit (own) sourceInfo outPath;
          inherit inputs outputs;
          _type = "flake";
        };
      # The member's own ci-lock revision, read as DATA: forcing `own.inputs.<n>.rev` would fetch
      # every roster pin that lock names, which substitution exists to avoid.
      ownLock = builtins.fromJSON (builtins.readFile "${src.outPath}/ci/flake.lock");
      # A `follows` edge is a path list, not a node name, and carries no revision of its own.
      ownRev =
        n:
        let
          node = ownLock.nodes.${ownLock.root}.inputs.${n};
        in
        if builtins.isString node then ownLock.nodes.${node}.locked.rev or null else null;
      report = builtins.toJSON {
        member = m;
        rev = src.rev;
        suites = builtins.length (builtins.attrNames outputs.tests);
        substituted = lib.genAttrs substituted (n: {
          hub = pinned.${n}.rev;
          own = ownRev n;
        });
      };
    in
    pkgs.runCommand "pins-compose-${m}"
      {
        inherit report;
        passAsFile = [ "report" ];
        # Its drvPath forces every `tests` cell at evaluation time; a failing cell is an eval error.
        tests = outputs.checks.${system}.default;
      }
      ''
        echo "── pins-compose-${m} ──"
        cat "$reportPath"
        echo
        echo "$tests"
        cp "$reportPath" "$out"
      '';
in
lib.listToAttrs (map (m: lib.nameValuePair "pins-compose-${m}" (check m)) memberNames)
