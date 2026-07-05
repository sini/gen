{
  # gen-flake variant of the 3-way comparison flake (ci/flake-compare).
  #
  # IDIOM CHOICE (documented honestly): gen-flake's `flakeModules.default` is HOST-oriented — it
  # composes a gen tree and realizes `nixosConfigurations` through the nixosSystem terminal. It has no
  # perSystem `packages`/`devShells`/`formatter` path, so it does NOT fit this flake's outputs. The
  # idiomatic gen-flake expression here is therefore the LIBRARY directly:
  #
  #   1. `gen-flake.lib.compose { tree = ./gen; }` — the PURE half. gen-merge's byte-mode
  #      `evalModuleTree` resolves the typed spec tree (packages registry + devShell/formatter specs)
  #      with ZERO nixpkgs. This is the gen framework machinery this bench measures.
  #   2. a hand-rolled per-system builder at the nixpkgs boundary, reading `composed.values` directly
  #      — the compose+own-builder path for consumers off the realize/nixosConfigurations track. It
  #      maps each resolved spec to a derivation (`import nixpkgs { inherit system; }`, identical to
  #      the other two variants); it does not go through gen-flake's `realize`/`terminals`.
  #
  # This is value-injection, not type-driving: the resolved VALUES cross into nixpkgs, gen TYPES never
  # do. The derivation-constructing calls are byte-identical to the flake-parts/ and adios/ variants,
  # so the drvPath equivalence check holds. gen-flake pins the whole pure gen stack (gen-merge /
  # gen-schema / gen-aspects / ...) as transitive inputs; its own nixpkgs (terminal-only) follows ours.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";
    gen-flake.url = "github:sini/gen-flake/16aafe641aa7f9bb20b84a979ae90d97bda65ef8";
    gen-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, gen-flake, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      # (1) PURE compose — resolve the typed spec tree with the gen-merge engine, no nixpkgs.
      composed = gen-flake.lib.compose { tree = ./gen; };
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
