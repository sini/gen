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
# loading itself (both marked in the `let`).
#
# AND AT THE PROJECTION RE-POINT (den-hoag-t3q9). The aspects/hosts projection this module carried
# VERBATIM from the dissolving compose is gone: it classified a delivery class by SHAPE, which
# ADR-0028's Rider forbids, and shape cannot see a key's declared category at all. The projection is
# now gen-delivery's own `project`, which reads the DECLARATION — so this module takes one, the new
# `gen.aspectCnf` option, and refuses by name when it is absent rather than degrading to shape. Two
# sentences of the carried header below are stale by that change and are left as source provenance
# like the two named further down: SYSTEMS' "from compose's `hosts` projection" (:75) and "from ONE
# `compose`" (:67) — the SYSTEMS half now takes a second input, the declaration.
#
# AND AT THE UNIT-5 RE-POINT, WHICH RETIRED THE LAST gen-flake READS. This module now consumes NO
# gen-flake surface:
#   * the `gen.inject` DEFAULT is the plain value `{ genValues = composedCore.values; }` — the
#     successor's real interface. gen-bind's `injectAdapter` (crossing-adapter-set.nix) is the
#     crossing-side successor of record for module-system targets; its header rules the module
#     wrapper vestigial, and this module IS the arg-environment writer (`_module.args` below), so
#     wrapping through a module here would re-introduce the wrapper the successor retired;
#   * `realized` reads gen-delivery's `realize` (the layered fold; roster key `delivery`) over
#     gen-delivery's own `project` result;
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
  # SYSTEMS half consumes are re-attached below, by gen-delivery's `project`.
  composedCore = compose {
    modules = treeModules ++ cfg.modules;
    specialArgs = genLibs // cfg.specialArgs;
  };

  # ── THE PROJECTION — gen-delivery's `project`, no longer a carried copy (den-hoag-t3q9) ─────
  # This module used to carry gen-flake compose.nix's `classFieldsOf`/`projectHosts` VERBATIM, and
  # that carried predicate classified a key of a flat-registry aspect entry by SHAPE: an attrset
  # carrying an `imports` list. ADR-0028's Rider forbids exactly that — a delivery class realizes
  # only on DECLARED content, never on structural shape — and the predicate failed it on two
  # measured arms. It read clean on the contentless-class arm only by COINCIDENCE (gen-aspects
  # renders a declared-but-unset class as `null`, a representation choice in another library), and
  # on the WRONG-CATEGORY arm it was simply wrong: a key declared `category = "channel"` rides its
  # value verbatim, so a channel carrying a module — the cross-framework exchange payload the
  # category exists for — was classified as a delivery class and `realize` called its terminal. A
  # facet declared with a permissive option type does the same.
  #
  # No shape test can fix that, because the two are the SAME SHAPE and differ only in what was
  # DECLARED. So the projection is gen-delivery's `project` (`deliveryClassesOf`: declared
  # `category = "class"` AND content present, shape never consulted) rather than a second predicate
  # here that can drift from it. `bindings.node` is the resolved instance and `selectHosts` keeps
  # gen-delivery's default (`values.hosts or { }`) — the shape this module always shipped.
  #
  # THE DECLARATION IS AN INPUT, NOT A DERIVATION, and that is measured rather than assumed: the
  # aspect `keySemantics` reaches the compose result at `values.schema.<kind>.keySemantics` ONLY
  # when the consumer's tree DEFINES a schema kind entry. A tree that merely declares
  # `options.schema`, or neither, yields a byte-identical aspect registry with the declaration
  # nowhere in it. A category source present for some consumers and absent for others is the silent
  # degradation the Rider forbids, so it is the `gen.aspectCnf` option and its absence is
  # gen-delivery's `requireCnf` refusal BY NAME — never a fallback to shape.
  #
  # One shape delta, stated: `gen.composed`'s `override` handle returns the SUCCESSOR projection (no
  # aspects/hosts re-attach on a re-compose); this module reads only the base compose.
  projected = genDelivery.project {
    values = composedCore.values;
    cnf = cfg.aspectCnf;
  };

  composed = composedCore // {
    inherit (projected) aspects;
    hosts = projected.nodes;
  };

  # ── THE TERMINAL BRIDGE (INTERIM — dies with this module at the ADR-0027 replacement) ─────
  # gen-delivery's fold calls a terminal FUNCTION; the successor constructors (gen-bind's crossing
  # adapter set) return a Terminal RECORD `{ adapter, locateConfig }` driven by the crossing's
  # `close`. The crossing performs this walk for crossing consumers; the hub performs it for the
  # degenerate one-member case, in `close`'s own order (bindFormals, then wrapUnit). `name` is
  # absorbed unused (as the retired terminal absorbed it); `passthrough` is not forwarded because
  # gen-delivery's projection never emits one (a future projection that does forwards it here — one
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
  # over the `project` result above. Reads only `projected`, the terminals above, and per-host
  # extras — never the injected/built config below, so no cycle. Shared by the `gen.realized` handle
  # and `flake.nixosConfigurations`. The hub passes no `bindings`/`refinements`/`layerOrder`: the
  # interim module grows no contract, and a consumer wanting the layered surface uses gen-delivery
  # directly.
  realized = genDelivery.realize {
    inherit projected terminals;
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

    aspectCnf = mkOption {
      type = types.nullOr types.raw;
      default = null;
      description = ''
        THE DECLARATION INPUT for the delivery-class projection: the consumer's OWN
        `mkAspectSchema` argument (`{ keySemantics = { <key>.category = "class" | "channel" |
        "facet"; }; … }`), handed to gen-delivery's `project`. ADR-0028's Rider — a delivery class
        realizes only on DECLARED content, never on structural shape — so the projection reads a
        key's declared category, and a channel or facet whose value happens to look like a
        deferredModule is NOT realized as a class.

        `null` is the ABSENT state, not a default. With no category source the projection has
        nothing left to classify by but the shape test it replaces, so it REFUSES BY NAME
        (gen-delivery's `requireCnf`) rather than degrading silently. Set it to the same value the
        tree's `mkAspectSchema` call takes — factor that argument into a file both sides import,
        since the declaration cannot be read back out of the compose result: `keySemantics` only
        reaches `values.schema.<kind>` when the tree also DEFINES a schema kind entry.
      '';
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
        the schema sub-tree, whose `values.schema.<kind>.options.*.type` are inert gen TYPE objects
        carrying `check`/`merge` FUNCTIONS, so the payload-side *provably-plain-data* predicate
        fails here. This site takes ADR-0023's declared interim (b), not the by-construction target:
        the payload lands in `_module.args`, which nixpkgs does NOT type-walk today, so the failure
        this design avoids — a gen type embedded in an OPTIONS tree via
        `substSubModules`/`getSubOptions` — does not occur for a plain `_module.args` value, but that
        is a DECLARED opt-out with its price recorded, not a by-construction guarantee, and it lifts
        when the by-construction target (`den-hoag-zgps`) lands. `renderDocs` legitimately reads
        `values.schema.<kind>.options.*.type.name` (a string). A consumer that instead uses
        `values.schema.<kind>` AS AN OPTION `type` is doing the explicitly out-of-scope thing
        (non-goal §11) and owns that hazard.
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
        projection entry carries one — gen-delivery's projection never emits it).
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
      defaultText = lib.literalExpression "genDelivery.realize { projected = <genDelivery.project { values; cnf = config.gen.aspectCnf; }>; inherit terminals; extraModules = config.gen.extraModules; }";
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
