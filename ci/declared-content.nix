# ── declared-content — the PERMANENT cell over the hub's DELIVERY-CLASS PROJECTION ──────────────
#
# ADR-0028's Rider: a delivery class realizes only on DECLARED CONTENT, never on structural shape.
# Two arms have been measured against this hub, and they fail differently:
#
#   den-hoag-jwm8 — the CONTENTLESS-CLASS arm. A class declared by the grammar and never given
#     content used to project on every member host. The hub read clean on it only by REPRESENTATION
#     COINCIDENCE: gen-aspects renders a declared-but-unset class as `null` (fix `93806f8`), which
#     happens to fail a shape test — a fact about ANOTHER library, not a guarantee. jwm8 measured
#     that gen's own lock pinned `gen-aspects` three days BEFORE that fix, so this hub built EVERY
#     member host under such a class and no cell here would have noticed (0-hit sweep,
#     `reports/den-hoag-jwm8-reduction-flight-v0.md`).
#
#   den-hoag-t3q9 — the WRONG-CATEGORY arm, and the one no shape test can reach. A key declared
#     `category = "channel"` rides its value VERBATIM; a module travelling a channel is the
#     cross-framework exchange payload the category exists for. Its value is therefore the SAME
#     SHAPE as a class's, and the hub's carried `classFieldsOf` — `isAttrs v && v ? imports &&
#     isList v.imports` — classified it as a delivery class and had `realize` call its terminal.
#     A facet declared with a permissive option type does the same.
#
# Both are now held BY CONSTRUCTION rather than by coincidence: `flakeModules/default.nix` no longer
# carries its own predicate at all. It calls `genDelivery.project`, whose `deliveryClassesOf` is
# limb 1 DECLARED `category = "class"` AND limb 2 content present, with shape never consulted.
#
# ★ THIS CELL EXISTS BECAUSE THE HUB'S CALL SITE IS NOT OTHERWISE EVALUATED BY ANY GATE.
# `flakeModules.default` is a PATH the hub exports; only a consumer's flake-parts eval runs its
# body, so nothing here would notice the call losing its declaration input, or reverting to a local
# predicate. gen-delivery's own suite covers the predicate; this one covers the HUB — the same
# pinned `gen.lib.mkGenLibs` roster a consumer gets, wired the way the module wires it, plus a
# lexical arm over the shipped module source for the two facts a value cannot express.
#
# The fixture's discriminating control is `channel-value-passes-the-RETIRED-shape-test`: it restates
# the predicate that was removed and asserts it ADMITS the channel. Without it, "the channel is not
# realized" could be a channel that would have been excluded anyway, which reads identically. The
# channel's value carries a NON-EMPTY `imports`, so limb 2 (content) admits it too — only limb 1,
# the declared category, excludes it. A fixture with `imports = [ ]` would be excluded by both limbs
# and would discriminate nothing.
#
# ADR-0028's other concept, the SHARE class (gen-class's caller-supplied `keyOf`, an equivalence
# over members), appears nowhere in this hub and nothing here classifies by one. Every site below is
# the DELIVERY class: a declared target whose terminal `realize` calls.
{ gen }:
let
  roster = gen.lib.mkGenLibs { lib = null; };
  genMerge = roster.merge;
  genDelivery = roster.delivery;
  genAspects = roster.aspects;

  # THE DECLARATION, written ONCE and handed to both sides — `mkAspectSchema` builds the grammar
  # from it and `project` classifies against it. That is the wiring `gen.aspectCnf` documents for a
  # consumer, exercised here rather than described.
  #
  #   nixos    a class, content GIVEN            → realizes every member host
  #   metrics  a class, content NEVER given      → the jwm8 arm; realizes nothing
  #   chan     a CHANNEL carrying a module value → the t3q9 arm; realizes nothing, same shape
  cnf = {
    keySemantics = {
      nixos.category = "class";
      metrics.category = "class";
      chan.category = "channel";
    };
  };

  schema = genAspects.mkAspectSchema cnf;

  # TWO member hosts, both in `web`, so "realizes no host" and "realizes EVERY member host" are both
  # claims over a non-empty domain.
  eval = genMerge.evalModuleTree {
    modules = [
      { options.schema = schema.schemaOption; }
      (schema.mkAspectModule { })
      {
        config.aspects.web.nixos.networking.hostName = "set";
        # Non-empty `imports`: class-shaped AND content-bearing, so only the declared category
        # can exclude it.
        config.aspects.web.chan.imports = [ { } ];
      }
    ];
  };

  values = {
    inherit (eval.config) aspects;
    hosts = {
      alpha.aspects = [ "web" ];
      beta.aspects = [ "web" ];
    };
  };

  # THE HUB'S OWN WIRING — `flakeModules/default.nix` calls `project` with exactly these two
  # arguments and takes gen-delivery's default `selectHosts`.
  projected = genDelivery.project { inherit values cnf; };
  entry = projected.aspects.web;

  # The RETIRED predicate, restated so the wrong-category arm is a discrimination rather than a
  # fixture that never qualified. Never called by anything shipped.
  retiredShapeTest = v: builtins.isAttrs v && v ? imports && builtins.isList v.imports;

  # A reflecting terminal — the realized shape is assertable without forcing a class body.
  dataTerminal = a: a.name;
  # A terminal that THROWS on invocation, so "the terminal is never called" is a measurement rather
  # than an inference from the output shape.
  tripwireTerminal = a: throw "gen ci declared-content: class terminal invoked for `${a.name}`";
  realizeWith =
    terminal:
    genDelivery.realize {
      inherit projected;
      terminals = {
        nixos = terminal;
        metrics = terminal;
        chan = terminal;
      };
      extraModules = { };
    };
  realized = realizeWith dataTerminal;
  realizedTripwire = realizeWith tripwireTerminal;

  forces = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  # THE LEXICAL ARM over the shipped module — the call site no value can witness.
  moduleSrc = builtins.readFile ../flakeModules/default.nix;
  occurs = tok: builtins.length (builtins.split tok moduleSrc) > 1;

  gate = {
    # ── CONTROLS on the fixture itself ──
    # Every key is genuinely registered by the grammar; without this an absence below could be an
    # unregistered key, which reads identically.
    contentless-class-is-declared = builtins.elem "metrics" (builtins.attrNames entry);
    channel-key-is-declared = builtins.elem "chan" (builtins.attrNames entry);
    # THE DISCRIMINATING CONTROL — the removed shape test ADMITS the channel, so its exclusion below
    # is the DECLARED CATEGORY doing the work and not the fixture failing to qualify.
    channel-value-passes-the-RETIRED-shape-test = retiredShapeTest entry.chan;
    # …and the same test admits the content-given class, so it is not simply blind.
    class-value-passes-the-RETIRED-shape-test = retiredShapeTest entry.nixos;

    # ── ADR-0028's Rider, both arms ──
    # Neither the contentless class nor the channel reaches the per-host class set; the
    # content-given class does.
    only-the-declared-content-class-is-projected =
      builtins.attrNames projected.nodes.alpha.classes == [ "nixos" ];
    # `realize` builds no host under either — jwm8 and t3q9, GUARDED.
    contentless-class-realizes-no-host = builtins.attrNames realized.metrics == [ ];
    channel-realizes-no-host = builtins.attrNames realized.chan == [ ];
    # The names remain output keys — `realize`'s spine is the terminals argument, so key presence is
    # the contract, not a residual of anything having projected.
    class-name-remains-an-output-key =
      builtins.attrNames realized == [
        "chan"
        "metrics"
        "nixos"
      ];
    # CONTROL, same run — the content-given class realizes EVERY member host.
    content-class-realizes-every-member-host =
      builtins.attrNames realized.nixos == [
        "alpha"
        "beta"
      ];
    # The terminal is never invoked for either excluded key.
    terminal-never-called-for-contentless-class = forces realizedTripwire.metrics;
    terminal-never-called-for-channel = forces realizedTripwire.chan;
    # CONTROL, same tripwire, same run — it DOES fire on the content-given class, so the two clean
    # reads above are terminals that were not called, not a tripwire that cannot go off.
    tripwire-fires-for-the-content-class = !(forces realizedTripwire.nixos);

    # ── THE DECLARATION'S ABSENCE IS A REFUSAL, not a degradation ──
    # Constructed with no category source, `project` has nothing left to classify by but the shape
    # test that was removed, so it refuses by name rather than falling back.
    absent-declaration-refuses = !(forces (genDelivery.project { inherit values; }));
    # CONTROL, same call, same run — with the declaration it evaluates, so the refusal above is the
    # missing `cnf` and not a broken fixture.
    present-declaration-evaluates = forces (genDelivery.project { inherit values cnf; }).nodes;

    # ── THE HUB'S CALL SITE ──
    hub-calls-gen-delivery-project = occurs "genDelivery\\.project";
    hub-passes-the-declaration = occurs "cnf = cfg\\.aspectCnf;";
    hub-carries-no-local-class-predicate = !(occurs "isList v\\.imports");
    # CONTROL, same instrument, same run — a token that IS in the file, so the absence above is a
    # predicate that is gone and not a `readFile`/`split` that reads everything as empty.
    lexical-instrument-fires = occurs "flake\\.nixosConfigurations";
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;
}
