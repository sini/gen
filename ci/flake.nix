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

    # ── REFERENCE side (frozen golden nixpkgs stack) for the re-host byte-parity oracles ──
    # ORIGINAL nixpkgs-signature gen-schema (`{ lib, algebra }`) + gen-aspects (`{ lib, schema }`),
    # pinned to their pre-re-host revs (the last commit before the pure re-host changed the signature).
    gen-schema-orig.url = "github:sini/gen-schema/2b7c2d39ad30f8fa5165d6861c01374f7c9cf3f6";
    gen-aspects-orig.url = "github:sini/gen-aspects/87bf758169bc1d7f3336132f22e7fe38c5adf954";
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

      # ── re-host byte-parity oracles (permanent regression) ──
      # PURE side tracks the published re-host mains; REFERENCE side is the frozen original
      # nixpkgs-signature libs driven through the pinned nixpkgs.lib. A future gen-merge / re-host
      # change that breaks byte-parity (incl the id_hash SHA) makes these checks fail.
      byteParity = import ./rehost-byte-parity.nix {
        inherit (inputs)
          gen-prelude
          gen-types
          gen-merge
          gen-algebra
          gen-schema
          gen-aspects
          gen-schema-orig
          gen-aspects-orig
          ;
        lib = inputs.nixpkgs-lib.lib;
      };
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
      byteParityKeys = [
        "all-identical"
        "both-evaluated"
        "teeth-mutation-diverges"
        "den-realism"
      ];
      denParityKeys = [
        "parity-schema"
        "parity-instances"
        "both-evaluated"
        "teeth-mutation"
        "teeth-parity"
        "parity-nested"
      ];
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
      #   nix eval ./ci#lib.parity.byte --json | jq
      #   nix eval ./ci#lib.parity.den  --json | jq
      flake.lib.parity = {
        byte = byteParity;
        den = denParity;
      };

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
              "gen-aspects-orig" = "${inputs.gen-aspects-orig}";
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
            rehost-byte-parity = mkParityCheck "rehost-byte-parity" byteParity byteParityKeys;
            rehost-den-parity = mkParityCheck "rehost-den-parity" denParity denParityKeys;
          };

          apps.perf-bench = {
            type = "app";
            program = "${perfBench}/bin/gen-perf-bench";
          };

          apps.flake-compare = {
            type = "app";
            program = "${flakeCompare}/bin/gen-flake-compare";
          };

          treefmt = {
            projectRootFile = ".git/config";
            flakeCheck = false;
            enableDefaultExcludes = true;
            settings.on-unmatched = "info";
            programs.mdformat = {
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
            ];
          };
        };
    };
}
