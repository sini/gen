{
  # gen-lib variant of the 3-way comparison flake (ci/flake-compare).
  #
  # IDIOM CHOICE (documented honestly): the hub is consumed as a BARE CALLER of `gen.lib.compose`
  # — the successor compose construct — not through `gen.flakeModules.default`. The flakeModule is
  # an INTERIM surface (its own header says so): host/tree-oriented, carrying gen-flake's
  # aspects/hosts projection verbatim, replaced when the true framework surface arrives — so
  # benching it would bake an interim surface's overhead into published integers. The library
  # route is the settled S2 core this bench measures:
  #
  #   1. `gen.lib.compose { modules; specialArgs; }` — the PURE half. gen-merge's byte-mode
  #      `evalModuleTree` resolves the typed spec tree (packages registry + devShell/formatter
  #      specs) with ZERO nixpkgs. `compose` is caller-total: tree loading is one
  #      `(import-tree.addPath ./gen).files` expression (gen's own pinned import-tree fork), and
  #      the constructor set is the same five-key map the hub flakeModule hands every hub-fronted
  #      tree (flakeModules/default.nix `genLibs`), merged here as the caller's own act.
  #   2. a hand-rolled per-system builder at the nixpkgs boundary, reading `composed.values`
  #      directly — the compose+own-builder path for consumers off the flakeModule track. It maps
  #      each resolved spec to a derivation (`import nixpkgs { inherit system; }`, identical to
  #      the other two variants).
  #
  # This is value-injection, not type-driving: the resolved VALUES cross into nixpkgs, gen TYPES
  # never do — held under ADR-0023's declared interim until no declared opt-out remains.
  # The derivation-constructing calls are byte-identical to the flake-parts/ and adios/
  # variants, so the drvPath equivalence check holds. The hub pins the whole pure gen stack
  # (gen-merge / gen-schema / gen-aspects / ...) as transitive inputs; its own nixpkgs
  # (never evaluated by the hub) follows ours.
  #
  # HISTORY (visible-amendment convention): this variant targeted gen-flake until the hub
  # consolidation re-pointed it at `gen.lib` (the third column renamed gen-flake → gen-lib). The
  # old header's reasoning, quoted: "gen-flake's `flakeModules.default` is HOST-oriented — it
  # composes a gen tree and realizes `nixosConfigurations` through the nixosSystem terminal. It
  # has no perSystem `packages`/`devShells`/`formatter` path, so it does NOT fit this flake's
  # outputs. The idiomatic gen-flake expression here is therefore the LIBRARY directly." The
  # library-direct idiom carries over unchanged; only the route (gen-flake.lib.compose with its
  # internal tree/constructor handling → gen.lib.compose as a bare caller) moved.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";

    # ── THIS LOCK IS NESTED, AND NOTHING SWEEPS IT ──
    # `ci/flake-compare/gen-lib/flake.lock` is a NESTED lock (den-hoag-w1tr4 OQ-4/§2.2's census: not
    # this repository's root lock and not its `ci/` lock — a lock no relock of gen's own inputs
    # reaches). It is deliberately left off the hub's relock rather than forgotten: this bench
    # declares only an APP (`flake-compare`) and no `checks.` entry consumes it (den-hoag-6fmmb, the
    # named precedent for "an app that gates nothing"), so branch (b) of OQ-4's rule applies — no
    # gate consumes it, so it is not swept, and the fact is recorded here instead. This `gen` pin
    # therefore drifts on no schedule; bump it by hand (`nix flake update gen` in this directory)
    # whenever the bench's number is next wanted.
    gen.url = "github:sini/gen";
    gen.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, gen, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      # The constructor set: the same five-key map the hub flakeModule hands every hub-fronted
      # tree, built off the roster (`gen.lib.mkGenLibs`) — the bare caller's own constructor merge
      # per compose's caller-total contract. The fixture tree declares `genSchema`/`genMerge`
      # formals only; the full set is supplied so the bench measures the constructor surface the
      # hub actually hands a tree.
      roster = gen.lib.mkGenLibs { };
      genLibs = {
        genMerge = roster.merge;
        genSchema = roster.schema;
        genAspects = roster.aspects;
        genTypes = roster.types;
        genPrelude = roster.prelude;
      };

      # (1) PURE compose — resolve the typed spec tree with the successor compose, no nixpkgs.
      composed = gen.lib.compose {
        modules = (gen.inputs.import-tree.addPath ./gen).files;
        specialArgs = genLibs;
      };
      specs = composed.values;

      # (2) the per-system builder: resolved spec -> derivation at the nixpkgs boundary.
      build =
        pkgs: name: spec:
        if spec.builder == "text" then
          pkgs.writeText name spec.text
        else
          pkgs.writeShellScriptBin name spec.text;

      perSystem = system: rec {
        pkgs = import nixpkgs { inherit system; };
        packages = builtins.mapAttrs (name: spec: build pkgs name spec) specs.packages;
        devShell = pkgs.mkShell {
          packages = map (n: pkgs.${n}) specs.devShell.packages;
          shellHook = specs.devShell.shellHook;
        };
        formatter = build pkgs "fmt" specs.formatter;
      };

      # One realization per system (shared pkgs/spec thunks); the flake outputs project off it, so
      # `nix eval .#packages.<sys>` forces only that system's packages, not its devShell/formatter.
      realized = forAllSystems perSystem;
    in
    {
      packages = builtins.mapAttrs (_: r: r.packages) realized;
      devShells = builtins.mapAttrs (_: r: { default = r.devShell; }) realized;
      formatter = builtins.mapAttrs (_: r: r.formatter) realized;
    };
}
