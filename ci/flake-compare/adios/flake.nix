{
  # adios-flake variant of the 3-way comparison flake (ci/flake-compare).
  #
  # The SAME outputs as the flake-parts/ and gen-lib/ siblings, expressed idiomatically with
  # adios-flake's `mkFlake` + `perSystem`. adios-flake replaces flake-parts' NixOS-module-system
  # output assembly with adios's direct function dispatch + memoized eval tree — the thing its own
  # published BENCHMARKS.md measures at 28-30% less evaluator cost than flake-parts on a real flake.
  #
  # adios's `pkgs` is already a bare `import inputs.nixpkgs { inherit system; }` (see adios-flake
  # lib.nix `nixpkgsFor`), so no override is needed here — it matches the pkgs construction the other
  # two variants pin. adios-flake carries its own lock for `adios` (github:adisbladis/adios), left
  # unoverridden so the framework is pinned exactly as published.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";
    adios-flake.url = "github:Mic92/adios-flake/957ede25f5aaaeb3b2a502f1bf55e472c80eb7a5";
  };

  outputs =
    inputs@{ adios-flake, self, ... }:
    adios-flake.lib.mkFlake {
      inherit inputs self;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
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
