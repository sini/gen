# ci-declares-no-member — this ci flake declares no `gen` input and no roster member.
#
# ── WHAT IT HOLDS ──
# The hub's ci reaches the root flake as `gen`, bound in `outputs` by `builtins.getFlake` of `self`
# (den-hoag-lbtnv D1), so `gen.inputs.gen-X` resolves through the ROOT `flake.lock` and this ci lock
# holds no copy of any member. That one-pin-set property is what the retired `lock-agreement` gated
# while the copy existed; with no copy it holds by construction, and the one act that would re-form
# the copy is a DECLARATION in `ci/flake.nix`: a `gen` input (by `path:..`, which Lix also refuses,
# or by `github:sini/gen`, which ci-self-input also refuses), or a roster member re-declared here,
# which reverses den-hoag-erls and which nothing else in this ci would see.
#
# ── REACH, STATED SO IT IS NOT OVER-READ ──
# By INPUT NAME, over `(import ./flake.nix).inputs`, against `gen` plus `gen-<key>` for every key of
# the roster of record, `gen.lib.mkGenLibs { }` minus `strata`. It does not read URLs: a member
# re-declared under another name is outside its reach, and `gen-schema-orig` and `gen-select-orig` —
# the frozen reference pins of gen-schema and gen-select, each a different revision by design — are
# outside it on purpose.
# Input names are also what `relock-plan` reads its ordering edges from, so this guards the same
# surface the planner sees.
#
# ── THE ARMING IS IN THE CELL, AND IT GATES ──
# Two seeds, each the live declaration set with one forbidden input added: `gen` itself, and the
# first roster member. Each must be named, read as a delta against the live reading. A third reads the live set with `gen-harness` added again
# and must stay clean, so the predicate is shown not to fire on every `gen-` name.
{ gen, lib }:
let
  rosterKeys = builtins.attrNames (builtins.removeAttrs (gen.lib.mkGenLibs { }) [ "strata" ]);
  forbidden = [ "gen" ] ++ map (k: "gen-${k}") rosterKeys;

  declared = (import ./flake.nix).inputs;
  hitsIn = inputs: builtins.filter (n: builtins.elem n forbidden) (builtins.attrNames inputs);

  live = hitsIn declared;
  firstMember = "gen-${builtins.head rosterKeys}";
  seededGen = hitsIn (declared // { gen.url = "path:.."; });
  seededMember = hitsIn (declared // { ${firstMember}.url = "github:sini/${firstMember}"; });
  seededHarness = hitsIn (declared // { gen-harness.url = "github:sini/gen-harness"; });

  # Each seed is read as a DELTA against the live reading, so a real hit does not also read as an
  # arming failure and send the reader at a sound predicate.
  delta = seeded: lib.subtractLists live seeded;
  gate = {
    live-declares-none = live == [ ];
    arming-roster-nonempty = builtins.length rosterKeys > 0;
    arming-gen-is-named = delta seededGen == [ "gen" ];
    arming-member-is-named = delta seededMember == [ firstMember ];
    arming-harness-is-not = delta seededHarness == [ ];
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;
  report = {
    governs = "the input declarations of the hub's ci/flake.nix";
    property = "no input named `gen` or `gen-<roster key>`: members are reached through `gen`, the root flake read at `self`, at the root flake.lock's pins";
    inherit live forbidden;
    arming = {
      inherit seededGen seededMember seededHarness;
    };
  };
}
