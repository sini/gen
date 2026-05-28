# mkCi — convenience wrapper for gen ecosystem CI flakes.
#
# Called from gen's root flake as:
#   lib.mkCi = import ./ci/mkCi.nix { inherit inputs; };
#
# Consumers call it as:
#   gen.lib.mkCi {
#     inherit inputs;
#     name = "gen-schema";
#     testModules = ./tests;
#     specialArgs = { inherit schemaLib genLib; };
#   };
{ inputs }:
{
  inputs,
  name,
  testModules,
  specialArgs ? { },
}:
let
  inherit (inputs.nixpkgs) lib;
  import-tree = import inputs.import-tree;
in
inputs.flake-parts.lib.mkFlake
  {
    inherit inputs;
    specialArgs = {
      inherit name;
    }
    // specialArgs;
  }
  {
    imports = [
      inputs.treefmt-nix.flakeModule
      inputs.devshell.flakeModule
      inputs.flake-root.flakeModule
      ./flakeModule.nix
      (import-tree testModules)
    ];
  }
