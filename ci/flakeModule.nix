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

    # tests1.<suite>.<test> = { <test> = leaf; } — wraps each leaf as a named test-prefixed child of a
    # group, so `--flake .#tests1.<suite>.<test>` makes that singleton the group root → nix-unit runs
    # exactly one test. nix-unit always treats the target attrpath ENDPOINT as a GROUP; pointing it at a
    # bare `{expr;expected;}` leaf (`#tests.<suite>.<test>`) recurses into expr/expected, finds no
    # test-prefixed child, and silently reports `0/0 successful` — a false pass. This view is the fix.
    flake.tests1 = lib.mapAttrs (
      _suite: subtests: lib.mapAttrs (tn: t: { ${tn} = t; }) subtests
    ) config.flake.tests;

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
          projectRootFile = ".git/config";
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
              help = "Run all checks, or a specific test [ci] [ci suite] [ci suite.test]";
              command = ''
                # A `suite.test` arg must target the `tests1` singleton-group view: nix-unit treats the
                # attrpath endpoint as a GROUP, so `#tests.<suite>.<test>` (a bare leaf) reports a silent
                # `0/0 successful`. `tests1.<suite>.<test>` wraps that leaf as a test-prefixed child, so
                # the singleton is the group root and runs 1/1. Bare suite / no arg stay on `tests`.
                if [ -n "''${1:-}" ] && [ "''${1#*.}" != "''$1" ]; then
                  target="tests1.$1"
                else
                  target="tests''${1:+.$1}"
                fi
                nix-unit \
                  --flake "$FLAKE_ROOT/ci#$target" \
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
