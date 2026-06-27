# mkGenLibs: two-stage instantiation of the gen library ecosystem.
#
# Stage 1 (definition time): captures genInputs containing the 9 gen-* flake inputs.
# Stage 2 (consumer time): takes { lib } and returns the fully-wired library set.
#
# This split exists because consumers don't have gen-algebra, gen-schema, etc. as
# inputs — only gen/ does. The consumer provides only nixpkgs.lib.
{ genInputs }:
{ lib }:
let
  # --- independent libraries (no cross-deps) ---

  # gen-prelude: pure utilities, zero deps (the nixpkgs-lib-free base). Takes no args.
  prelude = import "${genInputs.gen-prelude}/lib" { };

  # gen-algebra: functor, call with { lib }
  algebra = genInputs.gen-algebra { inherit lib; };

  # gen-scope: functor, call with { lib }
  scope = genInputs.gen-scope { inherit lib; };

  # gen-graph: functor, call with { lib }
  graph = genInputs.gen-graph { inherit lib; };

  # gen-bind: nixpkgs-lib-free, built from gen-prelude (module-system-aware via
  # locally-vendored convention helpers, not nixpkgs.lib).
  bind = import "${genInputs.gen-bind}/lib" { inherit prelude; };

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

  # gen-select: zero dependencies (intensionalEq inlined; no lib, no gen-algebra).
  select = import "${genInputs.gen-select}/lib" { };

  # gen-derive: nixpkgs-lib-free + gen-algebra-free (the dead gen-algebra dep was
  # dropped; toposort/filterAttrs/imap0/unique come from gen-prelude).
  derive = import "${genInputs.gen-derive}/lib" { inherit prelude; };
in
{
  inherit
    prelude
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
