{
  inputs = {
    # ── THE HUB ITSELF — and the ONLY route to a sibling library ──
    # A subflake declares no sibling pin and reaches everything through its own root. The input
    # carries the ENCLOSING REPOSITORY's name — `gen`, inside `gen` — because a `path:`
    # self-reference points at a repository like any other input, and an input's name matches the
    # repository it points at.
    #
    # The ci subflake can't `import ../lib` (that escapes its flake root), so it reaches the root
    # lib through this input, exactly like den-hoag's ci reaches den-hoag — and through
    # `gen.inputs.gen-X` it reaches every sibling AT THE ROOT flake.lock's pin. So the PURE side of
    # the byte-parity oracle (the published re-host mains), the perf bench's src set, and the
    # published `gen.lib.mkGenLibs` surface consumers get are one build of each library per
    # evaluation — by construction, rather than by two pin sets kept in agreement. Declaring the
    # siblings a second time here is exactly what let 12 of 13 of them diverge from the root.
    # Only the heavy nixpkgs is deduped.
    gen.url = "path:..";
    gen.inputs.nixpkgs.follows = "nixpkgs";

    # ── THE CI HARNESS — the machinery this gate is built from, now consumed rather than copied ──
    # gen-harness is the extraction of ci from this repository. Until now the hub kept its own copy
    # of the shared gate machinery, because the hub is not an mkCi consumer (see the pre-commit
    # block below) and the surface it needed was file layout rather than declared outputs. The copy
    # bought nothing but drift: the same repair was authored twice on four separate days, three of
    # those pairs carrying the same commit subject verbatim, and twice the second copy went stale
    # in prose while the first was fixed.
    #
    # THE TRADE, taken deliberately: this gate gains one external pin, so if gen-harness breaks the
    # hub's gate breaks with it, and a lock bump joins every harness-surface change. No cycle
    # re-opens — gen-harness declares eight inputs and all eight are tools, by construction and by
    # its own acceptance test, so this is a leaf rather than a back edge.
    #
    # The follows lines below are the whole overlap of the two input sets (six of them); without
    # them each shared tool would appear twice in this lock. gen-harness's remaining two inputs
    # (nix-unit, import-tree) serve mkCi, which this flake does not call — they arrive in the lock
    # and are never evaluated.
    gen-harness.url = "github:sini/gen-harness";
    gen-harness.inputs.nixpkgs.follows = "nixpkgs";
    gen-harness.inputs.flake-parts.follows = "flake-parts";
    gen-harness.inputs.flake-root.follows = "flake-root";
    gen-harness.inputs.treefmt-nix.follows = "treefmt-nix";
    gen-harness.inputs.devshell.follows = "devshell";
    gen-harness.inputs.git-hooks-nix.follows = "git-hooks-nix";

    # ── REFERENCE side (frozen golden nixpkgs stack) for the re-host parity oracle ──
    # ORIGINAL nixpkgs-signature gen-schema (`{ lib, algebra }`), pinned to its pre-re-host rev (the
    # last commit before the pure re-host changed the signature). A PERMANENT golden-reference pin
    # (same class as the nixpkgs-lib / flake-parts pins below), NEVER a release-set pin — do NOT sweep
    # it forward to main. main carries the pure re-host signature (`{ prelude, merge, algebra }`) the
    # oracle's reference side cannot call: rotating it to main makes rehost-den-parity throw (`called
    # without required argument 'merge'`) and dissolves the frozen witness the check exists to compare
    # re-host(main) against.
    #
    # A frozen reference is only sound where the SUBJECT's grammar is stable. The registry/schema
    # surface this pin guards is; the aspect grammar is not — it moves by design ruling, so no frozen
    # aspect reference can track it and a parity gate built on one reds on every ruled improvement
    # rather than on a defect. That is why only the schema half of the golden pair survives here.
    #
    # ★ AND THE SAME PRECONDITION HAS SINCE FAILED ON ONE AXIS OF THE SURVIVING HALF: the IDENTITY
    # ENCODING. gen-schema `75d40c1` re-minted `id_hash` by design ruling (ADR-0016) — the kind left
    # the digest for a `"<kind>:"` tag and the preimage became `toJSON` of the ⟨label,value⟩ pairs —
    # so the frozen witness reds on a ruled improvement here exactly as it would on the aspect
    # grammar, and no forward golden pin can carry the new encoding because every nixpkgs-signature
    # revision predates it. The identity axis is therefore EXCLUDED from the comparison: the parity
    # arms restate over instance key sets and every non-identity field (which do still hold
    # byte-for-byte), and `id_hash` is held by a teeth arm on the PURE engine instead of against the
    # frozen witness. ci/rehost-den-parity.nix states the exclusion and the arm at the arms.
    gen-schema-orig.url = "github:sini/gen-schema/2b7c2d39ad30f8fa5165d6861c01374f7c9cf3f6";
    # nixpkgs LIB ONLY — the reference `lib.evalModules` engine. Ecosystem policy: pull the pinned
    # nixpkgs.lib (auto-generated per nixpkgs release), NOT full nixpkgs, where only `lib.*` is needed.
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib/db3f255737b94216eb71cce308e2912cf6bc2d7c";

    # nixpkgs is the RUNNER only (treefmt, runCommand check derivations) — full nixpkgs required.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # The root flake's own inputs — the sibling route. `gen.inputs.gen-X` is the root's pin BY
      # REFERENCE, so no sibling revision is written in this file and none can be written stale:
      # `nix flake update gen-X` here reports that no such input exists. `gen-harness`'s `mkCi.nix`
      # gives the same value the same name, for the same reason.
      genInputs = inputs.gen.inputs;

      # ── re-host byte-parity oracle (permanent regression) ──
      # PURE side tracks the published re-host mains; REFERENCE side is the frozen original
      # nixpkgs-signature gen-schema driven through the pinned nixpkgs.lib. A future gen-merge /
      # re-host change that breaks byte-parity on the instance key sets or on any non-identity field
      # makes this check fail. The `id_hash` is the one excluded axis (see the golden pin above) and
      # is held by `teeth-mutation-pure` on the pure engine, which ships its own seeded control.
      denParity = import ./rehost-den-parity.nix {
        inherit (genInputs)
          gen-prelude
          gen-types
          gen-merge
          gen-algebra
          gen-schema
          ;
        inherit (inputs) gen-schema-orig;
        lib = inputs.nixpkgs-lib.lib;
      };

      # Keys that MUST be `true` for parity to hold (the regression gate).
      denParityKeys = [
        "parity-schema"
        "parity-instances"
        "both-evaluated"
        "teeth-mutation"
        "teeth-mutation-pure"
        "arming-teeth-mutation-pure"
        "teeth-parity"
        "parity-nested"
      ];

      # ── mkGenLibs wiring smoke check ──
      # Forces every key of the hub's published `gen.lib.mkGenLibs` so a broken lib wiring (bad pin
      # bump, drifted `.lib` signature) or a roster drift fails `nix flake check ./ci`. It also holds
      # the stratum partition: total declaration, published buckets matching it, and each bucket
      # entry the same value as its flat member. `.gate` is the per-key wiring-ok record + the roster
      # and stratum tripwires; `.gateKeys` the keys that MUST be `true`.
      mkGenLibsEval = import ./mkgenlibs-eval.nix { inherit (inputs) gen; };

      # ── agents-md-hub-inputs — the AGENTS.md hub-input sheet, CI-bound (den-hoag-bzcb4) ──
      # Reads AGENTS.md's fenced gen-input enumeration block back out of the committed file and
      # compares it, both directions, against the flake's own gen-* inputs (`genInputs`, filtered
      # by prefix) — so a new hub input reddens this instead of leaving the sheet to rot silently
      # the way it did once (den-hoag-8j5b, 19-vs-21). `.gate`/`.gateKeys` follow the same shape as
      # every other check below.
      hubInputSheet = import ./agents-md-hub-inputs.nix { inherit genInputs lib; };

      # ── inject-payload — the permanent O-INJ-2 cell ──
      # Asserts the MEASURED ADR-0023 (b) ground the crossing's `injectAdapter` declares: a real
      # `lib.compose` payload still reaches a function transitively (the schema sub-tree's gen
      # types), with the plain-clean and planted-caught controls in the same run. If a schema
      # change flips the predicate, this fails and the ADR-0023 disposition re-opens by
      # construction. `.gate` is the per-key record; `.gateKeys` the keys that MUST be `true`.
      injectPayload = import ./inject-payload.nix { inherit (inputs) gen; };

      # ── declared-content — the PERMANENT cell over the hub's CARRIED PROJECTION (den-hoag-jwm8) ──
      # Re-derives gen-delivery's own declared-content oracle against `flakeModules/default.nix`'s
      # carried `classFieldsOf`/`projectHosts` (copied verbatim, since they are not an exported
      # library call) fed through `genDelivery.realize` with the REAL pinned `gen.lib.mkGenLibs`
      # roster — the exact composition a consumer of this hub gets. Guards ADR-0028's Rider on the
      # path gen-delivery's own suite cannot reach: the hub never calls `genDelivery.project`.
      # `.gate` is the per-key record; `.gateKeys` the keys that MUST be `true`.
      declaredContent = import ./declared-content.nix { inherit (inputs) gen; };

      # ── direction-of-dependence lint ──
      # ADR-0015's enforcement half: no roster member may declare an input on a HIGHER stratum than
      # its own, under the chain substrate < modules < aspects < framework, save the closed
      # two-edge exception ruled 2026-08-18 (which is printed entry by entry, with its cause and
      # its retirement carrier, on every run). The observable is the DECLARED root-flake input
      # NAME — never a revision, so the lock graph ADR-0015 forbids as the enforcement source is
      # not what this reads. Like the check above it governs the hub's PINNED revisions, which is
      # the surface consumers get. `.gate` is the per-arm record incl. the in-tree arming; the
      # failure it guards is silent, so `refused: 0` travels with controls that fire in the same
      # run.
      directionOfDependence = import ./direction-of-dependence.nix { inherit (inputs) gen; };

      # The same value `gen-harness`'s own flake module installs for its twenty-two consumers. The
      # comment above this treefmt block says the set here may not be trimmed below the one
      # consumers receive; reading it from the harness makes that hold by construction, across the
      # repository boundary, rather than by two lists kept in agreement by hand.
      #
      # `{ names, plugins }`: the membership fact and the `programs.mdformat.plugins` value built
      # from it. The guard below is handed the names from here rather than restating them.
      mdformatBase = inputs.gen-harness.lib.mdformatBasePlugins;
      mdformatBasePlugins = mdformatBase.plugins;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = lib.systems.flakeExposed;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.devshell.flakeModule
        inputs.flake-root.flakeModule
        inputs.git-hooks-nix.flakeModule
      ];

      # Raw oracle results (system-independent, pure eval) for eyeballing:
      #   nix eval ./ci#lib.parity.den      --json | jq
      #   nix eval ./ci#lib.mkGenLibsEval   --json | jq   (keyCount / missing / extra / strata / per-key gate)
      flake.lib.parity = {
        den = denParity;
      };
      flake.lib.mkGenLibsEval = mkGenLibsEval;
      #   nix eval ./ci#lib.hubInputSheet --json | jq
      flake.lib.hubInputSheet = hubInputSheet;
      #   nix eval ./ci#lib.injectPayload.gate --json | jq
      flake.lib.injectPayload = injectPayload;
      #   nix eval ./ci#lib.declaredContent.gate --json | jq
      flake.lib.declaredContent = declaredContent;
      #   nix eval ./ci#lib.direction.report --json | jq
      flake.lib.direction = directionOfDependence;

      perSystem =
        {
          self',
          config,
          pkgs,
          system,
          ...
        }:
        let
          # Build a check derivation: prints the oracle result (incl id_hash sample + teeth), and
          # FAILS the build if any required key is not `true` — a permanent byte-parity regression.
          mkParityCheck =
            name: result: keys:
            let
              gate = lib.genAttrs keys (k: result.${k});
              allOk = builtins.all (k: result.${k} == true) keys;
              report = builtins.toJSON {
                inherit allOk;
                results = gate;
                sample = result.sample or { };
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "PARITY REGRESSION — re-host is no longer byte-identical to the nixpkgs stack" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the mkGenLibs wiring check: prints the per-key gate (+ the roster and stratum
          # diffs) and FAILS the build if any key failed to evaluate, the roster drifted, or the
          # stratum partition is not total and in agreement with the flat roster
          # (mkgenlibs-eval.nix). The roster of record is that file, never a count.
          mkGenLibsCheck =
            name: g:
            let
              allOk = builtins.all (k: g.gate.${k} == true) g.gateKeys;
              failed = builtins.filter (k: g.gate.${k} != true) g.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                inherit (g)
                  keyCount
                  memberCount
                  keys
                  missing
                  extra
                  strata
                  strataMissing
                  strataExtra
                  strataUnknown
                  bucketCounts
                  bucketMismatch
                  bucketOverlap
                  resolveFailed
                  agreeFailed
                  ;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "mkGenLibs WIRING REGRESSION — a lib key failed to evaluate, the roster drifted, or the stratum partition broke" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the agents-md-hub-inputs check: prints the documented/actual roster + the
          # missing/extra diffs and FAILS the build if the sheet and the flake's own gen-*
          # inputs disagree in either direction, or on order (byte-for-byte).
          mkHubInputSheetCheck =
            name: h:
            let
              allOk = builtins.all (k: h.gate.${k} == true) h.gateKeys;
              failed = builtins.filter (k: h.gate.${k} != true) h.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                inherit (h)
                  documented
                  actual
                  missing
                  extra
                  ;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "AGENTS.md HUB-INPUT SHEET DRIFT — the fenced enumeration block no longer matches the flake's own gen-* inputs" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the direction-of-dependence check: prints the full report — the class tallies,
          # every edge a reader must act on (refused, excepted, unranked, off-roster), the
          # exception entry by entry with its cause and carrier, and the arming — and FAILS the
          # build if any gate arm is not `true`. A failing arm is either an upward edge (the lint
          # firing) or an arming arm that stopped firing (the lint gone blind); both are red,
          # because a guard that can no longer refuse is not a passing guard.
          mkDirectionCheck =
            name: d:
            let
              allOk = builtins.all (k: d.gate.${k} == true) d.gateKeys;
              failed = builtins.filter (k: d.gate.${k} != true) d.gateKeys;
              report = builtins.toJSON ({ inherit allOk failed; } // d.report);
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "DIRECTION OF DEPENDENCE — a roster member declares an input above its own stratum, or the guard's own arming stopped firing" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the inject-payload check (the permanent O-INJ-2 cell): prints the per-key gate
          # and FAILS the build if any key is not `true`. A failing key is either the measured
          # ADR-0023 (b) ground moving (the payload no longer reaches a function — the declared
          # opt-out's disposition re-opens) or a control gone blind; both are red, because a
          # tripwire that can no longer fire is not a passing tripwire.
          mkInjectCheck =
            name: g:
            let
              allOk = builtins.all (k: g.gate.${k} == true) g.gateKeys;
              failed = builtins.filter (k: g.gate.${k} != true) g.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                results = g.gate;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "INJECT-PAYLOAD PREDICATE MOVED — the ADR-0023 (b) measured ground changed, or a control went blind; the declared opt-out's disposition re-opens" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # Build the declared-content check (den-hoag-jwm8): prints the per-key gate and FAILS
          # the build if any key is not `true`. A failing key is either the CARRIED projection
          # realizing a declared-but-contentless class again (the jwm8 defect, un-guarded) or a
          # control gone blind — the class going unregistered, or the tripwire losing its bite.
          mkDeclaredContentCheck =
            name: g:
            let
              allOk = builtins.all (k: g.gate.${k} == true) g.gateKeys;
              failed = builtins.filter (k: g.gate.${k} != true) g.gateKeys;
              report = builtins.toJSON {
                inherit allOk failed;
                results = g.gate;
              };
            in
            pkgs.runCommand name
              {
                inherit report;
                passAsFile = [ "report" ];
              }
              ''
                echo "── ${name} ──"
                cat "$reportPath"
                echo
                ${lib.optionalString (!allOk) ''
                  echo "CARRIED PROJECTION REGRESSION — the hub's classFieldsOf/projectHosts realizes a declared-but-contentless class (den-hoag-jwm8)" >&2
                  exit 1
                ''}
                cp "$reportPath" "$out"
              '';
          # ── perf-regression bench (the PERFORMANCE twin of the parity oracles) ──
          # `nix run ./ci#perf-bench` — drives ci/perf-bench.nix (pure vs pinned-nixpkgs stack)
          # through nix-instantiate + NIX_SHOW_STATS and gates on parity / thunk+alloc ratios /
          # counter linearity — every gate a deterministic evaluator counter. cpu is measured and
          # reported beside them but gated by nothing (ci/README.md). An app, not a check
          # derivation: timing needs an un-sandboxed evaluator run, and the report is regenerated
          # into BENCHMARKS.md. CI runs it as a dedicated workflow step.
          #
          # `gen-class` is the class-share mechanism lib: perf-bench drives its tier-2
          # `applyCoreFixed` against gen-merge's fixed-input kernel (the `classShare` workload —
          # spec §2.5). Like every sibling here it comes from the root's pin, never a local one.
          perfSrcs = pkgs.writeText "perf-srcs.nix" ''
            {
              "gen-prelude" = "${genInputs.gen-prelude}";
              "gen-types" = "${genInputs.gen-types}";
              "gen-merge" = "${genInputs.gen-merge}";
              "gen-algebra" = "${genInputs.gen-algebra}";
              "gen-schema" = "${genInputs.gen-schema}";
              "gen-aspects" = "${genInputs.gen-aspects}";
              "gen-class" = "${genInputs.gen-class}";
              "gen-schema-orig" = "${inputs.gen-schema-orig}";
              "nixpkgs-lib" = "${inputs.nixpkgs-lib}";
            }
          '';
          perfBench = pkgs.writeShellApplication {
            name = "gen-perf-bench";
            runtimeInputs = [
              pkgs.nix
              pkgs.jq
              pkgs.gawk
            ];
            text = ''
              export PERF_WORKLOADS=${./perf-bench.nix}
              export PERF_SRCS=${perfSrcs}
            ''
            + builtins.readFile ./perf-bench.sh;
          };

          # ── flake-compare bench — the 3-way real-flake comparison ──
          # `nix run ./ci#flake-compare` — evaluates ci/flake-compare/{flake-parts,adios,gen-lib}/
          # (the SAME outputs three ways) under adios-flake's BENCHMARKS.md methodology (5 nix eval
          # runs, NIX_SHOW_STATS counters, eval-cache off), prints a 3-way counter table + drvPath
          # equivalence. Report-only: pins the neighbour frameworks by rev but gates NOTHING (their
          # code moves independently of the hub). The variant flakes carry their own committed locks;
          # `${./flake-compare}` copies the tree (incl locks) to the store for a hermetic run.
          flakeCompare = pkgs.writeShellApplication {
            name = "gen-flake-compare";
            runtimeInputs = [
              pkgs.nix
              pkgs.jq
              pkgs.gawk
              pkgs.coreutils
            ];
            text = ''
              export FLAKE_COMPARE_DIR=${./flake-compare}
            ''
            + builtins.readFile ./flake-compare.sh;
          };

          # ── fleet-consistency — the TRUST-SURFACE arithmetic roster for the cited A1 fleet numbers ──
          # `nix run ./ci#fleet-consistency` — the [consistency] partition (nine pure-jq gates + a
          # `--selftest` teeth check) over the three committed baselines (ci/bench/baselines/, copied
          # verbatim from the hola lab @4bab613). It re-asserts pin agreement, the arithmetic
          # re-derivations, the byte-digest ties, and the two floors that BENCHMARKS.md / VALIDATION.md
          # cite — so the cited numbers cannot silently drift from their own arithmetic. It DOES gate
          # (unlike flake-compare): pure jq, seconds, NO fleet eval / NIX_SHOW_STATS / re-measurement —
          # re-measurement of the fleet is the hola lab's job. Owner principle: libraries stay unburdened
          # by fleet metrics; this hub is the trust surface, so the drift tooth lives here. SC2329: the
          # consistency-gate roster invokes its gate fns indirectly by name.
          fleetConsistency = pkgs.writeShellApplication {
            name = "gen-fleet-consistency";
            excludeShellChecks = [ "SC2329" ];
            runtimeInputs = [
              pkgs.jq
              pkgs.coreutils
            ];
            text = ''
              export FLEET_BASELINES=${./bench/baselines}
            ''
            + builtins.readFile ./fleet-consistency.sh;
          };
        in
        {
          # Pre-commit gate for the hub itself. Unlike the lib repos (which consume
          # `gen-harness.lib.mkCi` → its `flakeModule.nix` and get a `ci` nix-unit hook),
          # the hub is the parity/perf harness: it exposes flake `checks` + a perf `app`,
          # NOT a nix-unit `tests` output. So it must NOT carry the shared `ci` hook
          # (`nix-unit --flake ./ci#tests` would fail "does not provide attribute
          # 'tests'"). Format-only here.
          #
          # That is why this flake consumes gen-harness's CHECK BUILDERS rather than its
          # flake module: the hub cannot take a module built around a `tests` output, but
          # the gates themselves are pure functions of `pkgs` and apply here unchanged.
          pre-commit = {
            check.enable = false;
            settings.hooks.treefmt = {
              enable = true;
              package = self'.formatter;
            };
          };

          checks = {
            rehost-den-parity = mkParityCheck "rehost-den-parity" denParity denParityKeys;
            mkgenlibs-eval = mkGenLibsCheck "mkgenlibs-eval" mkGenLibsEval;
            agents-md-hub-inputs = mkHubInputSheetCheck "agents-md-hub-inputs" hubInputSheet;
            inject-payload = mkInjectCheck "inject-payload" injectPayload;
            declared-content = mkDeclaredContentCheck "declared-content" declaredContent;
            direction-of-dependence = mkDirectionCheck "direction-of-dependence" directionOfDependence;
            # The hub is gated by the same tree-root oracle gen-harness ships to its consumers —
            # the repository that ships a gate is gated by it, and now by the one instance of it
            # rather than by a second copy that has to be kept in agreement.
            treefmt-tree-root = inputs.gen-harness.lib.checks.treefmtTreeRoot {
              inherit pkgs;
              name = "gen";
              formatter = self'.formatter;
            };

            # The plugin set is a property of the GENERATED formatter, not of the expression
            # above: the defect this guards was a list that was written and then discarded.
            # `expected` comes from the same value installed in the treefmt block, so the guard
            # cannot fall behind the set it guards.
            mdformat-plugins = inputs.gen-harness.lib.checks.mdformatPlugins {
              inherit pkgs;
              name = "gen";
              formatter = self'.formatter;
              expected = mdformatBase.names;
            };
          };

          apps.perf-bench = {
            type = "app";
            program = "${perfBench}/bin/gen-perf-bench";
          };

          apps.flake-compare = {
            type = "app";
            program = "${flakeCompare}/bin/gen-flake-compare";
          };

          apps.fleet-consistency = {
            type = "app";
            program = "${fleetConsistency}/bin/gen-fleet-consistency";
          };

          treefmt = {
            # TREE ROOT — see `gen-harness`'s `flakeModule.nix` for the mechanism in full. A
            # `.git/config` marker walk is worktree-blind: a linked worktree's `.git` is a
            # gitdir-pointer file, so the walk escapes the worktree and formats the main checkout.
            # `null` rather than omission, because flake-parts' `mkDefault "flake.nix"` would pin
            # the tree root to `ci/`; `tree-root-cmd` then STATES the root instead of inheriting
            # treefmt's default.
            # Mirrors the module mkCi hands to consumers — root detection, the program set, and
            # the tree-root check alike: the repo that ships the gate is gated by it, so this list
            # may not be trimmed below the one consumers receive. Since the plugin set and both
            # check builders now come from `gen-harness` itself, that agreement holds by
            # construction rather than by two copies being maintained in step.
            projectRootFile = null;
            flakeCheck = false;
            enableDefaultExcludes = true;
            settings.on-unmatched = "info";
            settings.tree-root-cmd = "git rev-parse --show-toplevel";
            programs = {
              actionlint.enable = true;
              nixfmt.enable = true;
              mdformat = {
                enable = true;
                # ★ THROUGH `plugins`, WITH NO `package` LINE TO GUARD — `package` and `plugins`
                # do not union. treefmt-nix builds `cfg.package.withPlugins cfg.plugins`, and
                # mdformat's `withPlugins` wraps a hardcoded plain base rather than the package
                # it is called on, so a list written into `package` is discarded and the shipped
                # formatter is plain mdformat, store-path-identical to it.
                plugins = mdformatBasePlugins;
                settings.number = true;
              };
            };
          };

          devshells.default = {
            devshell.startup.git-hooks.text = config.pre-commit.installationScript;

            env = [
              {
                name = "FLAKE_ROOT";
                eval = "$PRJ_ROOT";
              }
            ];

            commands = [
              {
                name = "fmt";
                help = "Format all files";
                command = ''
                  cd "$FLAKE_ROOT/ci" && nix fmt
                '';
              }
              {
                name = "repl";
                help = "Interactive REPL with all gen libraries loaded";
                command = ''
                  nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"
                '';
              }
              {
                name = "perf-bench";
                help = "Run the module-system perf-regression bench (pure vs nixpkgs stack)";
                command = ''
                  nix run "$FLAKE_ROOT/ci#perf-bench"
                '';
              }
              {
                name = "flake-compare";
                help = "Run the 3-way real-flake comparison bench (gen-lib vs flake-parts vs adios-flake)";
                command = ''
                  nix run "$FLAKE_ROOT/ci#flake-compare"
                '';
              }
              {
                name = "fleet-consistency";
                help = "Re-assert the [consistency] roster over the cited A1 fleet baselines (pure jq, seconds)";
                command = ''
                  nix run "$FLAKE_ROOT/ci#fleet-consistency"
                '';
              }
            ];
          };
        };
    };
}
