{
  inputs = {
    # ── PURE side (the guarded thing): published re-host mains ──
    gen-prelude.url = "github:sini/gen-prelude";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-schema.url = "github:sini/gen-schema";
    gen-aspects.url = "github:sini/gen-aspects";
    gen-scope.url = "github:sini/gen-scope";
    gen-graph.url = "github:sini/gen-graph";
    gen-select.url = "github:sini/gen-select";
    gen-bind.url = "github:sini/gen-bind";
    gen-dispatch.url = "github:sini/gen-dispatch";
    gen-resolve.url = "github:sini/gen-resolve";
    # gen-class: the class-share mechanism lib; perf-bench drives its tier-2 `applyCoreFixed`
    # against gen-merge's fixed-input kernel (the `classShare` workload — spec §2.5).
    gen-class.url = "github:sini/gen-class";

    # The hub itself — for the mkGenLibs wiring smoke check (checks.mkgenlibs-eval). The ci subflake
    # can't `import ../lib` (that escapes its flake root), so it reaches the root lib through this
    # input, exactly like den-hoag's ci reaches den-hoag. Its gen-* pins stay the ROOT flake.lock's
    # (the published `gen.lib.mkGenLibs` surface consumers get); only the heavy nixpkgs is deduped.
    gen.url = "path:..";
    gen.inputs.nixpkgs.follows = "nixpkgs";

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

      # ── re-host byte-parity oracle (permanent regression) ──
      # PURE side tracks the published re-host mains; REFERENCE side is the frozen original
      # nixpkgs-signature gen-schema driven through the pinned nixpkgs.lib. A future gen-merge /
      # re-host change that breaks byte-parity (incl the id_hash SHA) makes this check fail.
      denParity = import ./rehost-den-parity.nix {
        inherit (inputs)
          gen-prelude
          gen-types
          gen-merge
          gen-algebra
          gen-schema
          gen-schema-orig
          ;
        lib = inputs.nixpkgs-lib.lib;
      };

      # Keys that MUST be `true` for parity to hold (the regression gate).
      denParityKeys = [
        "parity-schema"
        "parity-instances"
        "both-evaluated"
        "teeth-mutation"
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
          # ── perf-regression bench (the PERFORMANCE twin of the parity oracles) ──
          # `nix run ./ci#perf-bench` — drives ci/perf-bench.nix (pure vs pinned-nixpkgs stack)
          # through nix-instantiate + NIX_SHOW_STATS and gates on parity / cpu+counter ratios /
          # counter linearity. An app, not a check derivation: timing needs an un-sandboxed
          # evaluator run. CI runs it as a dedicated workflow step.
          perfSrcs = pkgs.writeText "perf-srcs.nix" ''
            {
              "gen-prelude" = "${inputs.gen-prelude}";
              "gen-types" = "${inputs.gen-types}";
              "gen-merge" = "${inputs.gen-merge}";
              "gen-algebra" = "${inputs.gen-algebra}";
              "gen-schema" = "${inputs.gen-schema}";
              "gen-aspects" = "${inputs.gen-aspects}";
              "gen-schema-orig" = "${inputs.gen-schema-orig}";
              "gen-class" = "${inputs.gen-class}";
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
          # `nix run ./ci#flake-compare` — evaluates ci/flake-compare/{flake-parts,adios,gen-flake}/
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
          # ../mkCi.nix → flakeModule.nix and get a `ci` nix-unit hook), the hub is the
          # parity/perf harness: it exposes flake `checks` + a perf `app`, NOT a nix-unit
          # `tests` output. So it must NOT carry the shared `ci` hook (`nix-unit --flake
          # ./ci#tests` would fail "does not provide attribute 'tests'"). Format-only here.
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
            # The hub carries the tree-root oracle it ships to consumers (flakeModule.nix).
            treefmt-tree-root = import ./treefmt-tree-root.nix {
              inherit pkgs;
              name = "gen";
              formatter = self'.formatter;
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
            # TREE ROOT — see flakeModule.nix for the mechanism in full. A `.git/config` marker
            # walk is worktree-blind: a linked worktree's `.git` is a gitdir-pointer file, so the
            # walk escapes the worktree and formats the main checkout. `null` rather than
            # omission, because flake-parts' `mkDefault "flake.nix"` would pin the tree root to
            # `ci/`; `tree-root-cmd` then STATES the root instead of inheriting treefmt's default.
            # Mirrors flakeModule.nix, the module mkCi hands to consumers — root detection, the
            # program set, and the tree-root check alike: the repo that ships the gate is gated by
            # it, so this list may not be trimmed below the one consumers receive.
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
                package = pkgs.mdformat.withPlugins (p: [
                  p.mdformat-beautysh
                  p.mdformat-footnote
                  p.mdformat-frontmatter
                  p.mdformat-gfm
                  p.mdformat-simple-breaks
                ]);
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
                help = "Run the 3-way real-flake comparison bench (gen-flake vs flake-parts vs adios-flake)";
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
