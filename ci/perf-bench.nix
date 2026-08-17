# Perf-regression workload corpus — the PERFORMANCE twin of the byte-parity oracle.
#
# Same provider-P trick as rehost-den-parity.nix, scaled: one workload source, two stacks —
# PURE (gen-prelude → gen-types → gen-merge.evalModuleTree → re-hosted gen-schema/gen-aspects,
# published mains) vs REFERENCE (frozen original gen-schema on pinned nixpkgs.lib evalModules).
# Each cell returns a sha256 digest of the JSON projection plus its length, so the perf matrix
# doubles as a byte-parity check at benchmark scale (~200× the oracle fixtures).
#
# The `aspects` workload is PURE-ONLY and the exclusion is structural, not incidental: `refP` has no
# `aspects` member, so running it on the reference stack throws rather than silently comparing. The
# aspect grammar moves by design ruling, so no frozen reference can track it — a pure/ref digest gate
# over that surface asserts "the grammar has not been improved", which is not a performance property.
# Its pure cells, absolute counters and linearity gates are unaffected; see ci/README.md.
#
# This file only DEFINES workloads; timing/counters/gates live in the `perf-bench` app
# (ci/flake.nix), which drives it through `nix-instantiate --eval` + NIX_SHOW_STATS per cell.
# Baselines + gate rationale: ci/README.md, which carries both in full. The 2026-07-04 benchmark
# report that first recorded them is not part of this repository and is not needed to re-derive them.
#
# The `classShare` workload (gen-class tier 2, spec §2.5) is the ODD ONE OUT: its two "stacks" are
# `pure-full` / `pure-fixed` (both the PURE engine), NOT pure/ref. It IGNORES the shared provider `P`
# (which routes only "pure" ↔ pureP) and builds its engines from `srcs` directly — see the dispatch at
# the bottom. The perf-bench.sh classShare section drives it in a DEDICATED loop, not the pure/ref matrix.
{
  srcs, # { gen-prelude, gen-types, gen-merge, gen-algebra, gen-schema, gen-aspects, gen-schema-orig, gen-class, nixpkgs-lib } — store paths as strings
  stack, # "pure" | "ref"  (aspects: "pure" only; classShare: "pure-full" | "pure-fixed"; overrideWarm: "cold" | "warm")
  workload, # "startup" | "scalar" | "registry" | "lazyRegistry" | "schemaHosts" | "aspects" | "wideFreeform" | "deepSubmodule" | "classShare" | "overrideWarm"
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
  # gen-class wired for tier 2 (the injected gen-merge kernel enables `applyCoreFixed`). Only the
  # `classShare` workload touches this; every pure/ref cell ignores it.
  genClass = import "${srcs.gen-class}/lib" {
    inherit prelude;
    merge = genMerge;
  };

  lib = import "${srcs.nixpkgs-lib}/lib";
  genSchemaOld = import "${srcs.gen-schema-orig}/lib" {
    inherit lib;
    algebra = genAlgebra;
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
  # No `aspects` member: the aspect grammar has no frozen reference to compare against (header note),
  # so `aspects` is a pure-only workload and the reference stack cannot evaluate it by construction.
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
  # PURE-ONLY (header note): `refP` carries no `aspects`, so this workload runs on the pure stack
  # alone — its linearity gates and absolute counters, never a pure/ref digest or ratio.
  aspects =
    P:
    let
      schema = P.aspects.mkAspectSchema {
        keySemantics = {
          nixos.category = "class";
          home.category = "class";
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

  # wideFreeform — a WIDE freeform tree: one root module with a `freeformType` (lazyAttrsOf str) that
  # absorbs n UNKNOWN sibling keys, coexisting with a handful of declared options. Layered defs
  # (mkDefault all, mkForce on even, mkIf every 3rd discharged away) drive priority resolution THROUGH
  # the freeform absorption path — the twin of `scalar`'s wide DECLARED option set, but exercising the
  # unknown-key → root-freeform merge instead of typed option lookup. Declared options (`title`/`count`)
  # take the typed path; unknown k* keys route to the freeform.
  wideFreeform =
    P:
    let
      eval = P.eval {
        modules = [
          {
            freeformType = P.types.lazyAttrsOf P.types.str;
            options.title = P.mkOption {
              type = P.types.str;
              default = "t";
            };
            options.count = P.mkOption {
              type = P.types.int;
              default = 0;
            };
          }
          {
            config =
              (toAttrs (i: {
                name = "k${toString i}";
                value = P.mkDefault "d${toString i}";
              }))
              // {
                title = "wide";
                count = n;
              };
          }
          {
            config = toAttrsIf even (i: {
              name = "k${toString i}";
              value = P.mkForce "f${toString i}";
            });
          }
          {
            config = toAttrs (i: {
              name = "k${toString i}";
              value = P.mkIf (!third i) "b${toString i}";
            });
          }
        ];
      };
    in
    eval.config;

  # deepSubmodule — n replicated DEEP submodule chains, each a fixed `depth`-level nest of
  # `submodule`s ending in leaf options. Exercises per-level engine recursion (the module fixpoint
  # re-entered `depth` deep per instance) — the one axis no other workload touches: registry's
  # instances are FLAT (4 leaf options), this one's are `depth` submodules deep. `depth = 8` is the
  # fixed sane constant — deep enough that per-level fixpoint re-entry dominates an instance's cost
  # (a shallower nest would be swamped by fixed per-instance overhead), shallow enough to stay within
  # the default eval stack (no overflow on a plain `nix run`); `n` scales the chain COUNT horizontally
  # (an attrsOf(submodule) of `n` instances), so counters stay linear in n — a per-level blowup would
  # show as super-linear growth against the linearity gate.
  deepSubmodule =
    P:
    let
      depth = 8;
      # a depth-level nested submodule chain type: `next.next.…(depth)….{ leaf; tag }`.
      mkChain =
        d:
        if d == 0 then
          {
            options.leaf = P.mkOption { type = P.types.str; };
            options.tag = P.mkOption {
              type = P.types.str;
              default = "end";
            };
          }
        else
          {
            options.next = P.mkOption {
              type = P.types.submodule (mkChain (d - 1));
              default = { };
            };
          };
      # a value that fills a chain to `depth` (only the leaf differs per instance).
      mkVal = d: leaf: if d == 0 then { inherit leaf; } else { next = mkVal (d - 1) leaf; };
      eval = P.eval {
        modules = [
          {
            options.chains = P.mkOption {
              type = P.types.attrsOf (P.types.submodule (mkChain depth));
              default = { };
            };
          }
          {
            config.chains = toAttrs (i: {
              name = "c${toString i}";
              value = mkVal depth "leaf${toString i}";
            });
          }
        ];
      };
    in
    eval.config.chains;

  workloads = {
    inherit
      startup
      scalar
      registry
      lazyRegistry
      schemaHosts
      aspects
      wideFreeform
      deepSubmodule
      ;
  };

  # ── classShare — the gen-class tier-2 fixed-input spine gate (spec §2.5) ──────────────────
  # A homogeneous class of `members` nodes that all share one DESIGNED core: an n-instance typed
  # `attrsOf(submodule)` registry — the same spine-heavy shape as the `registry` workload, the whole
  # of which is the byte-identical shared projection. Each member adds only a cheap sibling axis.
  #
  #   pure-full   : evaluate every member's FULL module tree — each independently re-merges the
  #                 n-instance registry (the honest no-sharing baseline: `members × merge(n)`).
  #   pure-fixed  : build the core ONCE (a single real merge → `coreValues`), then reconstruct each
  #                 member via `applyCoreFixed`, whose sole-def core marker makes gen-merge SKIP the
  #                 discharge/fold/verify spine for the registry loc (`1 × merge(n) + members × axis`).
  #
  # Both stacks return the SAME list of projections byte-identically (the in-bench byte gate asserts
  # digest equality); the fixed/full counter ratio is the measured spine reduction (perf-bench.sh gates
  # it against the A1 band — 1.89×→2.48× fixed-input reference, spec §2.5). Sole-def / no-default /
  # sibling-axis all satisfy the T7 firing contract so the skip actually fires (deterministic per
  # gen-class ci/tests/apply-fixed.nix).
  classShare =
    let
      members = 6; # a fixed homogeneous class (mirrors the corpus 6-agent class); n scales the core
      memberIdx = builtins.genList (i: i) members;

      # the designed core: an n-instance typed registry (registry-workload shape, layered defs)
      sub = {
        options = {
          addr = genMerge.mkOption { type = genMerge.types.str; };
          role = genMerge.mkOption {
            type = genMerge.types.str;
            default = "app";
          };
          port = genMerge.mkOption {
            type = genMerge.types.int;
            default = 80;
          };
          tags = genMerge.mkOption {
            type = genMerge.types.listOf genMerge.types.str;
            default = [ ];
          };
        };
      };
      # NB: NO `default` on the `hosts` option — a default appends a second def and demotes the sole
      # core marker to fall-through (still byte-identical, but no spine skip). The config always defines it.
      hostsDecl = {
        options.hosts = genMerge.mkOption {
          type = genMerge.types.attrsOf (genMerge.types.submodule sub);
        };
      };
      hostsCfg1 = {
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
      };
      hostsCfg2 = {
        config.hosts = toAttrsIf even (i: {
          name = "h${toString i}";
          value = {
            role = genMerge.mkForce "db";
            port = 8000 + i;
          };
        });
      };
      coreRegistryModules = [
        hostsDecl
        hostsCfg1
        hostsCfg2
      ];

      # THE expensive merge, computed ONCE — the fully-realized registry the class shares. Only
      # pure-fixed forces this (via `core`); pure-full never references it (laziness ⇒ no double-pay).
      coreValues = (genMerge.evalModuleTree { modules = coreRegistryModules; }).config.hosts;
      core = genClass.mkCoreRecord {
        class = genClass.mkClass {
          key = "hostclass";
          members = map (i: "node-${toString i}") memberIdx;
        };
        projection = "hosts";
        # attrNames is already lexically sorted (Nix guarantee) ⇒ satisfies mkCoreRecord's
        # sorted-sharedKeys contract without a redundant O(n log n) re-sort.
        sharedKeys = builtins.attrNames coreValues;
        values = coreValues;
      };

      # per-member axis: a cheap sibling loc (a DIFFERENT option from the projection, per the firing
      # contract) — the only thing that differs across members, so the class is non-degenerate.
      nodeIdDecl = {
        options.nodeId = genMerge.mkOption { type = genMerge.types.str; };
      };
      axisModule = i: { config.nodeId = "node-${toString i}"; };

      memberFull =
        i:
        (genMerge.evalModuleTree {
          modules = coreRegistryModules ++ [
            nodeIdDecl
            (axisModule i)
          ];
        }).config;
      memberFixed =
        i:
        (genClass.applyCoreFixed {
          inherit core;
          modules = [
            nodeIdDecl
            (axisModule i)
          ];
        }).config;

      projOf = if stack == "pure-fixed" then memberFixed else memberFull;
    in
    map (
      i:
      let
        c = projOf i;
      in
      {
        inherit (c) hosts nodeId;
      }
    ) memberIdx;

  # ── overrideWarm — gen-merge's warm re-eval (memoized override) gate (README §"Warm re-eval") ──
  # A shared registry-heavy base (den-hoag emit shape: a marked-pure data module + a clean force layer +
  # one dirty config-reading module) that a class of `overrides` cheap 1-module edits is applied over —
  # the adios `mkOverride` reverse-cone scenario the warm path implements, sound under gen-merge's config
  # fixpoint. Each edit appends a single sibling-axis def (`nodeId`), disjoint from the registry loc.
  #
  #   cold : evaluate every override's FULL module tree from scratch — each independently re-merges the
  #          shared registry (the honest no-reuse baseline: `overrides × merge(n)`).
  #   warm : evaluate the base ONCE (`prev`, forced once and shared), then reconstruct each override via
  #          `evalModuleTree { warmFrom = prev; editedModules = [edit]; }`. The dirty footprint of a
  #          1-module `nodeId` edit excludes the registry loc, so `hosts` splices from prev byte-for-byte
  #          (a typed registry is an isOptLeaf ⇒ whole-leaf splice) while only the edited `nodeId` and the
  #          dirty `summary` re-merge (`1 × merge(n) + overrides × edit`).
  #
  # Both stacks return the SAME list of projections byte-identically (the in-bench byte gate asserts
  # digest equality — the perf-scale twin of gen-merge's own warm-vs-cold byte oracle, and the standing
  # tooth against a lying `pureModule` marker: the data module is marked-pure, so a marker that read
  # `config` would stale-splice and diverge here). The warm/cold thunk ratio is the measured reuse; the
  # projection forces the whole registry in both stacks (cold `overrides` times, warm once via the splice).
  overrideWarm =
    let
      overrides = 6; # a fixed class of edits over one base (mirrors the corpus 6-agent class); n scales the registry
      ovIdx = builtins.genList (i: i) overrides;

      sub = {
        options = {
          addr = genMerge.mkOption { type = genMerge.types.str; };
          role = genMerge.mkOption {
            type = genMerge.types.str;
            default = "app";
          };
          port = genMerge.mkOption {
            type = genMerge.types.int;
            default = 80;
          };
          tags = genMerge.mkOption {
            type = genMerge.types.listOf genMerge.types.str;
            default = [ ];
          };
        };
      };

      # decl (clean attrset) + the cheap per-override sibling axis (nodeId) + a dirty aggregate (summary).
      decl = {
        _file = "decl";
        options.hosts = genMerge.mkOption { type = genMerge.types.attrsOf (genMerge.types.submodule sub); };
        options.nodeId = genMerge.mkOption {
          type = genMerge.types.str;
          default = "";
        };
        options.summary = genMerge.mkOption {
          type = genMerge.types.str;
          default = "";
        };
      };
      # THE data-heavy registry def, as a MARKED-PURE module taking a lib formal — the den-hoag emit-layer
      # shape ("den-hoag's emit layer can mark its data modules mechanically"). The formal resolves from
      # specialArgs and the body reads NO config, so the marker is honest ⇒ `hosts` classifies CLEAN and
      # is reusable across the class. (A lying marker would surface as a byte divergence at the gate.)
      dataModule = genMerge.pureModule (
        { genLib, ... }:
        {
          _file = "data";
          config.hosts = toAttrs (i: {
            name = "h${toString i}";
            value = {
              addr = "10.0.${toString (i / 256)}.${toString (i - ((i / 256) * 256))}";
              tags = [
                "t${toString i}"
                (genLib.zone i)
              ];
            };
          });
        }
      );
      # a clean force/override layer (attrset) — half the instances, mkForce role + a distinct port.
      dataForce = {
        _file = "data-force";
        config.hosts = toAttrsIf even (i: {
          name = "h${toString i}";
          value = {
            role = genMerge.mkForce "db";
            port = 8000 + i;
          };
        });
      };
      # one DIRTY config-reading module (bare function ⇒ dirty-by-default): it reads the registry and
      # re-merges in every re-eval, but reads the SPLICED (prev) registry under warm ⇒ forced once.
      dirtyReader =
        { config, ... }:
        {
          _file = "dirty";
          config.summary = "n=${toString (builtins.length (builtins.attrNames config.hosts))}";
        };

      # the lib the marked-pure data module consumes — a specialArg, NOT a fixpoint-derived _module.args.
      specialArgs = {
        genLib = {
          zone = i: "zone-${toString (i / 100)}";
        };
      };
      base = [
        decl
        dataModule
        dataForce
        dirtyReader
      ];
      editOf = k: {
        _file = "edit${toString k}";
        config.nodeId = "node-${toString k}";
      };

      # the base eval, computed ONCE — the memo the warm class reuses (`warmFrom`). Only the warm stack
      # references it; cold never does (laziness ⇒ no double-pay), exactly as classShare's `coreValues`.
      prev = genMerge.evalModuleTree {
        modules = base;
        inherit specialArgs;
      };

      coldMember =
        k:
        (genMerge.evalModuleTree {
          modules = base ++ [ (editOf k) ];
          inherit specialArgs;
        }).config;
      warmMember =
        k:
        (genMerge.evalModuleTree {
          modules = base ++ [ (editOf k) ];
          inherit specialArgs;
          warmFrom = prev;
          editedModules = [ (editOf k) ];
        }).config;

      projOf = if stack == "warm" then warmMember else coldMember;
    in
    map (
      k:
      let
        c = projOf k;
      in
      {
        inherit (c) hosts nodeId summary;
      }
    ) ovIdx;

  projection =
    if workload == "classShare" then
      classShare
    else if workload == "overrideWarm" then
      overrideWarm
    else
      workloads.${workload} P;
  json = builtins.toJSON projection;
in
{
  digest = builtins.hashString "sha256" json;
  count = builtins.stringLength json;
}
