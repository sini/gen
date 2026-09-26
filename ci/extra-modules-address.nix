# ── extra-modules-address — the PERMANENT cell over the hub's ADDRESSED extras inlet ──────────────
#
# gen-delivery's `realize` takes its extras CLASS-MAJOR, `{ <class>.<node> = [ module ]; }`, so a
# terminal receives only what was addressed to its own class at its own node (den-hoag-9vkq). The
# hub's `gen.extraModules` is documented as "per-node extra NixOS modules", so the module addresses
# it to `nixos`: `extraModules = { nixos = cfg.extraModules; }`. Before that, the node-keyed map
# reached EVERY class in `gen.terminals`, and a node with no nixos content dropped its extras with no
# word.
#
# ★ THIS CELL EXISTS BECAUSE THE HUB'S CALL SITE IS NOT OTHERWISE EVALUATED BY ANY GATE — the same
# reason `declared-content.nix` gives. `flakeModules.default` is a PATH the hub exports; only a
# consumer's flake-parts eval runs its body. So there are two arms:
#
#   VALUE    the pinned `gen.lib.mkGenLibs` roster's `realize`, wired the way the module wires it:
#            the extras reach nixos only, and an address that does not realize refuses. It fails if
#            the pin moves to a gen-delivery whose inlet is class-blind or silent.
#   LEXICAL  the shipped module source addresses the extras to `nixos` and passes no node-keyed map
#            — the call-site fact no value here can witness.
{ gen }:
let
  roster = gen.lib.mkGenLibs { lib = null; };
  genMerge = roster.merge;
  genDelivery = roster.delivery;
  genAspects = roster.aspects;

  # Two content classes, so "nixos only" is a claim a class-blind inlet can fail.
  cnf = {
    keySemantics = {
      nixos.category = "class";
      peer.category = "class";
    };
  };

  schema = genAspects.mkAspectSchema cnf;

  eval = genMerge.evalModuleTree {
    modules = [
      { options.schema = schema.schemaOption; }
      (schema.mkAspectModule { })
      {
        config.aspects.web.nixos.networking.hostName = "set";
        config.aspects.web.peer.marker = "peer";
        config.aspects.side.peer.marker = "peer";
      }
    ];
  };

  #   alpha, beta  nixos AND peer content
  #   gamma        peer content only — nixos does not realize there
  values = {
    inherit (eval.config) aspects;
    hosts = {
      alpha.aspects = [ "web" ];
      beta.aspects = [ "web" ];
      gamma.aspects = [ "side" ];
    };
  };

  projected = genDelivery.project {
    inherit values cnf;
    selectNodes = v: v.hosts;
  };

  reflect = a: a;
  extra = {
    system.stateVersion = "24.05";
  };

  # THE HUB'S OWN WIRING — the consumer's node-keyed `gen.extraModules`, addressed to `nixos`.
  realizeHub =
    consumerExtras:
    genDelivery.realize {
      inherit projected;
      terminals = {
        nixos = reflect;
        peer = reflect;
      };
      extraModules = {
        nixos = consumerExtras;
      };
    };
  realized = realizeHub { alpha = [ extra ]; };

  forces = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  # THE LEXICAL ARM over the shipped module — the call site no value can witness.
  moduleSrc = builtins.readFile ../flakeModules/default.nix;
  occurs = tok: builtins.length (builtins.split tok moduleSrc) > 1;

  gate = {
    # ── VALUE: the extras reach nixos at their node, and nowhere else ──
    extras-reach-the-nixos-terminal = realized.nixos.alpha.extraModules == [ extra ];
    extras-never-reach-a-peer-class = realized.peer.alpha.extraModules == [ ];
    extras-never-reach-an-unaddressed-node = realized.nixos.beta.extraModules == [ ];
    # CONTROL — the peer class does realize at alpha, so the absence above is an inlet that did not
    # deliver there, not a class that never built.
    peer-class-realizes-at-the-addressed-node =
      builtins.attrNames realized.peer == [
        "alpha"
        "beta"
        "gamma"
      ];

    # ── VALUE: an address that does not realize refuses, never drops ──
    extras-for-a-node-without-nixos-content-refuse =
      !(forces (realizeHub { gamma = [ extra ]; }).nixos);
    extras-for-an-unprojected-node-refuse = !(forces (realizeHub { delta = [ extra ]; }).nixos);
    # The pre-9vkq call — the node-keyed map handed straight through — is the retired shape and
    # refuses by name at the pinned gen-delivery.
    node-keyed-extras-refuse =
      !(forces (
        genDelivery.realize {
          inherit projected;
          terminals.nixos = reflect;
          extraModules = {
            alpha = [ extra ];
          };
        }
      ));
    # CONTROL, same instrument, same run — the addressed call evaluates, so the refusals above are the
    # addresses and not a fixture that throws on every call.
    addressed-extras-evaluate = forces realized.nixos;

    # ── LEXICAL: the shipped call site addresses the extras to nixos ──
    hub-addresses-extras-to-nixos = occurs "nixos = cfg\\.extraModules;";
    hub-passes-no-node-keyed-extras = !(occurs "extraModules = cfg\\.extraModules;");
    # CONTROL, same instrument, same run — a token that IS in the file, so the absence above is a
    # spelling that is gone and not a `readFile`/`split` that reads everything as empty.
    lexical-instrument-fires = occurs "genDelivery\\.realize";
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;
}
