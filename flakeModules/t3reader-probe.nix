# T3 — a SYNTACTIC membership read (ien5k round 2, probe). Reads a registry option's raw definitions
# (`definitionsWithLocations`) and answers a node's declared `aspects` without merging the registry or
# evaluating the node's instance, or `null` (FALL BACK to the module-system read) wherever the
# definitions do not decide it alone:
#   R1 a registry definition that is not a plain attrset (a property: mkMerge/mkIf/mkOverride/…, or a
#      function / path)                                                ⇒ every node falls back
#   R2 the kind's `aspects` declaration carries an `apply`               ⇒ every node falls back
#   N1 a node definition that is not a plain attrset, or is module-shaped (`imports`/`config`/`options`)
#   N2 not exactly one definition of the node states `aspects`
#   N3 that `aspects` is not a plain list of strings (a property, a function, …)
# `naive = true` drops every guard (the RED reader): first definition's `aspects`, else `[ ]`.
{ naive ? false }:
opt:
let
  defs = map (d: d.value) opt.definitionsWithLocations;
  plain = v: builtins.isAttrs v && !(v ? _type);
  sub = (opt.type.getSubOptions [ ]).aspects or null;
  wholeOk = builtins.all plain defs && sub != null && !(sub ? apply);
in
if naive then
  n:
  let
    nd = builtins.concatMap (v: if builtins.isAttrs v && v ? ${n} then [ v.${n} ] else [ ]) defs;
    withA = builtins.filter (v: builtins.isAttrs v && v ? aspects) nd;
  in
  if withA == [ ] then [ ] else (builtins.head withA).aspects
else if !wholeOk then
  _: null
else
  n:
  let
    nd = builtins.concatMap (v: if v ? ${n} then [ v.${n} ] else [ ]) defs;
    withA = builtins.filter (v: v ? aspects) nd;
    a = (builtins.head withA).aspects;
  in
  if
    builtins.all (v: plain v && !(v ? imports || v ? config || v ? options)) nd
    && builtins.length withA == 1
    && builtins.isList a
    && builtins.all builtins.isString a
  then
    a
  else
    null
