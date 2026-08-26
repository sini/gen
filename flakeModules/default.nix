# ─────────────────────────────────────────────────────────────────────────────────────────────────
# INTERIM — entry-surface ergonomics, NOT the framework interface.
#
# This module does NOT satisfy ADR-0027. It is INTERIM ergonomics: it gives a consumer a single
# sanctioned input (the hub) and a ready-to-`imports` flake-parts module, and nothing more. The TRUE
# framework surface arrives with den v2 / quiver bound against the ADR-0027 interface; when it does,
# this module is the thing that gets replaced, not the thing that gets extended. Do not build a
# framework contract on top of what is written here.
#
# Rehomed from `gen-flake`'s repository-root `flakeModule.nix` under ADR-0031 F1, which sanctions the
# move on the ground that the hub is the single input a consumer takes. The module body below is
# carried CONTENT-IDENTICAL from that file — same options, same config, same comments. The only
# additions are this header and the roster bindings in the `let` (marked there), which replace the
# partial application the source got from gen-flake's own `flake.nix`.
#
# SINCE AMENDED AT THE SUCCESSOR-COMPOSE RE-POINT (ADR-0031 F2's "compose S2 core → S2" row):
# `compose` no longer reads off gen-flake — the successor landed at this hub (lib/compose.nix,
# exposed as `gen.lib.compose`), and this module now performs the constructor merge and the tree
# loading itself and carries the aspects/hosts projection verbatim from the dissolving compose
# (both marked in the `let`).
#
# AND AT THE UNIT-5 RE-POINT, WHICH RETIRED THE LAST gen-flake READS. This module now consumes NO
# gen-flake surface:
#   * the `gen.inject` DEFAULT is the plain value `{ genValues = composedCore.values; }` — the
#     successor's real interface. gen-bind's `injectAdapter` (crossing-adapter-set.nix) is the
#     crossing-side successor of record for module-system targets; its header rules the module
#     wrapper vestigial, and this module IS the arg-environment writer (`_module.args` below), so
#     wrapping through a module here would re-introduce the wrapper the successor retired;
#   * `realized` reads gen-delivery's `realize` (the layered fold; roster key `delivery`) over the
#     carried projection, handed as `projected = { nodes = …; }`;
#   * the default `nixos` terminal is gen-bind's `mkSystemTerminal` (crossing adapter set), bridged
#     to the fold's terminal contract by the hub-local `terminalOf` in the `let` — the owed
#     consumer-side reconstruction of the retired `nixosSystem` sugar (corpus G1).
# The body is otherwise the F1 carry.
#
# Its two MEASURED defects travel with it UNFIXED and are beaded at den-hoag-es9g. They are deliberate
# carry-over, never accepted behavior:
#   1. the class-name hardcode — `flake.nixosConfigurations = realized.nixos or { }` names the `nixos`
#      class in the module itself, so no other class reaches a flake output without consumer wiring;
#   2. the witness-2 gap — the option set carries no evaluator-location slot, and `realize` is called
#      without one, so where a class is evaluated cannot be expressed.
# Fixing either here would be an undesigned change. They are fixed against a design, or not at all.
#
# ── on the carried header below ──────────────────────────────────────────────────────────────────
# Two of its sentences are true OF GEN-FLAKE'S REPOSITORY and are NOT descriptions of this hub. They
# are carried verbatim rather than edited, so read them as source provenance:
#   * "It is a FUNCTION of the constructed gen-flake lib … partially applied in flake.nix" — that
#     was gen-flake's own wiring. Here the module binds its dependencies from the hub roster at
#     consumer eval time (see the `let`), and since the unit-5 re-point none of them is gen-flake.
#   * the `ci/tests/purity.nix` exclusion — that is gen-flake's purity suite. This hub runs no purity
#     suite, so nothing here excludes anything; the sentence explains why the SOURCE file was exempt.
# ─────────────────────────────────────────────────────────────────────────────────────────────────

