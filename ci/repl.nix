# gen ecosystem REPL — all libraries in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  inherit (nixpkgs) lib;

  genAlgebra = import (builtins.getFlake "gen-algebra") { inherit lib; };
  genSchema = (builtins.getFlake "gen-schema").lib;
  genAspects = import "${builtins.getFlake "gen-aspects"}/lib" { inherit lib; };
  genScope = import (builtins.getFlake "gen-scope") { inherit lib; };
  genGraph = import (builtins.getFlake "gen-graph") { inherit lib; };
  genSelect = import "${builtins.getFlake "gen-select"}/lib" { inherit lib; };
  genBind = (builtins.getFlake "gen-bind").lib;
  genDerive = import "${builtins.getFlake "gen-derive"}/lib" { inherit lib; };
in
{
  inherit lib;
  inherit genAlgebra genSchema genAspects genScope genGraph genSelect genBind genDerive;

  # Shortcuts for the most common primitives
  inherit (genAlgebra.lib) mkIntensional intensionalEq;
  inherit (genAlgebra) either;
  inherit (genSchema) mkValidator; # relocated from gen-algebra 2026-06-26
  record = genAlgebra.lib.record;
  search = genAlgebra.lib.search;
}
