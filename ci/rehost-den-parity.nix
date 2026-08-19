# C4 — REAL-den byte-parity oracle (the substrate's final acceptance gate, against den's actual usage).
#
# Feasibility findings (see report):
#  - Full-den `--override-input` is INFEASIBLE: den fetches gen-schema via `builtins.fetchTarball`
#    from templates/ci/flake.lock (nix/lib/schema.nix), NOT a declared flake input → not overridable;
#    and the re-hosted flakes reference unpublished github:sini/gen-{merge,types}.
#  - den does NOT consume gen-aspects at all — it has its OWN native aspect layer (nix/lib/aspects/,
#    `den.lib.aspects.types.aspectType`). So the gen-aspects re-host has no real den consumer; its
#    validation is the C2 suite + grammar parity oracle. (Finding, not a gap.)
#  - den DOES consume gen-schema deeply (den entities = gen-schema registries), but via
#    `import gen-schema { inherit lib; }` — the OLD nixpkgs signature. The re-host changed it to
#    `{ prelude, merge, algebra }` → den needs a migration/compat shim (the C3 breaking-change,
#    now CONFIRMED live against real den).
#
# So the achievable real-den battle-test = den's ACTUAL `mkSchemaOption` registry (extracted verbatim
# from den/modules/options.nix: the 4 collections incl OR-merge isEntity/isolated, the `computed`
# isEntity derivation, the parent topology user/home→host, and host/user/home importing the `conf`
# kind) driven through the RE-HOSTED (pure) gen-schema vs the ORIGINAL nixpkgs gen-schema, asserted
# byte-identical. This is den's real registry shape, not synthetic. Read-only; den unmodified.
#
# ── REPRODUCIBLE PINNING (permanent gen-ci regression) — see ci/flake.nix ──
# PURE side (guarded) = published re-host main gen-schema (`{ prelude, merge, algebra }`); REFERENCE
# side (frozen golden) = ORIGINAL nixpkgs-signature gen-schema (`{ lib, algebra }`, pre-re-host pin)
# driven through a PINNED `github:nix-community/nixpkgs.lib` (NOT impure `getFlake "nixpkgs"`).
{
  gen-prelude,
  gen-types,
  gen-merge,
  gen-algebra,
  gen-schema, # PURE re-host (published main)
  gen-schema-orig, # ORIGINAL nixpkgs-signature { lib, algebra } (pre-re-host pin)
  lib, # pinned nixpkgs.lib
}:
let
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
  genSchemaOld = import "${gen-schema-orig}/lib" {
    inherit lib;
    algebra = genAlgebra;
  };

  pureP = {
    inherit (genMerge) mkOption;
    types = genMerge.types;
    eval = genMerge.evalModuleTree;
    schema = genSchemaNew;
  };
  refP = {
    inherit (lib) mkOption types;
    eval = lib.evalModules;
    schema = genSchemaOld;
  };

  # ── den's ACTUAL mkSchemaOption config (verbatim from den/modules/options.nix:73-110) ──
  denSchemaArgs = {
    collections = {
      includes = {
        default = [ ];
      };
      excludes = {
        default = [ ];
      };
      isEntity = {
        default = false;
        merge = acc: val: acc || val;
      };
      isolated = {
        default = false;
        merge = acc: val: acc || val;
      };
    };
    computed = collections: defs: {
      isEntity =
        collections.isEntity
        || builtins.any (
          d:
          let
            v = d.value;
            collectionKeys = [
              "includes"
              "excludes"
              "isEntity"
              "isolated"
              "parent"
              "collisionPolicy"
            ];
            stripped = if builtins.isAttrs v then builtins.removeAttrs v collectionKeys else v;
          in
          !builtins.isAttrs stripped || stripped != { }
        ) defs;
    };
  };

  # den's kind topology + imports (options.nix:112-149), with real host/user/home entity options.
  driveSchema =
    P:
    let
      eval = P.eval {
        modules = [
          { options.schema = P.schema.mkSchemaOption denSchemaArgs; }
          (
            { config, ... }:
            {
              config.schema.conf = { };
              config.schema.fleet = { };
              config.schema.host = {
                options.addr = P.mkOption { type = P.types.str; };
                imports = [ config.schema.conf ];
              };
              config.schema.user = {
                parent = "host";
                options.uid = P.mkOption {
                  type = P.types.int;
                  default = 1000;
                };
                imports = [ config.schema.conf ];
              };
              config.schema.home = {
                parent = "host";
                imports = [ config.schema.conf ];
              };
            }
          )
        ];
      };
      s = eval.config.schema;
    in
    {
      # the schema-topology introspection den relies on (schema-util.nix reads _kindNames; entities
      # read isEntity/parent/isolated)
      kindNames = s._kindNames;
      topology = s._topology;
      roots = s._roots;
      leaves = s._leaves;
      edges = s._edges;
      host-isEntity = s.host.isEntity;
      host-isolated = s.host.isolated;
      user-parent = s.user.parent;
      home-parent = s.home.parent;
      conf-isEntity = s.conf.isEntity;
      host-includes = s.host.includes;
    };

  pureSchema = driveSchema pureP;
  refSchema = driveSchema refP;

  # ── real-den INSTANCE registry (id_hash + strict) — host instances with addr, as den entities are ──
  driveInstances =
    P: addr2:
    let
      eval = P.eval {
        modules = [
          {
            options.schema = P.schema.mkSchemaOption denSchemaArgs;
            config.schema.host.options.addr = P.mkOption { type = P.types.str; };
          }
          (
            { config, ... }:
            {
              options.hosts = P.schema.mkInstanceRegistry config.schema.host { };
              config.hosts.blade.addr = "10.0.0.1";
              config.hosts.uplink.addr = addr2;
            }
          )
        ];
      };
    in
    lib.mapAttrs (_: h: { inherit (h) addr id_hash; }) eval.config.hosts;

  # ── NESTED-OPTIONS (den's real 2-level shape) ── den declares options UNDER `den.`:
  # `options.den.schema = mkSchemaOption …` and `options.den.hosts = mkInstanceRegistry …`. gen-merge
  # #16 (nested option-declaration paths, d76f7d4) landed → the re-hosted engine now auto-nests the
  # option tree exactly like nixpkgs `lib.evalModules`, so this den shape resolves (was the old C4
  # "nested-unsupported" finding). Driven through BOTH stacks and asserted byte-identical.
  driveNested =
    P:
    let
      eval = P.eval {
        modules = [
          {
            options.den.schema = P.schema.mkSchemaOption denSchemaArgs;
            config.den.schema.host.options.addr = P.mkOption { type = P.types.str; };
          }
          (
            { config, ... }:
            {
              options.den.hosts = P.schema.mkInstanceRegistry config.den.schema.host { };
              config.den.hosts.blade.addr = "10.0.0.1";
            }
          )
        ];
      };
    in
    {
      kindNames = eval.config.den.schema._kindNames;
      blade = { inherit (eval.config.den.hosts.blade) addr id_hash; };
    };

  # ── THE EXCLUDED AXIS: `id_hash` HAS LEFT THIS PAIR'S DOMAIN (ADR-0016) ──
  # ci/flake.nix states the golden pair's soundness precondition: a frozen reference is only sound
  # where the SUBJECT's grammar is stable, which is why the aspect half of the pair does not exist —
  # that grammar moves by design ruling, so a gate built on a frozen witness of it reds on every
  # ruled improvement rather than on a defect. The identity encoding has now falsified the same
  # precondition for the identity fields of the schema surface. gen-schema `75d40c1` re-minted it by
  # ruling (ADR-0016): the kind left the digest to become a `"<kind>:"` tag, and the preimage became
  # `toJSON` of the ⟨label,value⟩ pairs — closing a separator-injection hole, dissolving the
  # caller-side sort obligation, and admitting every value through a predicate before a builtin.
  #
  # The reference side cannot learn it. It is called on the nixpkgs `{ lib, algebra }` signature, and
  # every revision carrying that signature predates the pure re-host, which predates this encoding —
  # so no forward golden pin exists and the frozen witness holds the OLD formula permanently.
  #
  # So the identity axis is excluded and the arms below restate over the instance KEY SETS and every
  # NON-IDENTITY field, which do still hold byte-for-byte across that ruling (measured: three changed
  # lines, all `id_hash`, nothing else). What the exclusion does NOT concede: the `id_hash` is still
  # FORCED on both engines — by `teeth-mutation` on the reference and `teeth-mutation-pure` on the
  # pure side — so an engine that stopped minting one at all fails loudly on the missing attribute
  # rather than passing narrowly; and `teeth-mutation-pure` carries the tracking load that
  # `teeth-parity` used to carry through the reference.
  dropIdentity = builtins.mapAttrs (_: i: builtins.removeAttrs i [ "id_hash" ]);
  identitiesOf = builtins.mapAttrs (_: i: i.id_hash);
  nestedNonIdentity =
    P:
    let
      n = driveNested P;
    in
    n // { blade = builtins.removeAttrs n.blade [ "id_hash" ]; };

  # TEETH on the PURE engine. Predicate: the identity of the instance whose field MOVED must move,
  # and the identity of the instance whose fields did NOT must stand still — the second conjunct is
  # what separates identity tracking its own fields from identity tracking anything at all. Written
  # as a function of an instance drive so the SAME expression reads against a seeded engine in the
  # same run.
  tracksIdentity =
    instancesAt:
    let
      a = identitiesOf (instancesAt "10.0.0.2");
      b = identitiesOf (instancesAt "10.9.9.9");
    in
    b.uplink != a.uplink && b.blade == a.blade;

  # THE SEED — the in-suite positive control on that arm: an engine whose identity is CONSTANT while
  # `addr` still varies. That is precisely the construction a narrowed byte-parity check would
  # otherwise go green on, and `addr` is left moving on purpose — a seed that froze the addr too
  # would leave the arm passing on a predicate that reads `addr` rather than `id_hash`, and a control
  # that fires on the wrong cause is not a control.
  stuckIdentityInstances =
    addr2: builtins.mapAttrs (_: i: i // { id_hash = "host:0000"; }) (driveInstances pureP addr2);
in
{
  # BYTE-PARITY on den's real registry topology/collections/computed
  parity-schema = pureSchema == refSchema;
  # BYTE-PARITY on den-shaped instances: key sets and every non-identity field (see the excluded
  # axis above — `id_hash` is compared by `teeth-mutation-pure`, not against the frozen witness)
  parity-instances =
    dropIdentity (driveInstances pureP "10.0.0.2") == dropIdentity (driveInstances refP "10.0.0.2");

  # both stacks genuinely evaluated
  both-evaluated =
    (builtins.tryEval (builtins.deepSeq pureSchema pureSchema)).success
    && (builtins.tryEval (builtins.deepSeq refSchema refSchema)).success;

  # TEETH on the REFERENCE engine: a mutated instance addr changes its record
  teeth-mutation = driveInstances refP "10.9.9.9" != driveInstances refP "10.0.0.2";
  # TEETH on the PURE engine: its identity tracks its own fields, and only its own. This arm exists
  # because the two parity arms no longer read `id_hash` at all — without it the check would go green
  # on a pure engine that had stopped tracking its inputs entirely.
  teeth-mutation-pure = tracksIdentity (driveInstances pureP);
  # …and the seeded control that makes the arm above a READING: the identical predicate over an
  # engine with a frozen identity must be FALSE, in this same run.
  arming-teeth-mutation-pure = !(tracksIdentity stuckIdentityInstances);
  # Non-identity byte-parity under the same mutation
  teeth-parity =
    dropIdentity (driveInstances pureP "10.9.9.9") == dropIdentity (driveInstances refP "10.9.9.9");

  # NESTED-OPTIONS now SUPPORTED (gen-merge #16 landed): den's real 2-level shape (`options.den.schema`
  # / `options.den.hosts`) resolves through the re-hosted engine and is byte-identical to nixpkgs
  # `lib.evalModules`. Supersedes the stale C4 `finding-nested-options-unsupported = true`.
  parity-nested = nestedNonIdentity pureP == nestedNonIdentity refP;

  sample = {
    kindNames = pureSchema.kindNames;
    topology = pureSchema.topology;
    host-isEntity = pureSchema.host-isEntity;
    conf-isEntity = pureSchema.conf-isEntity;
    instances = driveInstances pureP "10.0.0.2";
    nested = driveNested pureP;
    # The readings behind `teeth-mutation-pure` and its seeded control, PRINTED and not only
    # asserted: the pure engine's identities at both drives, and the seeded frozen ones beside them.
    identities = {
      pure-at-10-0-0-2 = identitiesOf (driveInstances pureP "10.0.0.2");
      pure-at-10-9-9-9 = identitiesOf (driveInstances pureP "10.9.9.9");
      seeded-frozen-at-10-9-9-9 = identitiesOf (stuckIdentityInstances "10.9.9.9");
    };
  };
}
