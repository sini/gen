# Shared CI module for all gen ecosystem libraries.
# Provides treefmt, checks.default, devshell, and a flake.tests option.
#
# Expects `name` in specialArgs (set by mkCi).
# Expects `inputs` to include nix-unit (available via mkFlake specialArgs).
{
  config,
  lib,
  inputs,
  genInputs,
  name,
  ...
}:
let
  resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name};
in
let
  tests = config.flake.tests;

  assertTests = lib.mapAttrsToList (
    suite: subtests:
    lib.mapAttrsToList (
      testName: t:
      if t.expr == t.expected then
        true
      else
        throw "FAIL ${suite}.${testName}: got ${builtins.toJSON t.expr}, expected ${builtins.toJSON t.expected}"
    ) subtests
  ) tests;
in
{
  options.flake.tests = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites: { suite-name.test-name = { expr; expected; }; }";
  };

  config = {
    systems = lib.systems.flakeExposed;

    perSystem =
      {
        self',
        config,
        pkgs,
        system,
        ...
      }:
      let
        # nix-unit as a binary: the pre-commit framework execs `entry` directly (shlex split, no
        # shell), so it needs an executable that bundles the `--flake ./ci#tests` ref, not a bare
        # command string. No stack raise — the pure gen module system (gen-merge's evalModuleTree)
        # recurses per nesting level, not per module count, so every gen library's suite evaluates
        # within the default 8 MB stack. (A prior `ulimit -s unlimited` here masked a regex bug,
        # not eval depth: purity scans called nixpkgs lib.hasInfix, whose `.*needle.*` recurses to
        # depth ∝ string length on whole-file source reads. Fixed by genPrelude.hasInfix.)
        ciNixUnit = pkgs.writeShellApplication {
          name = "${name}-ci-nix-unit";
          runtimeInputs = [ (resolve "nix-unit").packages.${system}.default ];
          text = ''
            exec nix-unit --flake ./ci#tests "$@"
          '';
        };
      in
      {
        # Pre-commit hooks: format check + unit tests
        pre-commit = {
          check.enable = false;
          settings.hooks = {
            treefmt = {
              enable = true;
              package = self'.formatter;
            };
            ci = {
              enable = true;
              name = "ci";
              description = "Run nix-unit tests";
              entry = "${ciNixUnit}/bin/${name}-ci-nix-unit";
              files = "\\.nix$";
              pass_filenames = false;
            };
          };
        };

        treefmt = {
          # `null` selects treefmt's own native tree-root detection — `git rev-parse
          # --show-toplevel`, the root of the CURRENT worktree. A marker-file walk cannot serve
          # here: a linked worktree's `.git` is a gitdir-POINTER FILE rather than a directory, so
          # a `.git/config` search climbs straight through the worktree boundary and resolves the
          # main checkout. treefmt then formats that tree instead of the one it was invoked in,
          # and because the pre-commit hook above shares this wrapper (`package = self'.formatter`)
          # the hook formats one tree while the commit carries another.
          #
          # Explicit `null`, not omission: flake-parts' treefmt module supplies
          # `mkDefault "flake.nix"`, which walking up from `ci/` resolves to `ci/` itself — the
          # right worktree, the wrong scope.
          #
          # Residual: the native-detection branch of the generated wrapper omits the
          # `unset PRJ_ROOT` that the marker-file branch emits. Measured against treefmt 2.5.0,
          # PRJ_ROOT takes no part in tree-root resolution, so that unset is vestigial; the live
          # environment override is TREEFMT_TREE_ROOT, which neither branch unsets.
          projectRootFile = null;
          flakeCheck = false;
          enableDefaultExcludes = true;
          settings.on-unmatched = "info";
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

        checks.default = pkgs.runCommand "${name}-tests" { } ''
          echo "${toString (builtins.length (lib.flatten assertTests))} tests passed"
          touch $out
        '';

        devshells.default = {
          devshell.startup.git-hooks.text = config.pre-commit.installationScript;

          packages = [
            (resolve "nix-unit").packages.${system}.default
          ];

          env = [
            {
              name = "FLAKE_ROOT";
              eval = "$PRJ_ROOT";
            }
          ];

          commands = [
            {
              name = "ci";
              help = "Run all checks, or a specific test [ci] [ci suite.test]";
              command = ''
                nix-unit \
                  --flake "$FLAKE_ROOT/ci#tests''${1:+.$1}" \
                  --gc-roots-dir "$FLAKE_ROOT/ci/.gcroots" "''${@:2}"
              '';
            }
            {
              name = "fmt";
              help = "Format all files";
              command = ''
                cd "$FLAKE_ROOT/ci" && nix fmt
              '';
            }
            {
              name = "repl";
              help = "Interactive REPL";
              command = ''
                nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"
              '';
            }
          ];
        };
      };
  };
}
