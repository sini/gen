# ── inject-payload — the PERMANENT O-INJ-2 cell (ADR-0023 (b)'s measured ground, kept measured) ──
#
# gen-bind's `injectAdapter` (crossing-adapter-set.nix) declares the ADR-0023 (b) opt-out WITH its
# price: substrate-built gen TYPE objects cross the inject boundary, inert only because
# `_module.args` is not type-walked by the consuming module system. That disposition rests on a
# MEASUREMENT — O-INJ-2, run over a real `composed.values`: the payload-side predicate "no function
# is reachable, transitively" FAILS on the payload (`values.schema.<kind>.options.*.type` carries
# genuine `check`/`merge` functions). The original run had no permanent home (it needed `compose`,
# unreachable from gen-bind); the hub now has `lib.compose`, so the cell lives here, in the hub's
# checks — asserting the MEASURED state, not a wish.
#
# The tripwire cuts both ways: if a future schema change makes the payload function-free, the
# `payload-reaches-function` key flips FALSE, this check fails, and the ADR-0023 disposition
# re-opens by construction — arm (i) (narrow the payload) would then be live and the declared
# opt-out's ground gone. The two controls travel in the same run, per standing measurement law:
# a plain payload reads clean (the walk does not refuse everything), and a planted closure at a
# substrate-written position is caught (the predicate fires).
{ gen }:
let
  roster = gen.lib.mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)

  # A schema-carrying fixture in the minimal gen-schema instance pattern (a typed `host` kind, a
  # registry, two instances) — the same shape O-INJ-2's original run composed, so the predicate is
  # measured over the class of payload the flakeModule actually injects.
  schemaFixture =
    {
      config,
      genSchema,
      genMerge,
      ...
    }:
    {
      options.schema = genSchema.mkSchemaOption { };
      options.hosts = genSchema.mkInstanceRegistry config.schema.host { };
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        options.role = genMerge.mkOption {
          type = genMerge.types.str;
          default = "worker";
        };
        options.aspects = genMerge.mkOption {
          type = genMerge.types.listOf genMerge.types.str;
          default = [ ];
        };
      };
      config.hosts.igloo = {
        addr = "10.0.1.1";
        role = "web";
        aspects = [ "web" ];
      };
      config.hosts.iceberg = {
        addr = "10.0.2.1";
      };
    };

  composed = gen.lib.compose {
    modules = [ schemaFixture ];
    specialArgs = {
      genSchema = roster.schema;
      genMerge = roster.merge;
    };
  };

  payload = composed.values;

  # The O-INJ-2 predicate: is a FUNCTION reachable, transitively, anywhere in the value? The walk
  # stops AT a function (it never applies one) and recurses through attrsets and lists — the only
  # containers a resolved gen value tree holds.
  anyFunction =
    v:
    if builtins.isFunction v then
      true
    else if builtins.isAttrs v then
      builtins.any anyFunction (builtins.attrValues v)
    else if builtins.isList v then
      builtins.any anyFunction v
    else
      false;

  # Control payloads — same instrument, same run. Plain: no function anywhere. Planted: one closure
  # at a substrate-written position (an instance field), the exact class the predicate must catch.
  plainPayload = {
    hosts.igloo = {
      addr = "10.0.1.1";
      role = "web";
    };
    tags = [
      "a"
      1
      null
    ];
  };
  plantedPayload = plainPayload // {
    hosts = plainPayload.hosts // {
      igloo = plainPayload.hosts.igloo // {
        addr = _: "closure";
      };
    };
  };

  gate = {
    # TRUE today — the ADR-0023 (b) ground, re-measured on every gate run rather than remembered.
    payload-reaches-function = anyFunction payload;
    # The three positions the original O-INJ-2 named, pinned individually: `check` and `merge` are
    # genuine functions at every one of them.
    # The list is EXPLICIT, never `attrNames` — an empty options set would pass a vacuous `all`,
    # and a silently-vanished position is exactly what this cell must not miss.
    schema-type-functions-at-named-positions =
      builtins.all
        (
          n:
          builtins.isFunction payload.schema.host.options.${n}.type.check
          && builtins.isFunction payload.schema.host.options.${n}.type.merge
        )
        [
          "addr"
          "aspects"
          "role"
        ];
    control-plain-clean = anyFunction plainPayload == false;
    control-planted-caught = anyFunction plantedPayload;
  };
in
{
  inherit gate payload;
  gateKeys = builtins.attrNames gate;
}
