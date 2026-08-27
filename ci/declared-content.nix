# ── declared-content — the PERMANENT cell over the hub's CARRIED PROJECTION (den-hoag-jwm8) ──
#
# ADR-0028's Rider: a delivery class realizes only on DECLARED CONTENT, never on structural shape.
# gen-delivery's own successor surface (`project`/`realize`) holds this by construction
# (gen-delivery/lib/default.nix:86-104) and ships its own declared-content suite — but the HUB does
# not call `genDelivery.project`. `flakeModules/default.nix` carries its OWN structural projection
# ("THE CARRIED PROJECTION" in that file's header — `classFieldsOf`/`projectHosts`) straight into
# `genDelivery.realize`, and that carried predicate tests the deferredModule LIST SHAPE
# (`? imports && isList imports`), never the aspect grammar's declared category. Until 2026-08-27
# that carried predicate discharged the Rider only by REPRESENTATION COINCIDENCE: gen-aspects
# renders a declared-but-contentless class as `null` (fix `93806f8`), which happens to fail the
# shape test — a fact about ANOTHER library, not a guarantee this predicate holds. den-hoag-jwm8
# measured that gen's own lock pinned `gen-aspects` three days BEFORE that fix, so this hub built
# EVERY member host under a class that was declared and never given content, and no cell here would
# have noticed (0-hit sweep, `reports/den-hoag-jwm8-reduction-flight-v0.md`).
#
# This cell re-derives jwm8's end-to-end probe as a permanent gate: `classFieldsOf`/`projectHosts`
# copied VERBATIM from `flakeModules/default.nix` (not exported as a library call — carried code, so
# the cell must carry the same code to test the CARRIED path rather than gen-delivery's), fed the
# REAL pinned `gen.lib.mkGenLibs` roster — the exact composition a consumer of this hub gets —
# through `genDelivery.realize`. If the two copies of `classFieldsOf`/`projectHosts` are ever let
# drift apart, this cell is testing something other than the shipped predicate; there is no
# mechanical guard against that drift, only this comment.
{ gen }:
let
  roster = gen.lib.mkGenLibs { lib = null; };
  genMerge = roster.merge;
  genDelivery = roster.delivery;
  genAspects = roster.aspects;

  # ── VERBATIM from gen/flakeModules/default.nix (classFieldsOf / projectHosts) ──
  classFieldsOf =
    entry:
    builtins.filter (
      k:
      let
        v = entry.${k};
      in
      builtins.isAttrs v && v ? imports && builtins.isList v.imports
    ) (builtins.attrNames entry);

  dedup =
    xs:
    builtins.attrNames (
      builtins.listToAttrs (
        map (x: {
          name = x;
          value = null;
        }) xs
      )
    );

  projectHosts =
    selectHosts: values: aspects:
    let
      hosts = selectHosts values;
      _hostsCheck =
        if builtins.isAttrs hosts then
          null
        else
          throw "compose: selectHosts must return an attrset of host instances ({ <host> = <instance>; }), got ${builtins.typeOf hosts}";
    in
    builtins.seq _hostsCheck (
      builtins.mapAttrs (
        _hostName: inst:
        let
          memberAspects = builtins.filter (a: aspects ? ${a}) (inst.aspects or [ ]);
          classNames = dedup (builtins.concatMap (a: classFieldsOf aspects.${a}) memberAspects);
          collectClass =
            class:
            builtins.concatMap (
              a:
              let
                entry = aspects.${a};
              in
              if builtins.elem class (classFieldsOf entry) then [ entry.${class} ] else [ ]
            ) memberAspects;
        in
        {
          bindings = {
            node = inst;
          };
          classes = builtins.listToAttrs (
            map (c: {
              name = c;
              value = collectClass c;
            }) classNames
          );
        }
      ) hosts
    );

  # ONE aspect declaring TWO classes, content on exactly one — `metrics` is the axis: declared by
  # the grammar, never set by any definition; `nixos` is the same-shape sibling that IS set. TWO
  # member hosts, both in `web`, so "realizes no host" and "realizes EVERY member host" are both
  # claims over a non-empty domain (gen-delivery's own `ci/tests/declared-content.nix` fixture
  # shape, re-derived here rather than transferred — this fixture's entry points are the hub's).
  schema = genAspects.mkAspectSchema {
    keySemantics = {
      nixos.category = "class";
      metrics.category = "class"; # DECLARED, never given content anywhere
    };
  };
  eval = genMerge.evalModuleTree {
    modules = [
      { options.schema = schema.schemaOption; }
      (schema.mkAspectModule { })
      { config.aspects.web.nixos.networking.hostName = "set"; }
    ];
  };
  registry = genAspects.flatten eval.config.aspects;
  entry = registry.web;

  values = {
    hosts = {
      alpha.aspects = [ "web" ];
      beta.aspects = [ "web" ];
    };
  };
  projected = projectHosts (v: v.hosts or { }) values registry;

  # A reflecting terminal — the realized shape is assertable without forcing a class body.
  dataTerminal = a: a.name;
  realized = genDelivery.realize {
    projected = {
      nodes = projected;
    };
    terminals = {
      nixos = dataTerminal;
      metrics = dataTerminal;
    };
    extraModules = { };
  };

  # A terminal that THROWS on invocation, so "the terminal is never called for a contentless
  # class" is a measurement rather than an inference from the output shape.
  tripwireTerminal = a: throw "gen ci declared-content: class terminal invoked for `${a.name}`";
  realizedTripwire = genDelivery.realize {
    projected = {
      nodes = projected;
    };
    terminals = {
      nixos = tripwireTerminal;
      metrics = tripwireTerminal;
    };
    extraModules = { };
  };

  forces = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  gate = {
    # CONTROL — the class is genuinely registered by the grammar; without this the absence below
    # could be an unregistered class, which reads identically.
    contentless-class-is-declared = builtins.elem "metrics" (builtins.attrNames entry);
    # …yet absent from the CARRIED projection's per-host class set, while its content-given
    # sibling is present.
    contentless-class-not-projected = builtins.attrNames projected.alpha.classes == [ "nixos" ];
    # `realize` builds no host under the contentless class — THE jwm8 DEFECT, GUARDED.
    contentless-class-realizes-no-host = builtins.attrNames realized.metrics == [ ];
    # The class name remains an output key — `realize`'s spine is the terminals argument, so key
    # presence is the contract, not a residual of the class having projected.
    class-name-remains-an-output-key =
      builtins.attrNames realized == [
        "metrics"
        "nixos"
      ];
    # CONTROL, same run — the content-given class realizes EVERY member host.
    content-class-realizes-every-member-host =
      builtins.attrNames realized.nixos == [
        "alpha"
        "beta"
      ];
    # The class terminal is never invoked for the contentless class.
    terminal-never-called-for-contentless-class = forces realizedTripwire.metrics;
    # CONTROL, same tripwire, same run — it DOES fire on the content-given class, so the clean read
    # above is a terminal that was not called, not a tripwire that cannot go off.
    tripwire-fires-for-the-content-class = !(forces realizedTripwire.nixos);
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;
}
