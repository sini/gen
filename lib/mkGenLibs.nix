# mkGenLibs: two-stage instantiation of the gen library ecosystem.
#
# Stage 1 (definition time): captures genInputs (the gen-* flake inputs).
# Stage 2: each lib is self-wired — every gen flake exposes a `.lib` value that
# resolves its own deps internally (gen-schema owns its gen-algebra input, etc.),
# so the hub just re-exports `genInputs.gen-X.lib`. The `lib` arg is now vestigial
# (real consumers read `inputs.gen-X.lib` directly); kept as `_` for call-compat.
{ genInputs }:
_:
{
  prelude = genInputs.gen-prelude.lib;
  algebra = genInputs.gen-algebra.lib;
  scope = genInputs.gen-scope.lib;
  graph = genInputs.gen-graph.lib;
  bind = genInputs.gen-bind.lib;
  schema = genInputs.gen-schema.lib;
  aspects = genInputs.gen-aspects.lib;
  select = genInputs.gen-select.lib;
  derive = genInputs.gen-derive.lib;
  resolve = genInputs.gen-resolve.lib;
}
