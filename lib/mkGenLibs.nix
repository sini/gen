# mkGenLibs: two-stage instantiation of the gen library ecosystem.
#
# Stage 1 (definition time): captures genInputs containing the 8 gen-* flake inputs.
# Stage 2 (consumer time): takes { lib } and returns the fully-wired library set.
#
# This split exists because consumers don't have gen-algebra, gen-schema, etc. as
# inputs — only gen/ does. The consumer provides only nixpkgs.lib.
{ genInputs }:
{ lib }:
let
  # --- independent libraries (no cross-deps) ---

  # gen-algebra: functor, call with { lib }
  algebra = genInputs.gen-algebra { inherit lib; };

  # gen-scope: functor, call with { lib }
  scope = genInputs.gen-scope { inherit lib; };

  # gen-graph: functor, call with { lib }
  graph = genInputs.gen-graph { inherit lib; };

  # gen-bind: .lib flake output (already instantiated with nixpkgs from its flake)
  bind = genInputs.gen-bind.lib;

  # --- libraries with cross-deps ---

  # gen-schema: takes { inputs, lib }, resolves gen-algebra from inputs
  schema = import "${genInputs.gen-schema}/nix/lib" {
    inputs.gen-algebra = algebra;
    inherit lib;
  };

  # gen-aspects: takes { inputs, lib }, resolves gen-schema from inputs
  aspects = import "${genInputs.gen-aspects}/lib" {
    inputs.gen-schema = schema;
    inherit lib;
  };

  # gen-select: takes { lib, genAlgebra }
  select = import "${genInputs.gen-select}/lib" {
    inherit lib;
    genAlgebra = algebra.pure;
  };

  # gen-derive: takes { lib, genAlgebra }
  derive = import "${genInputs.gen-derive}/lib" {
    inherit lib;
    genAlgebra = algebra.pure;
  };
in
{
  inherit
    algebra
    schema
    aspects
    scope
    graph
    select
    bind
    derive
    ;
}
