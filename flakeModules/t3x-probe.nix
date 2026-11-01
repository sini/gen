# PROBE (ien5k T3 precondition; never a main). The syntactic membership read with its precondition
# SIMULATED: `pub.<field>` stands for gen-schema's publication of the definitions an instance receives
# for a field from everything but the node's own definitions, `null` where gen-schema cannot state them.
# A node's own definitions are the registry option's served `definitionsWithLocations` values for it;
# exactly one definition in all, folded by gen-merge's option fold with the single-definition statement
# (variant G3: G2 with the element type's `shorthandOnlyDefinesConfig` in place of a module classification).
{ genMerge }:
let
  plain = v: builtins.isAttrs v && !(v ? _type) && !(v ? __functor);
  # A definition of an instance is its CONFIG where the element type says so (`shorthandOnlyDefinesConfig`,
  # the type's own statement, as nixpkgs' `submodule` reads an attrset definition); anything not a plain
  # attrset, or not a type stating it, is not syntactic here.
  defsIn =
    shorthand: undeclared: field: file: m:
    if !shorthand || !(plain m) || undeclared m then
      null
    else if m ? ${field} then
      [
        {
          inherit file;
          value = m.${field};
        }
      ]
    else
      [ ];
in
{
  regOpt,
  loc,
  pub,
  field ? "aspects",
}:
let
  side = if pub == null then null else pub.${field} or null;
  rdefs = regOpt.definitionsWithLocations;
  wholeOk = side != null && builtins.all (d: plain d.value) rdefs;
  subOpts = regOpt.type.getSubOptions [ ];
  shorthand = (regOpt.type.nestedTypes.elemType or { }).shorthandOnlyDefinesConfig or false;
  decl = subOpts.${field} or null;
  # SIMULATES gen-schema's strict check (strict.nix `unmatchedPaths`, top level only here): a key the
  # kind does not declare makes the module read refuse, so the reader must not serve
  undeclared = c: builtins.any (k: !(subOpts ? ${k})) (builtins.attrNames c);
  instanceDefinitions =
    node:
    let
      per = map (d: if d.value ? ${node} then defsIn shorthand undeclared field d.file d.value.${node} else [ ]) rdefs;
      all = side ++ builtins.concatLists per;
    in
    if builtins.any (x: x == null) per || builtins.length all > 1 then null else all;
in
if !wholeOk || decl == null then
  _: null
else
  node:
  let
    d = instanceDefinitions node;
  in
  if d == null then
    null
  else
    # value-only option fold with the single-definition statement (what gen-merge would publish):
    # a lone property-free definition outranks the declared default, so the fold reads it alone
    let
      lone = builtins.length d == 1 && !((builtins.head d).value ? _type);
      readOnly = decl.readOnly or false;
      seeded =
        if decl ? default then
          [
            {
              file = "<default>";
              value = genMerge.mkOptionDefault decl.default;
            }
          ]
          ++ d
        else
          d;
      ds = if !readOnly && lone then d else seeded;
      v = genMerge.mergeDefs (
        loc
        ++ [
          node
          field
        ]
      ) decl.type ds;
    in
    if readOnly && builtins.length seeded > 1 then null else if decl ? apply then decl.apply v else v