# flakeModule.nix — gen-flake's flake-parts ergonomics ("no manual threading").
#
# Exposed as `gen-flake.flakeModules.default`. A consumer writes, with NO manual
# compose/inject/realize threading:
#
#     imports = [ gen-flake.flakeModules.default ];
#     gen.tree = ./gen-modules;                       # a directory of gen definition modules
#     gen.extraModules.<host> = [ ./hardware.nix ];   # per-host platform/base modules
#     gen.terminals.<class> = <terminal>;             # extra class terminals (a `nixos` one defaults
#                                                     #   in from `gen.nixpkgs`); map others off
#                                                     #   `gen.realized.<class>`
#     gen.injectPerSystem = true;                     # ALSO inject the values into perSystem args
#
# and gets, from ONE `compose`:
#   * QUERY   — the resolved gen VALUES injected as consumer module args under `config.gen.inject`
#               names (default `genValues`) into the top-level flake module args, so any consumer
#               module reads `{ genValues, ... }: … genValues.hosts.<h>.addr …`. The same values are
#               ALSO injected into every `perSystem` arg IFF `gen.injectPerSystem` is set — opt-in, so
#               the default emits NO `perSystem` definition: the perSystem arg-scope stays clean (no
#               values a perSystem module never named), and the module stays robust against flake-parts
#               versions that force a `systems` declaration once any `perSystem` definition exists.
#   * SYSTEMS — `flake.nixosConfigurations = (realize { terminals; … }).nixos or { }`, the `nixos`
#               class realized per host from compose's `hosts` projection (each host's `nixos` class
#               deferredModules, with the resolved instance partial-applied as the `node` binding by
#               gen-bind's wrap core). A host with no `nixos` content is not built (class-major); a
#               registry with no `nixos` class at all yields the empty `or { }`.
#   * TERMINALS — `gen.terminals` is the class-keyed registry `realize` consumes; `gen.realized` is the
#               full class-major result (`{ <class>.<host> = artifact; }`), so a consumer wires
#               non-nixos classes into their own flake outputs off `gen.realized.<class>`.
#
# This file is the FLAKE-PARTS / TERMINAL side of gen-flake. Unlike the pure core
# (lib/compose.nix, lib/inject.nix, lib/realize.nix) it legitimately uses nixpkgs `lib`
# (mkOption/types — supplied by the consumer's flake-parts eval) and closes over the `terminals`
# nixpkgs boundary. So ci/tests/purity.nix EXCLUDES it, for the same reason it excludes
# lib/terminals.nix.
#
# It is a FUNCTION of the constructed gen-flake lib (compose / injectArgs / realize / terminals),
# partially applied in flake.nix so `flakeModules.default` is a ready-to-`imports` module.
{
  config,
  lib,
  inputs,
  ...
}:
let
  # THE REHOME BINDINGS (added here; adjusted at the successor-compose and unit-5 re-points — see
  # the header). The source was a function of the constructed gen-flake lib, applied by gen-flake's
  # own `flake.nix`. The hub exports module PATHS and evaluates no flake-parts of its own, so the
  # module binds its dependencies at CONSUMER eval time off the hub roster — the same shape as
  # `flakeModules/genLibs.nix`. Since the unit-5 re-point those dependencies are the successors:
  # gen-bind's crossing adapter set (`bind`) and gen-delivery's fold (`delivery`); no surface below
  # reads gen-flake.
  roster = inputs.gen.lib.mkGenLibs { inherit lib; };
  genBind = roster.bind;
  genDelivery = roster.delivery;

  inherit (lib) mkOption types;
  cfg = config.gen;

  # ── THE SUCCESSOR-COMPOSE RE-POINT ──────────────────────────────────────────────────────────
  # `compose` is the hub's own successor construct (`gen.lib.compose`, lib/compose.nix). It takes
  # `specialArgs` CALLER-TOTAL and has no tree formal, so the two acts gen-flake's compose
  # performed internally are performed HERE, as this framework surface's own wiring:
  #   * the CONSTRUCTOR MERGE — `genLibs // cfg.specialArgs`, the constructor set handed to every
  #     module of a hub-fronted gen tree (carried from gen-flake compose.nix's `genLibs` constant;
  #     the consumer's specialArgs merge LAST so a caller can override or extend the set);
  #   * TREE LOADING — the import-tree fork's bare path list (`(addPath dir).files`); gen-merge
  #     imports path leaves natively. The fork's pin lives at the hub root flake.nix.
  compose = inputs.gen.lib.compose;
  importTree = inputs.gen.inputs.import-tree;

  genLibs = {
    genMerge = roster.merge;
    genSchema = roster.schema;
    genAspects = roster.aspects;
    genTypes = roster.types;
    genPrelude = roster.prelude;
  };

  treeModules = if cfg.tree == null then [ ] else (importTree.addPath cfg.tree).files;

  # The ONE compose for this flake — driven by the consumer's `gen.tree`/`gen.modules`. Pure
  # (gen-merge's byte-mode evalModuleTree); reads only `tree`/`modules`/`specialArgs`, never any of
  # the injected/built config below, so it introduces no fixpoint cycle. The successor result
  # carries `values`/`provenance`/`override`; the `aspects`/`hosts` projections this module's
  # SYSTEMS half consumes are re-attached below (the carried projection).
  composedCore = compose {
    modules = treeModules ++ cfg.modules;
    specialArgs = genLibs // cfg.specialArgs;
  };

  # ── THE CARRIED PROJECTION (INTERIM CARRY from gen-flake lib/compose.nix; code-identical save
  # ONE amendment: the binding formal renamed `host` → `node` at the unit-5 re-point — substrate
  # vocabulary, R§6.3, matching gen-delivery's documented contract "`bindings.node` IS the resolved
  # instance") ─
  # The successor compose does not project `aspects`/`hosts`: the settlement assigns them to
  # gen-delivery, whose realization predicate reads the key-category DECLARATION (`cnf`) — a value
  # this module's option surface does not carry and a compose result cannot reach. So the SYSTEMS
  # half of this interim module keeps the projection it has always shipped, carried VERBATIM from
  # the dissolving compose so consumer behaviour is preserved, and it dies with this module at the
  # ADR-0027 replacement. The structural-predicate defect it carries is MEASURED and beaded
  # (den-hoag-jwm8 / den-hoag-t3q9 — the ADR-0028 Rider gap the carried comment below describes):
  # deliberate carry-over in the same standing as the two den-hoag-es9g defects above, never
  # accepted behaviour. The fix is gen-delivery's declared-category predicate, adopted when this
  # module's replacement takes a declaration input. One shape delta, stated: `gen.composed`'s
  # `override` handle returns the SUCCESSOR projection (no aspects/hosts re-attach on a
  # re-compose); this module reads only the base compose.
  #
  # The class fields of a flat-registry aspect entry: keys whose value is a deferredModule (an
  # attrset carrying an `imports` LIST). Structural — no hardcoded class-name list, so any class
  # registered via `mkAspectSchema { keySemantics.<c>.category = "class"; }` is discovered. A class
  # DECLARED but never given content reads `null` (gen-aspects represents absence rather than
  # fabricating an empty deferredModule), so `isAttrs` below excludes THAT case. Reading `? imports`
  # on an unforced deferredModule is cheap and does NOT force the class body.
  #
  # ★★ THE PROJECTION IS NOT CONTENT-DRIVEN. The filter discovers every declared class but not
  # ONLY classes: it never consults a key's DECLARED CATEGORY, so a NON-class key whose value
  # happens to carry an `imports` list is classified as a delivery class and `realize` calls its
  # terminal for it. Measured on both non-class categories against the locked gen-aspects, with
  # controls and a firing tripwire — gen-flake AGENTS.md's trap table carries the two rows and the
  # figures. The exclusion that DOES hold is the contentless-class one above, and it rests on
  # gen-aspects' representation choice rather than on this predicate.
  classFieldsOf =
    entry:
    builtins.filter (
      k:
      let
        v = entry.${k};
      in
      builtins.isAttrs v && v ? imports && builtins.isList v.imports
    ) (builtins.attrNames entry);

  # `dedup` — order-preserving unique over a string list, builtins-only (listToAttrs collapses dups).
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

  # `projectHosts` — the host-keyed reshape of the FLAT aspect registry. For each host instance,
  # gather the deferredModules of each class across the aspects the host declares membership in
  # (`host.aspects`). `selectHosts` names WHICH resolved attrset holds the host instances; this
  # module applies the default projection (`values.hosts or { }`) — a nested registry layout is
  # the lower-level API's territory. Yields
  #   { <host> = { bindings = { node = <resolved instance>; }; classes = { <class> = [ <deferredModule> ]; }; }; }
  # PURE — no nixpkgs; the deferredModules stay unforced (opaque) until the terminal imports them.
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

  # The flat aspect registry (keyed by aspect path). Absent an `aspects` surface, empty.
  aspects =
    if composedCore.values ? aspects then roster.aspects.flatten composedCore.values.aspects else { };

  composed = composedCore // {
    inherit aspects;
    hosts = projectHosts (values: values.hosts or { }) composedCore.values aspects;
  };

  # ── THE TERMINAL BRIDGE (INTERIM — dies with this module at the ADR-0027 replacement) ─────
  # gen-delivery's fold calls a terminal FUNCTION; the successor constructors (gen-bind's crossing
  # adapter set) return a Terminal RECORD `{ adapter, locateConfig }` driven by the crossing's
  # `close`. The crossing performs this walk for crossing consumers; the hub performs it for the
  # degenerate one-member case, in `close`'s own order (bindFormals, then wrapUnit). `name` is
  # absorbed unused (as the retired terminal absorbed it); `passthrough` is not forwarded because
  # the carried projection never emits one (a future projection that does forwards it here — one
  # line, and gen-bind's spine-read shadow refusal then governs). `locateConfig` rides the record
  # for the crossing's `close`, not for the fold — this bridge does not consume it.
  terminalOf =
    record: args:
    let
      a = record.adapter { inherit (args) extent extraModules; };
    in
    a.wrapUnit (a.bindFormals args.bindings args.modules) [ ];

  # The effective terminal registry the fold consumes: the consumer's `gen.terminals`, plus a default
  # `nixos` terminal wired to `gen.nixpkgs` UNLESS `gen.nixpkgs` is null or the consumer already
  # supplied their own `nixos` terminal (in which case theirs wins). A consumer replacing terminals
  # entirely (custom classes, `gen.nixpkgs = null`) gets exactly their registry — no default nixos.
  # The default is the owed consumer-side reconstruction of the retired `nixosSystem` sugar (corpus
  # G1): the substrate names no host builder, so the consumer's evaluator is threaded here.
  terminals =
    cfg.terminals
    // lib.optionalAttrs (cfg.nixpkgs != null && !(cfg.terminals ? nixos)) {
      nixos = terminalOf (
        genBind.crossing.mkSystemTerminal {
          evaluator = cfg.nixpkgs.lib.nixosSystem;
          locateConfig = a: a.config;
        }
      );
    };

  # The class-major realize result (`{ <class>.<host> = artifact; }`) — gen-delivery's layered fold
  # over the carried projection. Reads only `composed`, the terminals above, and per-host extras —
  # never the injected/built config below, so no cycle. Shared by the `gen.realized` handle and
  # `flake.nixosConfigurations`. The hub passes no `bindings`/`refinements`/`layerOrder`: the
  # interim module grows no contract, and a consumer wanting the layered surface uses gen-delivery
  # directly.
  realized = genDelivery.realize {
    projected = {
      nodes = composed.hosts;
    };
    inherit terminals;
    extraModules = cfg.extraModules;
  };
