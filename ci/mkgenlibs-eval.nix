# mkgenlibs-eval — the hub's own wiring smoke check.
#
# `gen.lib.mkGenLibs` is the PUBLISHED two-stage instantiation every consumer (den-hoag, the lib
# repos) reaches the ecosystem through. A bad pin bump or a lib whose `.lib` signature drifts breaks
# the wiring silently — no consumer catches it until their OWN eval throws. This forces every key of
# the hub's mkGenLibs so a broken wiring — or a dropped/added roster key — fails `nix flake check ./ci`.
#
# `gen` is the hub itself (`path:..`) — the ci subflake can't `import ../lib` (escapes its flake root),
# so it reaches the root lib through an input, exactly like den-hoag's ci reaches den-hoag. This checks
# the ROOT flake.lock pins — the surface consumers actually get via `gen.lib.mkGenLibs`.
{ gen }:
let
  genLibs = gen.lib.mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)
  actualKeys = builtins.attrNames genLibs;

  # The 19-key roster (lib/mkGenLibs.nix). A roster change is intentional: bump this list in the SAME
  # commit that adds/removes a lib, so this stays a tripwire rather than silent drift.
  expectedKeys = [
    "algebra"
    "aspects"
    "bind"
    "class"
    "demand"
    "dispatch"
    "edge"
    "flake"
    "graph"
    "merge"
    "pipe"
    "prelude"
    "product"
    "resolve"
    "schema"
    "scope"
    "select"
    "settings"
    "types"
  ];

  missing = builtins.filter (k: !(builtins.elem k actualKeys)) expectedKeys;
  extra = builtins.filter (k: !(builtins.elem k expectedKeys)) actualKeys;
  rosterOk = missing == [ ] && extra == [ ];

  # Force each key: deepSeq the lib's top-level attrset + values to WHNF — catches a broken import
  # wiring (missing dep arg, dep-signature drift) WITHOUT calling into each function. tryEval turns a
  # throw into `false`, so the check names WHICH key broke instead of aborting the whole eval. Forces
  # every ACTUAL key (not just the roster), so a newly-added broken key is exercised too.
  wired = builtins.listToAttrs (
    map (k: {
      name = k;
      value = (builtins.tryEval (builtins.deepSeq genLibs.${k} true)).success;
    }) actualKeys
  );
in
{
  # Flat gate record for the check helper: each actual key → wiring-ok, plus the roster tripwire.
  gate = wired // {
    roster-ok = rosterOk;
  };
  gateKeys = actualKeys ++ [ "roster-ok" ];
  # Raw, for `nix eval ./ci#lib.mkGenLibsEval --json | jq`.
  keyCount = builtins.length actualKeys;
  keys = actualKeys;
  inherit expectedKeys missing extra;
}
