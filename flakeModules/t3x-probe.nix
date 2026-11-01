# PROBE (ien5k T3 precondition; never a main). The syntactic membership read with its precondition
# SIMULATED: `pub.<field>` stands for gen-schema's publication of the definitions an instance receives
# for a field from everything but the node's own definitions (the kind tree, extraModules), `null`
# where an opaque module or the registry pipeline reaches the field. The node's own definitions are
# read off the registry option's served `definitionsWithLocations`, each node module classified by
# gen-merge's published `moduleSyntax`; more than one definition in all is `null` (their order is
# gen-merge's collection law). The value is gen-merge's own option fold, `mergeOption`.
{ genMerge }:
let
  syn = genMerge.moduleSyntax;
  plain = v: builtins.isAttrs v && !(v ? _type) && !(v ? __functor);
  structuredMeta = builtins.filter (k: k != "config" && k != "_file") syn.structured;
  shorthandMeta = builtins.filter (k: k != "_file") syn.shorthandMeta;
  hasAny = ks: m: builtins.any (k: m ? ${k}) ks;
  defsIn =
    field: file: m:
    if !(plain m) then
      null
    else if hasAny syn.structuring m then
      if hasAny structuredMeta m then
        null
      else if !(m ? config) then
        [ ]
      else if !(plain m.config) then
        null
      else if m.config ? ${field} then
        [
          {
            inherit file;
            value = m.config.${field};
          }
        ]
      else
        [ ]
    else if hasAny shorthandMeta m then
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
  decl = (regOpt.type.getSubOptions [ ]).${field} or null;
  instanceDefinitions =
    node:
    let
      per = map (d: if d.value ? ${node} then defsIn field d.file d.value.${node} else [ ]) rdefs;
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
