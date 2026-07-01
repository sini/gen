# flake-parts module: injects gen libraries into _module.args for all submodules.
#
# Usage in a consumer flake:
#   imports = [ inputs.gen.flakeModules.genLibs ];
#
# This makes genAlgebra, genSchema, etc. available as top-level arguments in
# every flake-parts module evaluated by the consumer.
{ lib, inputs, ... }:
let
  genLibs = inputs.gen.lib.mkGenLibs { inherit lib; };
in
{
  _module.args = {
    genAlgebra = genLibs.algebra;
    genSchema = genLibs.schema;
    genAspects = genLibs.aspects;
    genScope = genLibs.scope;
    genGraph = genLibs.graph;
    genSelect = genLibs.select;
    genBind = genLibs.bind;
    genDispatch = genLibs.dispatch;
  };
}
