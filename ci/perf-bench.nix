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
  srcs, # { gen-prelude, gen-types, gen-merge, gen-memo, gen-scope, gen-algebra, gen-identity, gen-schema, gen-aspects, gen-select, gen-schema-orig, gen-select-orig, gen-class, nixpkgs-lib } — store paths as strings
  stack, # "pure" | "ref"  (aspects: "pure" only; classShare: "pure-full" | "pure-fixed"; overrideWarm: "cold" | "warm"; kindMatch: "attrs-ref" | "kind" | "attrs-ref-sealed" | "kind-sealed" | "kind-plant"; entityMatch: "attrs-ref" | "entity" | "attrs-ref-sealed" | "entity-sealed" | "entity-plant")
  workload, # "startup" | "scalar" | "registry" | "lazyRegistry" | "schemaHosts" | "aspects" | "wideFreeform" | "deepSubmodule" | "classShare" | "overrideWarm" | "kindMatch" | "entityMatch" | "preflight"
  n,
}:
let
  # ── the combination's construction, DEMAND-DRIVEN ─────────────────────────────
  # Every member is applied with exactly the formals ITS OWN entry object declares, read live with
  # `builtins.functionArgs` at the path this file imports. A hand-written argument set per call site
  # is the shape ci/hub-substrate.nix's header names — "comparing SUPPLY against DEMAND read from
  # this file's own hand-written copy would be `x == x`" — and its failure mode is not cosmetic: a
  # member that gains or loses a formal is then reported by the EVALUATOR, which aborts on the first
  # offender a workload happens to force, and most workloads force none. `preflight` below reports
  # the whole residue in one pass instead.
  #
  # Two things here cannot be read off the source set and are therefore written down: which object a
  # call site imports, and which name the environment publishes it under.
  entryPath = {
    "gen-prelude" = "/lib";
    "gen-identity" = "/lib";
    "gen-types" = "/lib";
    "gen-merge" = "/lib";
    # gen-memo and gen-scope are applied at their repository ROOT, not at /lib — a DIFFERENT value
    # with different formals (at /lib both make `graph` REQUIRED; at the root every formal carries a
    # default). A census over /lib for these two reads a demand the call site never has to satisfy.
    "gen-memo" = "";
    "gen-scope" = "";
    "gen-algebra" = "/lib";
    "gen-schema" = "/lib";
    "gen-aspects" = "/lib";
    "gen-select" = "/lib"; # kindMatch: `sel.kind` keyed by minted kind identity (den-hoag-l0y)
    "gen-class" = "/lib"; # tier 2: the injected gen-merge kernel is what enables `applyCoreFixed`
    "gen-graph" = "/lib";
    "gen-schema-orig" = "/lib";
    "gen-select-orig" = "/lib"; # kindMatch's frozen denominator (ci/flake.nix)
    "nixpkgs-lib" = "/lib";
  };
  envName = {
    "gen-prelude" = "prelude";
    "gen-identity" = "identity";
    "gen-types" = "types";
    "gen-merge" = "merge";
    "gen-memo" = "memo";
    "gen-scope" = "scope";
    "gen-algebra" = "algebra";
    "gen-schema" = "schema";
    "gen-aspects" = "aspects";
    "gen-select" = "select";
    "gen-class" = "class";
    "gen-graph" = "graph";
    "gen-schema-orig" = "schemaOrig";
    "gen-select-orig" = "selectOrig";
    "nixpkgs-lib" = "lib";
  };
  memberKeys = builtins.attrNames entryPath;

  # The member's flake/resolver seam (ci/hub-substrate.nix:56-61) — never hub-suppliable, so it is
  # never an environment key and always lands "not nameable". Struck where DEFAULTED; left to refuse
  # where REQUIRED, because a member asking the hub for a resolver it does not have must not be
  # filtered out of the census, pass the pre-flight, and then abort at cell time.
  seamFormals = [
    "inputs"
    "src"
    "dep"
    "wire"
  ];

  entryOf = k: import "${srcs.${k}}${entryPath.${k}}";
  isApplied = k: builtins.isFunction (entryOf k); # ci/hub-substrate.nix:63 — functionArgs throws otherwise
  formalsOf = k: builtins.functionArgs (entryOf k); # { formal -> carries-a-default }

  # `env` is a FIXPOINT, not an ordered list: each member is applied with values drawn from `env`
  # itself and Nix's laziness resolves the construction order. The well-formedness condition is
  # therefore ACYCLICITY, not lexical position — `memo` and `scope` are nameable for `gen-merge`
  # even though the old hand-written form constructed them inside gen-merge's own argset. A genuine
  # cycle is an `infinite recursion` refusal, never a silent mis-supply. `env`'s SPINE is computable
  # without forcing any member (the names come from `envName`), which is what makes `intersectAttrs`
  # against it safe while `env` is being built.
  env = builtins.listToAttrs (
    map (k: {
      name = envName.${k};
      value =
        if isApplied k then
          # SUPPLIED ∪ PINNED in one builtin: every declared formal the environment can name, and
          # nothing else. A formal the environment cannot name is either UNSAT (required — refused
          # by the pre-flight) or a LEAK (defaulted — declared in the combination block, and it
          # resolves from the member's OWN lock rather than from the combination you asked for).
          entryOf k (builtins.intersectAttrs (formalsOf k) env)
        else
          entryOf k;
    }) memberKeys
  );

  inherit (env) prelude lib;
  genIdentity = env.identity;
  genTypes = env.types;
  genMerge = env.merge;
  genAlgebra = env.algebra;
  genSchemaNew = env.schema;
  genAspectsNew = env.aspects;
  genClass = env.class;
  genSelect = env.select;
  genSelectOrig = env.selectOrig;
  genSchemaOld = env.schemaOrig;

  # ── the pre-flight census (`--argstr workload preflight`) ─────────────────────
  # Forces NO member body: `builtins.functionArgs` evaluates the lambda and never applies it, so this
  # names every offending member in ONE pass where application aborts at one and, on most cells, at
  # none. `strike` is the arming knob — the identical predicate against the environment with a name
  # removed — so every run prints a seeded delta beside its live reading.
  envKeysOn = strike: builtins.filter (f: !(builtins.elem f strike)) (builtins.attrValues envName);
  nameableOn = strike: f: builtins.elem f (envKeysOn strike);
  isSeam = f: builtins.elem f seamFormals;
  namesWhere = p: k: builtins.filter (f: p (formalsOf k).${f}) (builtins.attrNames (formalsOf k));
  requiredOf = namesWhere (hasDefault: !hasDefault);
  defaultedOf = namesWhere (hasDefault: hasDefault);
  appliedKeys = builtins.filter isApplied memberKeys;

  censusOn =
    strike:
    map (k: {
      member = k;
      entry = if entryPath.${k} == "" then "ROOT" else "/lib";
      required = requiredOf k;
      defaulted = defaultedOf k;
      supplied = builtins.filter (nameableOn strike) ((requiredOf k) ++ (defaultedOf k));
      unsat = builtins.filter (f: !(nameableOn strike f)) (requiredOf k);
      leak = builtins.filter (f: !(nameableOn strike f) && !(isSeam f)) (defaultedOf k);
    }) appliedKeys;
  residueOn = strike: builtins.filter (r: r.unsat != [ ]) (censusOn strike);

  # The arming strike. `prelude` is the name the largest number of entries make REQUIRED, so it is
  # the sharpest single-name seed available; its delta is reported, never its absolute.
  armingStrike = "prelude";
  preflight = {
    rows = censusOn [ ];
    residue = residueOn [ ];
    leaks = builtins.filter (r: r.leak != [ ]) (censusOn [ ]);
    unappliedEntries = builtins.filter (k: !(isApplied k)) memberKeys;
    arming = {
      strike = armingStrike;
      fires = builtins.length (residueOn [ armingStrike ]);
      members = map (r: r.member) (residueOn [ armingStrike ]);
      of = builtins.length appliedKeys;
    };
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

  # schemaHosts — the parity oracle's schemaFleet at scale: kind + n instances. The `id_hash` is
  # minted and FORCED here but does not enter the digest — see the excluded axis at the projection.
  #
  # ── MANUAL SYMMETRIC TWO-PASS FREEZE (a PRECEDENT, not a specified mechanism) ──
  # The relocation spec §2.6 retires the crossing spelling
  # `mkInstanceRegistry <binding>.config.<path>.schema.<k>` — a read out of the fixpoint the same
  # pass is still constructing — onto `mkInstanceRegistry <frozen>.<k>` with
  # `<frozen> = evalSchema {…}`. That ordinary let-bind is the ONLY construction §2.6 prescribes,
  # and it is unavailable here: this cell runs on BOTH stacks, and `refP.schema` is the permanently
  # pinned `gen-schema-orig` (ci/flake.nix), a revision predating `evalSchema` entirely. So the kind
  # is frozen in its own prior pass instead, on plain `P.eval` + `mkSchemaOption` — the API both
  # engines carry — exactly as ci/rehost-den-parity.nix's `driveInstances`/`driveNested` do. Same
  # shape on both arms, so the parity digest stays an engine comparison and not a shape comparison.
  # The kind has no dependency on the registry it seeds, which is what makes the split sound.
  schemaHosts =
    P:
    let
      hostSchema = P.eval {
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
        ];
      };
      frozenHost = hostSchema.config.schema.host;
      eval = P.eval {
        modules = [
          {
            options.hosts = P.schema.mkInstanceRegistry frozenHost { };
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
    # ── THE EXCLUDED AXIS: `id_hash` IS FORCED BUT NOT DIGESTED (ADR-0016) ──
    # This cell's digest is compared against the PERMANENT frozen `gen-schema-orig` pin, which
    # ci/flake.nix documents as never swept forward. gen-schema `75d40c1` re-minted `id_hash` by
    # design ruling (ADR-0016) — the kind left the digest for a `"<kind>:"` tag and the preimage
    # became `toJSON` of the ⟨label,value⟩ pairs — and the reference side cannot learn it: it is
    # called on the nixpkgs `{ lib, algebra }` signature, and every revision carrying that signature
    # predates the encoding, so the frozen witness holds the OLD formula permanently. The identity
    # axis is therefore excluded from the digest exactly as ci/rehost-den-parity.nix excludes it
    # from the oracle's parity arms; identity's oracle is `teeth-mutation-pure` there plus
    # gen-schema's own identity suite, and no replacement identity arm belongs in a perf bench.
    #
    # The `seq` stays, because this is a PERFORMANCE cell before it is a parity one. Minting n
    # identities is real work on both stacks, and dropping it from the projection rather than from
    # the digest would stop the bench measuring it: at n=400 the pure cell falls 506992 → 294589
    # thunks and −40% alloc, turning a 0.71 counter ratio into 0.56 — an engine win no engine
    # earned, spliced into BENCHMARKS.md by the next `--update` run. Forcing it also keeps the
    # failure loud: an engine that stopped minting an `id_hash` at all throws on the missing
    # attribute here instead of passing a narrowed digest.
    builtins.mapAttrs (
      _: h:
      builtins.seq h.id_hash {
        inherit (h)
          addr
          role
          system
          ;
      }
    ) eval.config.hosts;

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

  # ── kindMatch — kind identity at scale (den-hoag-l0y; the owner's landing gate on ruling (a)) ──
  # Two kinds sharing ONE name (`host`), from two `evalSchema` calls whose declarations differ by a
  # non-key option, so gen-schema's `kindEq` calls them two kinds. n/2 instances in each registry;
  # one registry-adapter context over the union, whose per-id `kindFor` hands back each node's
  # SHARED kind value. Single-engine, classShare's pattern, over TWO fixtures:
  #
  #   migrated (bare stack name) : `addr` typed by gen-merge, so the kind's sealed map is EMPTY and a
  #                                matching node leaves the sealed-collision helper on its empty arm.
  #   sealed   (`-sealed` suffix) : `addr` typed by nixpkgs `lib.types.str`, a SEALED component (a
  #                                 value gen-schema cannot key), so a matching node reaches
  #                                 `sealedCollisionEq`'s non-empty arm: the unmigrated kinds den
  #                                 declares today.
  #
  #   attrs-ref  : `sel.attrs { addr = <A's value>; }` through the FROZEN gen-select (`gen-select-orig`,
  #                ci/flake.nix): the per-node matching machinery with no kind identity read, at a
  #                revision no relock moves. The DENOMINATOR. A live-gen-select denominator dilutes
  #                every cost both stacks pay in the shared matcher instead of reporting it.
  #   kind       : `sel.kind A` through the LIVE gen-select — the path under test. Its projection must
  #                equal attrs-ref's byte for byte (the A instances, n/2 of them): a name key
  #                conflating A with B returns all n.
  #   kind-plant : `kind` with `kindFor` RE-DERIVING the node's kind per call, so every node forces a
  #                fresh digest — the per-node recompute the owner's cost answer was conditional on
  #                not happening. Byte-identical to `kind` by construction (the re-derived kind mints
  #                the same identity), so ONLY the counter gate can see it; perf-bench.sh runs it as
  #                the row's arming control, never as a gated arm.
  #
  # The digest lives on the kind value, gen-schema's lazy `__mint.minted`; every reader holds a
  # shared reference and none re-derives it, so the construction pays the mint once per KIND. The
  # instance data plane (gen-merge, gen-schema) is still the LIVE code on both stacks, so a cost there
  # is diluted by the ratio; the rows that gate that plane are the pure/ref matrix above.
  kindMatch =
    let
      S = genSchemaNew;
      M = genMerge;
      sealed = builtins.elem stack [
        "attrs-ref-sealed"
        "kind-sealed"
      ];
      isRef = builtins.elem stack [
        "attrs-ref"
        "attrs-ref-sealed"
      ];
      sel = if isRef then genSelectOrig else genSelect;
      declA = {
        addr = M.mkOption { type = if sealed then lib.types.str else M.types.str; };
      };
      declB = declA // {
        tags = M.mkOption {
          type = M.types.listOf M.types.str;
          default = [ ];
        };
      };
      mkHost = d: (S.evalSchema { modules = [ { config.schema.host.options = d; } ]; }).host;
      kA = mkHost declA;
      kB = mkHost declB;
      names = p: builtins.genList (i: "${p}${toString i}") (n / 2);
      nodes = names "a" ++ names "b";
      isA = id: builtins.substring 0 1 id == "a";
      ev = M.evalModuleTree {
        modules = [
          {
            options.hostsA = S.mkInstanceRegistry kA { };
            options.hostsB = S.mkInstanceRegistry kB { };
            config.hostsA = builtins.listToAttrs (
              map (x: {
                name = x;
                value.addr = "10.0.0.1";
              }) (names "a")
            );
            config.hostsB = builtins.listToAttrs (
              map (x: {
                name = x;
                value.addr = "10.0.0.2";
              }) (names "b")
            );
          }
        ];
      };
      ctx = sel.adapters.registry.mkContext {
        inherit nodes;
        data = id: if isA id then ev.config.hostsA.${id} else ev.config.hostsB.${id};
        parent = _: null;
        kindFor =
          if stack == "kind-plant" then
            (id: if isA id then mkHost declA else mkHost declB)
          else
            (id: if isA id then kA else kB);
      };
      selector = if isRef then sel.attrs { addr = "10.0.0.1"; } else sel.kind kA;
    in
    builtins.filter (id: sel.matches selector id ctx) nodes;

  # ── entityMatch — INSTANCE identity at scale (den-hoag-l0y U2): the stack that FORCES `id_hash` ──
  # kindMatch never forces an instance's `id_hash` (the registry adapter's `entryFor` tests presence
  # only), so a per-instance cost in gen-schema's stamp is invisible there. This row reads every
  # node's stamp through `sel.entity`. Two kinds share ONE name (`host`) and differ by a non-key
  # option, so `kindEq` calls them two kinds; registries A and B hold the SAME instance names
  # (`h0`..) at the SAME key values, so only the kind can separate the two halves.
  #
  #   attrs-ref    : THE DENOMINATOR, and it runs NO library under test. The frozen gen-schema
  #                  (`gen-schema-orig`) on the pinned nixpkgs `lib.evalModules`, matched with
  #                  `sel.attrs { addr; name = "h0"; }` through the frozen gen-select
  #                  (`gen-select-orig`) — schemaHosts' `ref` stack joined to kindMatch's frozen
  #                  matcher. With the live gen-schema in the denominator, a cost both stacks pay in it
  #                  LOWERS a ratio above 1, so the one-sided gate reads a regression as an improvement.
  #                  No stamp is read. Projection: both halves, `[ "a:h0" "b:h0" ]`.
  #   entity       : `sel.entity kA hostsA.h0` through the LIVE gen-select over LIVE gen-schema
  #                  instances: forces all n stamps. Projection: `[ "a:h0" ]`; a name-keyed stamp gives
  #                  both halves.
  #   entity-plant : `entity` with every node's instance evaluated under a kind RE-DERIVED for that
  #                  node, so each stamp forces a fresh mark — the per-instance recompute. Byte-identical
  #                  to `entity`, so only the counter gate can see it; perf-bench.sh runs it as the row's
  #                  arming control, never as a gated arm.
  #   attrs-ref-sealed / entity-sealed : the SEALED fixture (den-hoag-l0y (β); kindMatch's precedent).
  #                  `addr` is typed by nixpkgs `lib.types.str`, so both kinds carry a sealed component
  #                  and the one matching node reaches `sel.entity`'s sealed arm (the node's kind key,
  #                  then `kindEq`). Without it, a cost confined to that arm, such as reading every
  #                  node's kind before the stamp decides, is invisible here.
  #
  # Both engines carry `mkSchemaOption`, and `gen-schema-orig` predates `evalSchema`, so the kinds are
  # frozen in their own prior pass in the in-module declaration form on BOTH stacks (schemaHosts'
  # precedent), which keeps the two arms one shape.
  entityMatch =
    let
      isRef = stack == "attrs-ref" || stack == "attrs-ref-sealed";
      sealedE = stack == "attrs-ref-sealed" || stack == "entity-sealed";
      sel = if isRef then genSelectOrig else genSelect;
      S = if isRef then genSchemaOld else genSchemaNew;
      O = if isRef then lib else genMerge;
      eval = if isRef then lib.evalModules else genMerge.evalModuleTree;
      declA = {
        addr = O.mkOption { type = if sealedE then lib.types.str else O.types.str; };
      };
      declB = declA // {
        tags = O.mkOption {
          type = O.types.listOf O.types.str;
          default = [ ];
        };
      };
      mkHost =
        d:
        (eval {
          modules = [
            {
              options.schema = S.mkSchemaOption { };
              config.schema.host.options = d;
            }
          ];
        }).config.schema.host;
      kA = mkHost declA;
      kB = mkHost declB;
      half = builtins.genList (i: "h${toString i}") (n / 2);
      nodes = map (x: "a:${x}") half ++ map (x: "b:${x}") half;
      isA = id: builtins.substring 0 2 id == "a:";
      inst = id: builtins.substring 2 (builtins.stringLength id - 2) id;
      regOf =
        xs:
        builtins.listToAttrs (
          map (x: {
            name = x;
            value.addr = "10.0.0.1";
          }) xs
        );
      ev = eval {
        modules = [
          {
            options.hostsA = S.mkInstanceRegistry kA { };
            options.hostsB = S.mkInstanceRegistry kB { };
            config.hostsA = regOf half;
            config.hostsB = regOf half;
          }
        ];
      };
      planted = stack == "entity-plant";
      evOne =
        id:
        (eval {
          modules = [
            {
              options.h = S.mkInstanceRegistry (mkHost (if isA id then declA else declB)) { };
              config.h.${inst id}.addr = "10.0.0.1";
            }
          ];
        }).config.h.${inst id};
      ctx = sel.adapters.registry.mkContext {
        inherit nodes;
        data =
          id:
          if planted then
            evOne id
          else if isA id then
            ev.config.hostsA.${inst id}
          else
            ev.config.hostsB.${inst id};
        parent = _: null;
        kindFor = id: if isA id then kA else kB;
      };
      selector =
        if isRef then
          sel.attrs {
            addr = "10.0.0.1";
            name = "h0";
          }
        else
          sel.entity kA ev.config.hostsA.h0;
    in
    builtins.filter (id: sel.matches selector id ctx) nodes;

  projection =
    if workload == "preflight" then
      preflight
    else if workload == "classShare" then
      classShare
    else if workload == "overrideWarm" then
      overrideWarm
    else if workload == "kindMatch" then
      kindMatch
    else if workload == "entityMatch" then
      entityMatch
    else
      workloads.${workload} P;
  json = builtins.toJSON projection;
in
# The census is READ, not digested: ci/perf-bench.sh parses the residue and the leaks out of it, and
# a digest would hide exactly the thing it exists to report. `json` stays a thunk on this branch, so
# no member body is forced; `preflight` stays a thunk on every other branch, so the gated counters
# are untouched by its presence.
if workload == "preflight" then
  projection
else
  {
    digest = builtins.hashString "sha256" json;
    count = builtins.stringLength json;
  }
