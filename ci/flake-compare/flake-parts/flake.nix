{
  # flake-parts variant of the 3-way comparison flake (ci/flake-compare).
  #
  # The SAME outputs as the adios/ and gen-lib/ siblings — three trivial packages, one devShell,
  # one formatter, across x86_64-linux / aarch64-linux / x86_64-darwin — expressed idiomatically with
  # flake-parts' `perSystem`. The derivation-constructing expressions (writeShellScriptBin / writeText
  # / mkShell) are byte-identical across all three variants, so `flake-compare.sh`'s drvPath
  # equivalence check holds and the only measured difference is the framework's output-assembly cost.
  #
  # `pkgs` is pinned to a BARE `import nixpkgs { inherit system; }` (overriding flake-parts' default
  # `legacyPackages` provider) so all three variants construct pkgs identically — the pkgs closure is
  # then a shared constant and the eval delta is pure framework machinery (the NixOS module system's
  # evalModules / option merge here). This is the standard flake-parts override pattern.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";
    flake-parts.url = "github:hercules-ci/flake-parts/17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
      ];

      perSystem =
        { system, pkgs, ... }:
        {
          # Bare import — identical pkgs construction to the adios/ and gen-lib/ variants.
          _module.args.pkgs = import nixpkgs { inherit system; };

          packages = {
            greeter = pkgs.writeShellScriptBin "greeter" ''echo "hello from flake-compare"'';
            farewell = pkgs.writeShellScriptBin "farewell" ''echo "goodbye, $1"'';
            notes = pkgs.writeText "notes" "flake-compare shared notes\n";
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.hello
              pkgs.jq
            ];
            shellHook = "echo entering flake-compare devshell";
          };

          formatter = pkgs.writeShellScriptBin "fmt" "echo formatting; exit 0";
        };
    };
}