in
{
  options.gen = {
    tree = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        A directory of gen definition modules, composed once via gen-merge's `evalModuleTree`
        (loaded as a bare path list by the import-tree fork). `null` ⇒ no tree; use `modules`.
      '';
    };

    modules = mkOption {
      # `raw`, NOT `deferredModule`: these modules are fed to the PURE gen-merge engine, not to
      # nixpkgs. nixpkgs `deferredModule` coercion would wrap them in a nixpkgs-flavored module and
      # is a category error at the gen boundary; pass them through untouched.
      type = types.listOf types.raw;
      default = [ ];
      description = "Extra inline gen modules appended to the tree (fed to gen-merge, not nixpkgs).";
    };

    specialArgs = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra module args merged over the threaded gen libs during `compose`.";
    };

    inject = mkOption {
      type = types.attrsOf types.raw;
      # The default is the successor's REAL interface, inlined: gen-bind's `injectAdapter`
      # (crossing-adapter-set.nix, the crossing-side successor of record for module-system targets)
      # rules the retired `injectArgs` module wrapper vestigial — every live consumer read
      # `._module.args` straight back out — so the `AttrsOf Value` is the interface, and THIS
      # module is the arg-environment writer (`config._module.args = cfg.inject` below is the
      # `(Formals, Substrate)` placement one level up). Wrapping through a module here would
      # re-introduce the wrapper the successor retired.
      default = {
        genValues = composedCore.values;
      };
      defaultText = lib.literalExpression "{ genValues = <the resolved gen config values>; }";
      description = ''
        The resolved gen VALUES to inject as consumer module args, keyed by arg NAME. Defaults to
        `{ genValues = <the resolved config values>; }`; a consumer may rename the arg or add
        further derived values. The set is injected into the top-level flake module args, and — when
        `injectPerSystem` is set — every `perSystem` arg, so consumer modules read them as
        `{ genValues, ... }: …`.

        INVARIANT — do NOT project `schema` out of the injected values. `composed.values` includes
        the schema sub-tree, whose `values.schema.<kind>.options.*.type` are inert gen TYPE objects.
        This is invariant-SAFE here: the payload lands in `_module.args`, which nixpkgs does NOT
        type-walk. The failure this design avoids — nixpkgs walking a gen type embedded in an
        OPTIONS tree via `substSubModules`/`getSubOptions` — cannot occur for a plain `_module.args`
        value. `renderDocs` legitimately reads `values.schema.<kind>.options.*.type.name` (a
        string). A consumer that instead uses `values.schema.<kind>` AS AN OPTION `type` is doing
        the explicitly out-of-scope thing (non-goal §11) and owns that hazard.
      '';
    };

    injectPerSystem = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to ALSO inject the resolved values (`inject`) into every `perSystem` arg, not just the
        top-level flake args. Default `false`: the module emits NO `perSystem` definition, keeping the
        perSystem arg-scope clean (no values a perSystem module never named) and the module robust
        against flake-parts versions that force a `systems` declaration once any `perSystem` definition
        exists. Set `true` when a `perSystem` module needs to read `genValues`.
      '';
    };

    nixpkgs = mkOption {
      type = types.nullOr types.raw;
      default = inputs.nixpkgs or null;
      defaultText = lib.literalExpression "inputs.nixpkgs or null";
      description = ''
        The nixpkgs used to BUILD the per-host NixOS systems (the default `nixos` terminal). Defaults
        to the consumer's own `inputs.nixpkgs`, so systems pin to the consumer's nixpkgs, not
        gen-flake's. `null` (or a consumer-supplied `terminals.nixos`) suppresses the default `nixos`
        terminal.
      '';
    };

    terminals = mkOption {
      # `raw`: each value is a terminal FUNCTION (gen-delivery's realize contract), fed to the pure
      # fold — not a nixpkgs module. A default `nixos` terminal is merged in from `nixpkgs` below
      # unless overridden.
      type = types.attrsOf types.raw;
      default = { };
      description = ''
        The class-keyed terminal registry gen-delivery's `realize` consumes:
        `{ <class> = <terminal>; }`. Each terminal is a function of one call-record per node:
        `{ name, modules, bindings, extent, extraModules }` (plus `passthrough` iff the node's
        projection entry carries one — the carried projection here never emits it).
        `bindings.node` is the resolved instance; `extent` is this class's realized set itself (a
        lazy cross-node accessor whose spine is the class's node keys). A default `nixos` terminal
        (gen-bind's `mkSystemTerminal` over `config.gen.nixpkgs.lib.nixosSystem`, bridged to this
        contract) is added unless `gen.nixpkgs` is null or this set already carries a `nixos`
        terminal. Read the realized artifacts back off `gen.realized.<class>` to wire non-nixos
        classes into flake outputs.
      '';
    };

    extraModules = mkOption {
      # `deferredModule` here IS correct: these are nixpkgs NixOS modules handed to
      # `nixpkgs.lib.nixosSystem`.
      type = types.attrsOf (types.listOf types.deferredModule);
      default = { };
      description = ''
        Per-host extra NixOS modules appended to each built system, e.g.
        `{ <host> = [ ./hardware.nix { system.stateVersion = "24.05"; } ]; }`.
      '';
    };

    composed = mkOption {
      type = types.raw;
      readOnly = true;
      internal = true;
      default = composed;
      defaultText = lib.literalExpression "compose { inherit (config.gen) tree modules specialArgs; }";
      description = "The single `compose` result (`values` / `aspects` / `hosts`). Internal read handle.";
    };

    realized = mkOption {
      type = types.raw;
      readOnly = true;
      internal = true;
      default = realized;
      defaultText = lib.literalExpression "genDelivery.realize { projected = { nodes = <the carried hosts projection>; }; inherit terminals; extraModules = config.gen.extraModules; }";
      description = ''
        The full class-major realize result (`{ <class>.<host> = artifact; }`) over `gen.terminals`.
        `flake.nixosConfigurations` is `realized.nixos or { }`; a consumer maps any other class off
        `realized.<class>`. Internal read handle.
      '';
    };
  };

  config = {
    # QUERY — inject the resolved VALUES under the `inject` names into the top-level flake args
    # (always), and into every `perSystem` arg IFF opted in (default emits no `perSystem` definition,
    # keeping the perSystem arg-scope clean).
    _module.args = cfg.inject;
    perSystem = lib.mkIf cfg.injectPerSystem (_: {
      _module.args = cfg.inject;
    });

    # SYSTEMS — the `nixos` class of the realized registry. `or { }` because a consumer may replace
    # terminals entirely without a `nixos` class (e.g. `gen.nixpkgs = null` + custom terminals).
    flake.nixosConfigurations = realized.nixos or { };
  };
}
