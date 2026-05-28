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
let
  genInputs = inputs;
in
{
  inputs,
  name,
  testModules,
  specialArgs ? { },
}:
let
  inherit (inputs.nixpkgs) lib;
  # Resolve an input: prefer consumer's if present, fall back to gen's.
  resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name};
  import-tree = import (resolve "import-tree");
in
(resolve "flake-parts").lib.mkFlake
  {
    inherit inputs;
    specialArgs = {
      inherit name genInputs;
    }
    // specialArgs;
  }
  {
    imports = [
      (resolve "treefmt-nix").flakeModule
      (resolve "devshell").flakeModule
      (resolve "flake-root").flakeModule
      (resolve "git-hooks-nix").flakeModule
      ./flakeModule.nix
      (import-tree testModules)
    ];
  }
