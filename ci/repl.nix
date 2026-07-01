# gen ecosystem REPL — all libraries in scope.
# Every gen flake exposes a `.lib` value output (the canonical convention), so each
# library is reached uniformly via `(getFlake "gen-X").lib`.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  inherit (nixpkgs) lib;

  genAlgebra = (builtins.getFlake "gen-algebra").lib;
  genSchema = (builtins.getFlake "gen-schema").lib;
  genAspects = (builtins.getFlake "gen-aspects").lib;
  genScope = (builtins.getFlake "gen-scope").lib;
  genGraph = (builtins.getFlake "gen-graph").lib;
  genSelect = (builtins.getFlake "gen-select").lib;
  genBind = (builtins.getFlake "gen-bind").lib;
  genDispatch = (builtins.getFlake "gen-dispatch").lib;
  genResolve = (builtins.getFlake "gen-resolve").lib;
in
{
  inherit lib;
  inherit
    genAlgebra
    genSchema
    genAspects
    genScope
    genGraph
    genSelect
    genBind
    genDispatch
    genResolve
    ;

  # Shortcuts for the most common primitives (gen-algebra is the flat value set).
  inherit (genAlgebra)
    mkIntensional
    intensionalEq
    either
    record
    search
    ;
  inherit (genSchema) mkValidator; # relocated from gen-algebra 2026-06-26
}
