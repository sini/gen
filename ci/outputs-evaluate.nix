# ── outputs-evaluate — the hub's flake-parts `evaluate` through gen-bind's outputs terminal ──
#
# `lib.flakePartsEvaluate` (the root flake, den-hoag-52hn7) is the ONE flake-parts binding of
# gen-bind's `crossing.mkOutputsTerminal evaluate`, on ADR-0031 F1's interim surface. A hub surface
# no gate evaluates has no gate, so this cell runs it over the REAL flake-parts this ci pins: a body
# writing a flake output and reading `inputs.self`, `config.systems` and the inputs' names must come
# back as the body's `flake` outputs, with all three reaching it.
#
# Every read is `or null`-guarded and `tryEval`-wrapped, so a wrong shape reads `false` rather than
# aborting the gate. The control is the empty body: it must carry no output, so a gate that answered
# the fixture's value from anywhere but the body would read red.
{ gen, flake-parts }:
let
  roster = gen.lib.mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)

  evaluate = gen.lib.flakePartsEvaluate {
    inherit (flake-parts.lib) evalFlakeModule;
    inputs.upstream = "an-input";
    self = {
      marker = "the-self";
      outPath = "/dev/null";
    };
    systems = [ "x86_64-linux" ];
  };

  run = body: (roster.bind.crossing.mkOutputsTerminal evaluate).adapter.wrapUnit body [ ];

  out = run [
    { flake.alpha = 1; }
    (
      { inputs, config, ... }:
      {
        flake.sawSelf = (inputs.self or { }).marker or null;
        flake.sawSystems = config.systems;
        flake.sawInputs = builtins.attrNames inputs;
      }
    )
  ];

  t =
    v:
    let
      e = builtins.tryEval (builtins.deepSeq v v);
    in
    e.success && e.value;

  gate = {
    outputs-are-the-body-flake = t ((out.alpha or null) == 1);
    self-reaches-the-body = t ((out.sawSelf or null) == "the-self");
    systems-reach-the-body = t ((out.sawSystems or null) == [ "x86_64-linux" ]);
    inputs-carry-self = t (
      (out.sawInputs or null) == [
        "self"
        "upstream"
      ]
    );
    control-empty-body-has-no-output = t (!((run [ ]) ? alpha));
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;
}
