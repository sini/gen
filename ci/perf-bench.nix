# Perf-regression workload corpus — the PERFORMANCE twin of the byte-parity oracles.
#
# Same provider-P trick as rehost-byte-parity.nix, scaled: one workload source, two stacks —
# PURE (gen-prelude → gen-types → gen-merge.evalModuleTree → re-hosted gen-schema/gen-aspects,
# published mains) vs REFERENCE (frozen original gen-schema/gen-aspects on pinned nixpkgs.lib
# evalModules). Each cell returns a sha256 digest of the JSON projection plus its length, so the
# perf matrix doubles as a byte-parity check at benchmark scale (~200× the oracle fixtures).
#
# This file only DEFINES workloads; timing/counters/gates live in the `perf-bench` app
# (ci/flake.nix), which drives it through `nix-instantiate --eval` + NIX_SHOW_STATS per cell.
# Baselines + gate rationale: ci/README.md and the 2026-07-04 benchmark report
# (den-architecture/gen-specs/gen-merge/2026-07-04-module-system-benchmarks.md).
{
  srcs, # { gen-prelude, gen-types, gen-merge, gen-algebra, gen-schema, gen-aspects, gen-schema-orig, gen-aspects-orig, nixpkgs-lib } — store paths as strings
  stack, # "pure" | "ref"
  workload, # "startup" | "scalar" | "registry" | "lazyRegistry" | "schemaHosts" | "aspects"
  n,
}:
let
  prelude = import "${srcs.gen-prelude}/lib";
  genTypes = import "${srcs.gen-types}/lib" { inherit prelude; };
  genMerge = import "${srcs.gen-merge}/lib" {
    inherit prelude;
    types = genTypes;
  };
  genAlgebra = import "${srcs.gen-algebra}/lib";
  genSchemaNew = import "${srcs.gen-schema}/lib" {
    inherit prelude;
    merge = genMerge;
    algebra = genAlgebra;
  };
  genAspectsNew = import "${srcs.gen-aspects}/lib" {
    inherit prelude;
    merge = genMerge;
    schema = genSchemaNew;
  };

  lib = import "${srcs.nixpkgs-lib}/lib";
  genSchemaOld = import "${srcs.gen-schema-orig}/lib" {
    inherit lib;
    algebra = genAlgebra;
  };
  genAspectsOld = import "${srcs.gen-aspects-orig}/lib" {
    inherit lib;
    schema = genSchemaOld;
  };

  pureP = {
    inherit (genMerge)
      mkOption
      mkMerge
      mkDefault
      mkForce
      mkIf
      ;
    types = genMerge.types;
    eval = genMerge.evalModuleTree;
    schema = genSchemaNew;
    aspects = genAspectsNew;
  };
  refP = {
    inherit (lib)
      mkOption
      mkMerge
      mkDefault
      mkForce
      mkIf
      types
      ;
    eval = lib.evalModules;
    schema = genSchemaOld;
    aspects = genAspectsOld;
  };

  P = if stack == "pure" then pureP else refP;

  # ── helpers (builtins only — neither stack pays for these) ──
  idx = builtins.genList (i: i) n;
  toAttrs = f: builtins.listToAttrs (map f idx);
  toAttrsIf = pred: f: builtins.listToAttrs (map f (builtins.filter pred idx));
  even = i: builtins.bitAnd i 1 == 0;
  third = i: i - ((i / 3) * 3) == 0;

  # ── workloads : P -> projection ──────────────────────────────────────────

  # startup — fixed cost of one trivial option through the engine (report-only, no gates).
  startup =
    P:
    (P.eval {
      modules = [
        {
          options.x = P.mkOption {
            type = P.types.str;
            default = "y";
          };
        }
      ];
    }).config.x;

  # scalar — n flat typed options; layer 1 = mkDefault (all), layer 2 = mkIf (every 3rd discharges
  # away). Exercises decl merge, property discharge, priority, leaf verify. The wide-sibling shape
  # that catches super-linear key handling (the 2026-07-04 O(k²) unique regression).
  scalar =
    P:
    let
      eval = P.eval {
        modules = [
          {
            options.s = toAttrs (i: {
              name = "o${toString i}";
              value = P.mkOption {
                type = P.types.str;
                default = "d${toString i}";
              };
            });
          }
          {
            config.s = toAttrs (i: {
              name = "o${toString i}";
              value = P.mkDefault "a${toString i}";
            });
          }
          {
            config.s = toAttrs (i: {
              name = "o${toString i}";
              value = P.mkIf (!third i) "b${toString i}";
            });
          }
        ];
      };
    in
    eval.config.s;

  # registry — attrsOf(submodule), n instances × 4 typed fields, mkForce-override on half.
  # The den registry shape: one nested fixpoint per instance.
  mkRegistry =
    attrsOfName: P:
    let
      sub = {
        options = {
          addr = P.mkOption { type = P.types.str; };
          role = P.mkOption {
            type = P.types.str;
            default = "app";
          };
          port = P.mkOption {
            type = P.types.int;
            default = 80;
          };
          tags = P.mkOption {
            type = P.types.listOf P.types.str;
            default = [ ];
          };
        };
      };
      eval = P.eval {
        modules = [
          {
            options.hosts = P.mkOption {
              type = P.types.${attrsOfName} (P.types.submodule sub);
              default = { };
            };
          }
          {
            config.hosts = toAttrs (i: {
              name = "h${toString i}";
              value = {
                addr = "10.0.${toString (i / 256)}.${toString (i - ((i / 256) * 256))}";
                tags = [
                  "t${toString i}"
                  "zone-${toString (i / 100)}"
                ];
              };
            });
          }
          {
            config.hosts = toAttrsIf even (i: {
              name = "h${toString i}";
              value = {
                role = P.mkForce "db";
                port = 8000 + i;
              };
            });
          }
        ];
      };
    in
    eval.config.hosts;

  registry = mkRegistry "attrsOf";
  lazyRegistry = mkRegistry "lazyAttrsOf";

  # schemaHosts — the parity oracle's schemaFleet at scale: kind + n instances incl id_hash.
  schemaHosts =
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
            config.hosts = toAttrs (i: {
              name = "host${toString i}";
              value = {
                addr = "10.1.${toString (i / 256)}.${toString (i - ((i / 256) * 256))}";
                role = if even i then "web" else "db";
              }
              // (if third i then { system = "aarch64-linux"; } else { });
            });
          }
        ];
      };
    in
    builtins.mapAttrs (_: h: {
      inherit (h)
        addr
        role
        system
        id_hash
        ;
    }) eval.config.hosts;

  # aspects — n aspects with class content, every 4th with a nested child; flatten.
  aspects =
    P:
    let
      schema = P.aspects.mkAspectSchema {
        classes = {
          nixos = { };
          home = { };
        };
      };
      fourth = i: builtins.bitAnd i 3 == 0;
      eval = P.eval {
        modules = [
          { options.schema = schema.schemaOption; }
          (schema.mkAspectModule { })
          {
            config.aspects = toAttrs (i: {
              name = "asp${toString i}";
              value = {
                description = "aspect ${toString i}";
                nixos = {
                  services."svc${toString i}".enable = true;
                };
              }
              // (if fourth i then { child.description = "child of ${toString i}"; } else { });
            });
          }
        ];
      };
      flat = P.aspects.flatten eval.config.aspects;
    in
    builtins.mapAttrs (_: a: {
      inherit (a) name;
      description = a.description or null;
      key = a.key or null;
    }) flat;

  workloads = {
    inherit
      startup
      scalar
      registry
      lazyRegistry
      schemaHosts
      aspects
      ;
  };

  projection = workloads.${workload} P;
  json = builtins.toJSON projection;
in
{
  digest = builtins.hashString "sha256" json;
  count = builtins.stringLength json;
}
