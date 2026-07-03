# C4 — whole-stack re-host byte-parity oracle (the integration proof).
#
# Asserts the PURE stack (gen-prelude + gen-types + gen-merge/evalModuleTree + re-hosted gen-schema
# registry + re-hosted gen-aspects grammar) is BYTE-IDENTICAL to the nixpkgs stack (lib.evalModules +
# original gen-schema + original gen-aspects) over a corpus of whole-stack fixtures — schema entities
# and aspects TOGETHER, the realistic den shape. Each fixture is parameterized by a provider `P` so
# both stacks run the SAME source; the resolved projection (instance data incl id_hash + aspect
# flatten incl key + guard wrap) is compared. Mutation-teeth prove the oracle discriminates.
#
# nixpkgs is REFERENCE-side only. This is validation — it modifies nothing (den/nix-config untouched).
#
# Scope note: gen's flake DEMOS (gen-aspects/examples/demo, gen-schema/examples/demo) are flake-parts
# apps (import-tree + flake-parts.lib.mkFlake + lib.types.lines) — they exercise the nixpkgs TERMINAL
# plane, not the pure COMPOSITION plane, so they are not runnable through evalModuleTree. This oracle
# therefore validates the composition plane byte-identically using the demos' SHAPES (the gen-schema
# demo `host` kind; aspect trees with class content/includes/guards) + a read-only den-aspect sample.
#
# ── REPRODUCIBLE PINNING (permanent gen-ci regression) ──
# This oracle is a FUNCTION over flake-input sources so `nix flake check ./ci` can run it on every
# check. Wiring (see ci/flake.nix):
#   • PURE side (the guarded thing) tracks the PUBLISHED re-host mains — gen-schema / gen-aspects /
#     gen-merge / gen-prelude / gen-types / gen-algebra. A future change that breaks byte-parity
#     (incl the id_hash SHA) fails this check.
#   • REFERENCE side is FROZEN as the golden nixpkgs stack — the ORIGINAL nixpkgs-signature gen-schema
#     (`{ lib, algebra }`) + gen-aspects (`{ lib, schema }`), pinned to their pre-re-host revs, driven
#     through a PINNED `github:nix-community/nixpkgs.lib` (NOT an impure `getFlake "nixpkgs"`).
{
  gen-prelude,
  gen-types,
  gen-merge,
  gen-algebra,
  gen-schema, # PURE re-host (published main)
  gen-aspects, # PURE re-host (published main)
  gen-schema-orig, # ORIGINAL nixpkgs-signature { lib, algebra } (pre-re-host pin)
  gen-aspects-orig, # ORIGINAL nixpkgs-signature { lib, schema } (pre-re-host pin)
  lib, # pinned nixpkgs.lib
}:
let
  # ── pure re-hosted stack (published mains) ──
  prelude = import "${gen-prelude}/lib";
  genTypes = import "${gen-types}/lib" { inherit prelude; };
  genMerge = import "${gen-merge}/lib" {
    inherit prelude;
    types = genTypes;
  };
  genAlgebra = import "${gen-algebra}/lib";
  genSchemaNew = import "${gen-schema}/lib" {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
  };
  genAspectsNew = import "${gen-aspects}/lib" {
    inherit prelude;
    merge = genMerge;
    schema = genSchemaNew;
  };

  # ── reference nixpkgs stack (frozen originals + pinned nixpkgs.lib) ──
  genSchemaOld = import "${gen-schema-orig}/lib" {
    inherit lib;
    algebra = genAlgebra;
  };
  genAspectsOld = import "${gen-aspects-orig}/lib" {
    inherit lib;
    schema = genSchemaOld;
  };

  pureP = {
    inherit (genMerge) mkOption mkMerge mkDefault;
    types = genMerge.types;
    eval = genMerge.evalModuleTree;
    aspects = genAspectsNew;
    schema = genSchemaNew;
  };
  refP = {
    inherit (lib)
      mkOption
      mkMerge
      mkDefault
      types
      ;
    eval = lib.evalModules;
    aspects = genAspectsOld;
    schema = genSchemaOld;
  };

  # ────────────────────────────────────────────────────────────────────────
  # CORPUS — whole-stack fixtures : P -> comparable projection (the data spine)
  # ────────────────────────────────────────────────────────────────────────

  # (1) SCHEMA — the gen-schema demo `host` kind shape + instances + id_hash + a mkDefault.
  schemaFleet =
    P:
    let
      eval = P.eval {
        modules = [
          {
            options.schema = P.schema.mkSchemaOption { };
            config.schema.host = {
              options.addr = P.mkOption { type = P.types.str; };
              options.role = P.mkOption { type = P.types.str; };
              options.system = P.mkOption {
                type = P.types.str;
                default = "x86_64-linux";
              };
            };
          }
          {
            options.hosts = P.schema.mkInstanceRegistry eval.config.schema.host { };
            config.hosts.web = {
              addr = "10.0.0.1";
              role = "web";
            };
            config.hosts.db = {
              addr = "10.0.0.2";
              role = "db";
              system = "aarch64-linux";
            };
          }
        ];
      };
    in
    lib.mapAttrs (_: h: {
      inherit (h)
        addr
        role
        system
        id_hash
        ;
    }) eval.config.hosts;

  # (2) ASPECTS — a tree with class content (deferred), includes, a raw guard fn, and a nested aspect.
  aspectTree =
    P:
    let
      schema = P.aspects.mkAspectSchema {
        classes = {
          nixos = { };
          home = { };
        };
      };
      eval = P.eval {
        modules = [
          { options.schema = schema.schemaOption; }
          (schema.mkAspectModule { })
          {
            config.aspects.web = {
              description = "Web";
              nixos = {
                services.nginx.enable = true;
              };
              nested = {
                description = "child";
              };
            };
            config.aspects.db.includes = [ ({ host, ... }: { fromHost = host.name; }) ];
          }
        ];
      };
      flat = P.aspects.flatten eval.config.aspects;
      guard = builtins.head eval.config.aspects.db.includes;
    in
    {
      flat = lib.mapAttrs (_: a: {
        inherit (a) name;
        description = a.description or null;
        key = a.key or null;
      }) flat;
      guard = {
        wrapped = guard.__isWrappedFn or false;
        args = guard.__functionArgs or null;
        applied =
          (guard {
            host = {
              name = "H";
            };
          }).fromHost or "?";
      };
      # class content materialized through a nixpkgs terminal (functions can't value-compare) —
      # both stacks hand the SAME deferredModule to one lib.evalModules; compare the config.
      nixosConfig =
        (lib.evalModules {
          modules = [
            eval.config.aspects.web.nixos
            { options.services.nginx.enable = lib.mkOption { type = lib.types.bool; }; }
          ];
        }).config.services.nginx.enable;
    };

  # (3) INTEGRATED — aspects + schema-declared options together (the den shape): mkAspectSchema with a
  # collection + a schema-kind option (priority) threaded into every aspect instance via mkAspectModule.
  integrated =
    P:
    let
      schema = P.aspects.mkAspectSchema {
        classes = {
          nixos = { };
        };
        collections = {
          tags = {
            default = [ ];
          };
        };
      };
      eval = P.eval {
        modules = [
          { options.schema = schema.schemaOption; }
          # schema-declared option on the aspect kind: `priority`
          {
            config.schema.aspect.options.priority = P.mkOption {
              type = P.types.int;
              default = 50;
            };
          }
          (schema.mkAspectModule { })
          {
            config.aspects.svc = {
              description = "Service";
              priority = 10;
              nixos = {
                x = true;
              };
            };
            config.aspects.other.description = "Other"; # uses the default priority
          }
        ];
      };
    in
    {
      svc-priority = eval.config.aspects.svc.priority;
      other-priority = eval.config.aspects.other.priority;
      keys = builtins.sort (a: b: a < b) (builtins.attrNames (P.aspects.flatten eval.config.aspects));
    };

  fixtures = {
    inherit schemaFleet aspectTree integrated;
  };

  # run each fixture through both stacks; deep-compare the projection
  cmp =
    fx:
    let
      p = builtins.tryEval (builtins.deepSeq (fx pureP) (fx pureP));
      r = builtins.tryEval (builtins.deepSeq (fx refP) (fx refP));
    in
    {
      identical = p.success && r.success && p.value == r.value;
      pureOk = p.success;
      refOk = r.success;
    };

  results = lib.mapAttrs (_: cmp) fixtures;

  # ── mutation-teeth: a changed value must diverge from the reference (oracle has content) ──
  teeth =
    let
      # perturb schemaFleet: a different addr changes the id_hash
      mutated =
        let
          eval = genMerge.evalModuleTree {
            modules = [
              {
                options.schema = genSchemaNew.mkSchemaOption { };
                config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
              }
              {
                options.hosts = genSchemaNew.mkInstanceRegistry eval.config.schema.host { };
                config.hosts.web.addr = "10.9.9.9";
              }
            ];
          };
        in
        eval.config.hosts.web.id_hash;
      base = (schemaFleet pureP).web.id_hash;
    in
    mutated != base;

  # ── read-only den-aspect realism sample: a real aspect tree through BOTH grammars ──
  # den aspects couple `den`/`lib`; we lift only the DECLARATIVE aspect DATA (an attrset tree, the
  # shape resolveEntity feeds the grammar) and drive it through each grammar's flatten.
  denRealism =
    let
      # a representative den-shaped aspect tree (mirrors modules/aspects/*.nix: class-keyed content,
      # includes, nested) — data only, no den/lib coupling.
      denAspects = {
        base = {
          description = "base";
          nixos = {
            boot.tmp.cleanOnBoot = true;
          };
        };
        webserver = {
          includes = [ "base" ];
          nixos = {
            services.nginx.enable = true;
          };
          tuning = {
            description = "tuning";
          };
        };
      };
      drive =
        P:
        let
          schema = P.aspects.mkAspectSchema {
            classes = {
              nixos = { };
            };
          };
          eval = P.eval {
            modules = [
              { options.schema = schema.schemaOption; }
              (schema.mkAspectModule { })
              { config.aspects = denAspects; }
            ];
          };
        in
        builtins.sort (a: b: a < b) (builtins.attrNames (P.aspects.flatten eval.config.aspects));
    in
    {
      pure = drive pureP;
      ref = drive refP;
      identical = drive pureP == drive refP;
    };
in
{
  # per-fixture byte-parity (pure stack == nixpkgs stack)
  parity = lib.mapAttrs (_: r: r.identical) results;
  all-identical = builtins.all (r: r.identical) (builtins.attrValues results);
  # both stacks actually evaluated (not vacuously equal via shared throw)
  both-evaluated = builtins.all (r: r.pureOk && r.refOk) (builtins.attrValues results);
  # teeth
  teeth-mutation-diverges = teeth;
  # den realism sample
  den-realism = denRealism.identical;
  # dumps for eyeballing
  sample = {
    schema = (schemaFleet pureP).web;
    aspect-flat = (aspectTree pureP).flat;
    integrated = integrated pureP;
    den-keys = denRealism.pure;
  };
}
