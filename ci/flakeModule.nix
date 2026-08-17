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

  # The markdown invariants, from the one file both this module and the hub's own ci read, so
  # the two cannot drift apart the way the three copies of the discarded list did.
  mdformatBasePlugins = import ./mdformat-plugins.nix;
  # Bound HERE rather than inside `perSystem`, whose own `config` argument shadows this one.
  mdformatExtra = config.gen.ci.mdformat.extraPlugins;

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

  # The EXTENSION point, and it is an extension rather than an override on purpose. The base set
  # defends representational invariants of markdown, which are uniform across every repository
  # that writes markdown and are therefore not a per-corpus preference. What IS per-corpus — gfm
  # being the measured case — arrives here, added to the base rather than replacing it.
  options.gen.ci.mdformat.extraPlugins = lib.mkOption {
    type = lib.types.functionTo (lib.types.listOf lib.types.package);
    default = _: [ ];
    description = ''
      Plugins ADDED to mkCi's base mdformat set. The base set is not reachable for removal
      through this option, by construction: `programs.mdformat.plugins` replaces rather than
      extends, so a consumer setting it directly would silently drop frontmatter, footnote and
      simple-breaks and nothing would report it.
    '';
  };

  config = {
    systems = lib.systems.flakeExposed;

    # testSingletons.<suite>.<test> = { <test> = leaf; } — re-nests each leaf under a group keyed by its
    # OWN (test-prefixed) name, so `--flake .#testSingletons.<suite>.<test>` makes that singleton the
    # group root → nix-unit runs exactly one test. nix-unit treats the target attrpath ENDPOINT as a
    # GROUP and detects a test by the `test` NAME-PREFIX of a group child (verified on 2.35.0: a
    # `{expr;expected;}` child named `only` runs 0/0, `test-only` runs 1/1). Pointing it at a bare
    # `{expr;expected;}` leaf (`#tests.<suite>.<test>`) makes that leaf the group and finds no
    # test-prefixed child, so it silently reports `0/0 successful` — a false pass. The wrap works because
    # `${tn}` reuses the original test-prefixed name as the singleton child. This view is the fix.
    flake.testSingletons = lib.mapAttrs (
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
          # TREE ROOT — the two settings below are one decision; `checks.treefmt-tree-root`
          # is its oracle. A marker-file walk cannot serve here: a linked worktree's `.git` is
          # a gitdir-POINTER FILE rather than a directory, so a `.git/config` search finds
          # nothing in the worktree and climbs UP, crossing the worktree boundary into the main
          # checkout. treefmt then reads and writes THAT tree — a run invoked in a worktree
          # reformats the main checkout and leaves the worktree's own files untouched while
          # reporting success. The pre-commit hook above shares this wrapper
          # (`package = self'.formatter`), so it formats one tree while the commit carries another.
          #
          # `null` rather than omission: flake-parts' treefmt module supplies
          # `mkDefault "flake.nix"`, which walking up from `ci/` resolves to `ci/` itself — the
          # right worktree, the wrong scope. `null` suppresses the `--tree-root-file` flag.
          projectRootFile = null;
          flakeCheck = false;
          enableDefaultExcludes = true;
          settings.on-unmatched = "info";
          # STATED, not inherited. With no tree root declared treefmt falls back to its own
          # detection, which is `git rev-parse --show-toplevel` today — correct, but a default
          # this invariant does not control, and one whose non-git branch resolves the CONFIG
          # FILE'S STORE DIRECTORY rather than failing. Naming the command makes the worktree
          # the tree root by construction and turns the non-git case into a loud error.
          #
          # Residual, unaddressed: `TREEFMT_TREE_ROOT` in the environment still overrides both
          # (flags and env outrank the config file), and the generated wrapper unsets neither.
          settings.tree-root-cmd = "git rev-parse --show-toplevel";
          programs = {
            actionlint.enable = true;
            nixfmt.enable = true;
            mdformat = {
              enable = true;
              # ★ THE SET GOES THROUGH `plugins`, AND THERE IS NO `package` LINE TO GUARD.
              # treefmt-nix builds its final package as `cfg.package.withPlugins cfg.plugins`,
              # and mdformat's `withPlugins` wraps a HARDCODED plain base rather than the package
              # it is called on. So `package` and `plugins` do not union: a list written into
              # `package` is discarded outright and the formatter that ships is plain mdformat,
              # store-path-identical to it. Setting both would encode a union that does not
              # exist, which is why the line is deleted rather than supplemented.
              plugins = p: mdformatBasePlugins p ++ mdformatExtra p;
              # Ordered lists renumber rather than repeating `1.`, so a reordered list reads
              # correctly in plain text as well as rendered.
              settings.number = true;
            };
          };
        };

        # The tree-root invariant is a property of the GENERATED artefacts, so it is gated
        # where they are built rather than trusted to the settings above staying put.
        checks.treefmt-tree-root = import ./treefmt-tree-root.nix {
          inherit pkgs name;
          formatter = self'.formatter;
        };

        # The plugin set is a property of the GENERATED formatter, not of the expression above:
        # the defect this guards was a list that was written and then discarded. Gated where the
        # artefact is built, for the same reason the tree root is.
        checks.mdformat-plugins = import ./mdformat-plugins-check.nix {
          inherit pkgs name;
          formatter = self'.formatter;
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
                # A `suite.test` arg must target the `testSingletons` view: nix-unit treats the attrpath
                # endpoint as a GROUP and detects tests by the `test` name-prefix of a group child, so
                # `#tests.<suite>.<test>` (a bare leaf, no test-prefixed child) reports a silent
                # `0/0 successful`. `testSingletons.<suite>.<test>` re-nests the leaf under a child keyed
                # by its own test-prefixed name, so the singleton runs 1/1. Bare suite / no arg → `tests`.
                if [ -n "''${1:-}" ] && [ "''${1#*.}" != "''$1" ]; then
                  target="testSingletons.$1"
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
