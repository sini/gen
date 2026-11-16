# lib-door — the hub's lib-instantiated engine door: `gen.lib.instantiate { lib }` on the flake path
# and the `lib` formal on the standalone entry (`../default.nix`), ADR-0039 S4, den-hoag-6v35f C-i.
#
# ── WHAT THIS IS FOR ──
# The engine takes `lib` as an instantiation parameter, and every surface the hub published before
# the door was the engine built with none. So a module in nixpkgs' commonest shape,
# `{ lib, ... }: { options.x = lib.mkOption …; }`, was refused wherever a hub consumer evaluated it,
# where nixpkgs serves it. These cells hold the door to nixpkgs' answer, cell for cell, at every
# place a module meets an engine: the root, a nested submodule, a gen-schema registry and a nested
# one, gen-aspects' schema extension, `compose`, a bucket, and the engine calls two dependents make
# themselves (gen-schema's `evalSchema`, gen-class's `applyCoreFixed`).
#
# ── WHAT THE DOOR MUST NOT DO ──
# Leave a dependent on the no-lib engine. There are two shapes of that escape, and the value cells
# catch only one of them: the door engine evaluates every nested instance itself, so a registry cell
# stays green over an escaped gen-schema. Hence the census (every member but the zero-dependency
# leaves of the hub lock is rebuilt: a pass-through reds it) and the dependent-driven cells (a member
# rebuilt over the no-lib engine passes the census and reds them). Each shape is armed below.
#
# The published surface is unchanged: `mkGenLibs`'s argument stays vestigial, every published cell
# still refuses, and `mkGenLibs { lib }` is the same value as `mkGenLibs { }` member for member.
#
# ── THE ARMING IS IN THE CELL, AND IT GATES ──
# Each arm re-runs a gating reading over a seeded defect and must read the defect, evaluated on every
# run. Flake-path defects are rebuilt as values over the same construction the door uses
# (`import <gen> { lib; src; … }`). Standalone-entry defects are TEXT seeds of `../default.nix` itself,
# each asserted to have changed the text before it is read, so a seed that no-ops reds rather than
# passing. A guard that can no longer fire is not a passing guard.
#
# ── REACH ──
# NOT HERMETIC: the standalone cells build the roster from the root lock's fixed-output tarballs,
# like `hub-entry`'s fetch cell. The planted-lock cells fetch nothing (their `src` is a fixture).
# Not here: den's own consumer path (it needs den's lock to pin a hub with the door), and nixpkgs
# `evalModules` mounting a gen-schema registry type, which aborts uncatchably on the published and
# the door roster alike (den-hoag-glzkb).
{ gen }:
let
  nlib = gen.inputs.nixpkgs.lib;
  marker = l: l.marker or (if l ? evalModules then "nixpkgs" else "other");
  served = "served:nixpkgs";

  flakeSrc = segs: (builtins.foldl' (n: s: n.inputs.${s}) { inherit (gen) inputs; } segs).outPath;

  pubRoster = gen.lib.mkGenLibs { };
  door = gen.lib.instantiate { lib = nlib; };
  doorRoster = door.mkGenLibs { };
  standalone = import "${gen}" { lib = nlib; };

  # A cell's value, forced and classified: `{ v = … }` or `"R"` (a catchable refusal).
  v =
    x:
    let
      r = builtins.tryEval (builtins.deepSeq x x);
    in
    if r.success then { v = r.value; } else "R";
  isServed = x: v x == { v = served; };

  readsLib =
    { lib, ... }:
    {
      options.backendKind = lib.mkOption {
        type = lib.types.str;
        default = "served:${marker lib}";
      };
    };

  mergeRoot = R: (R.merge.evalModuleTree { } [ readsLib ]).config.backendKind;
  mergeNested =
    R:
    (R.merge.evalModuleTree { } [
      {
        options.loom = R.merge.mkOption {
          type = R.merge.types.submodule [ readsLib ];
          default = { };
        };
      }
    ]).config.loom.backendKind;
  schemaOf =
    R:
    R.schema.evalSchema { } [
      {
        config.schema.node.options.addr = R.merge.mkOption { type = R.merge.types.str; };
        config.schema.port.options.num = R.merge.mkOption {
          type = R.merge.types.str;
          default = "0";
        };
      }
    ];
  registry =
    R:
    (R.merge.evalModuleTree { } [
      {
        options.nodes = R.schema.mkInstanceRegistry { extraModules = [ readsLib ]; } (schemaOf R).node;
        config.nodes.n1.addr = "10.0.0.1";
      }
    ]).config.nodes.n1.backendKind;
  nestedRegistry =
    R:
    let
      s = schemaOf R;
    in
    (R.merge.evalModuleTree { } [
      {
        options.nodes = R.schema.mkInstanceRegistry {
          extraModules = [
            { options.ports = R.schema.mkInstanceRegistry { extraModules = [ readsLib ]; } s.port; }
          ];
        } s.node;
        config.nodes.n1.addr = "10.0.0.1";
        config.nodes.n1.ports.p1 = { };
      }
    ]).config.nodes.n1.ports.p1.backendKind;
  aspectsFlow =
    R:
    let
      schema = R.aspects.mkAspectSchema { keySemantics.nixos.category = "class"; };
    in
    (R.merge.evalModuleTree { } [
      { options.schema = schema.schemaOption; }
      (schema.mkAspectModule { })
      {
        config.schema.aspect.imports = [ readsLib ];
        config.aspects.web = { };
      }
    ]).config.aspects.web.backendKind;
  # A dependent's OWN engine call: gen-schema's `evalSchema` evaluates schema modules with the merge
  # gen-schema was built over.
  schemaLevel =
    R:
    let
      s = R.schema.evalSchema { } [
        (
          { lib, ... }:
          {
            config.schema.node.options.tag = R.merge.mkOption {
              type = R.merge.types.str;
              default = "served:${marker lib}";
            };
          }
        )
      ];
    in
    (R.merge.evalModuleTree { } [
      {
        options.nodes = R.schema.mkInstanceRegistry { } s.node;
        config.nodes.n1 = { };
      }
    ]).config.nodes.n1.tag;
  # gen-class's own engine call (`applyCoreFixed` → its merge's `evalModuleTree`).
  classApply =
    R:
    let
      core = R.class.mkCoreRecord {
        class = R.class.mkClass { } "agent" [ "a" ];
        projection = "agent.opts";
        sharedKeys = [ "k" ];
        values = {
          k = 1;
        };
      };
    in
    (R.class.applyCoreFixed { } core [ readsLib ]).config.backendKind;
  composeRoot = C: (C { modules = [ readsLib ]; }).values.backendKind;
  composeNested =
    C: R:
    (C {
      modules = [
        {
          options.loom = R.merge.mkOption {
            type = R.merge.types.submodule [ readsLib ];
            default = { };
          };
        }
      ];
    }).values.loom.backendKind;

  # Every reading a roster must serve. `compose` is the roster's own when it has one.
  valueCells =
    R: C:
    {
      merge-root = isServed (mergeRoot R);
      merge-nested = isServed (mergeNested R);
      registry = isServed (registry R);
      nested-registry = isServed (nestedRegistry R);
      aspects = isServed (aspectsFlow R);
      schema-level = isServed (schemaLevel R);
      class-apply = isServed (classApply R);
    }
    // (
      if C == null then
        { }
      else
        {
          compose-root = isServed (composeRoot C);
          compose-nested = isServed (composeNested C R);
        }
    );
  allTrue = s: builtins.all (x: x) (builtins.attrValues s);
  noneTrue = s: !(builtins.any (x: x) (builtins.attrValues s));

  # ── nixpkgs' twins: the answer every door cell is held to ──
  npRoot = (nlib.evalModules { modules = [ readsLib ]; }).config.backendKind;
  npNested =
    (nlib.evalModules {
      modules = [
        {
          options.loom = nlib.mkOption {
            type = nlib.types.submodule [ readsLib ];
            default = { };
          };
        }
      ];
    }).config.loom.backendKind;

  # ── the rebuilt-member census ──
  # Pointer identity without forcing a member: a member's first function-valued attribute, compared
  # inside an `attrValues (intersectAttrs …)` list (the attrset's own element pointers; a list literal
  # would make a fresh thunk per side and never compare equal).
  fnName =
    m:
    let
      ns = builtins.filter (
        n:
        let
          t = builtins.tryEval (builtins.isFunction m.${n});
        in
        t.success && t.value
      ) (builtins.attrNames m);
    in
    if builtins.isAttrs m && ns != [ ] then builtins.head ns else null;
  pick = n: m: builtins.attrValues (builtins.intersectAttrs { ${n} = null; } m);
  sameMember =
    a: b:
    let
      n = fnName a;
      r = builtins.tryEval (
        if n != null then pick n a == pick n b else pick "x" { x = a; } == pick "x" { x = b; }
      );
    in
    r.success && r.value;
  sharedWith =
    A: B:
    builtins.filter (
      k: k != "strata" && sameMember (builtins.head (pick k A)) (builtins.head (pick k B))
    ) (builtins.attrNames B);
  # The members a rebuild may share: the zero-dependency leaves of the hub lock, whose `import ./lib`
  # is memoised by path. Read from the lock, never listed.
  hubLock = builtins.fromJSON (builtins.readFile "${gen}/flake.lock");
  rootIn = hubLock.nodes.${hubLock.root}.inputs;
  rosterKeys = builtins.filter (k: k != "strata") (builtins.attrNames pubRoster);
  leaves = builtins.filter (
    k: rootIn ? "gen-${k}" && (hubLock.nodes.${rootIn."gen-${k}"}.inputs or { }) == { }
  ) rosterKeys;
  onlyLeavesShared = A: builtins.all (k: builtins.elem k leaves) (sharedWith A pubRoster);

  # ── precedence (nixpkgs' order), each beside its twin ──
  callerLib = nlib // {
    marker = "caller";
  };
  maLib = nlib // {
    marker = "module-args";
  };
  submoduleLoom = mkOption: type: {
    options.loom = mkOption {
      inherit type;
      default = { };
    };
  };
  precedence = {
    caller-root = {
      door =
        v
          (doorRoster.merge.evalModuleTree { specialArgs.lib = callerLib; } [ readsLib ]).config.backendKind;
      np =
        v
          (nlib.evalModules {
            specialArgs.lib = callerLib;
            modules = [ readsLib ];
          }).config.backendKind;
    };
    caller-not-nested = {
      door =
        v
          (doorRoster.merge.evalModuleTree { specialArgs.lib = callerLib; } [
            (submoduleLoom doorRoster.merge.mkOption (doorRoster.merge.types.submodule [ readsLib ]))
          ]).config.loom.backendKind;
      np =
        v
          (nlib.evalModules {
            specialArgs.lib = callerLib;
            modules = [ (submoduleLoom nlib.mkOption (nlib.types.submodule [ readsLib ])) ];
          }).config.loom.backendKind;
    };
    module-args-shadowed = {
      door =
        v
          (doorRoster.merge.evalModuleTree { } [
            { _module.args.lib = maLib; }
            { options.x = doorRoster.merge.mkOption { type = doorRoster.merge.types.str; }; }
            ({ lib, ... }: { x = marker lib; })
          ]).config.x;
      np =
        v
          (nlib.evalModules {
            modules = [
              { _module.args.lib = maLib; }
              { options.x = nlib.mkOption { type = nlib.types.str; }; }
              ({ lib, ... }: { x = marker lib; })
            ];
          }).config.x;
    };
    submodule-own-args = {
      door =
        v
          (doorRoster.merge.evalModuleTree { } [
            (submoduleLoom doorRoster.merge.mkOption (
              (doorRoster.merge.types.submodule [ readsLib ]).withArgs { lib = callerLib; }
            ))
          ]).config.loom.backendKind;
      np =
        v
          (nlib.evalModules {
            modules = [
              (submoduleLoom nlib.mkOption (
                nlib.types.submoduleWith {
                  modules = [ readsLib ];
                  specialArgs.lib = callerLib;
                }
              ))
            ];
          }).config.loom.backendKind;
    };
    presence = {
      door = v (presence doorRoster);
      np =
        v
          (nlib.evalModules {
            modules = [
              (
                { ... }@a:
                {
                  options.p = nlib.mkOption {
                    type = nlib.types.bool;
                    default = a ? lib;
                  };
                }
              )
            ];
          }).config.p;
    };
  };
  registrySpecialArgs =
    v
      (doorRoster.merge.evalModuleTree { } [
        {
          options.nodes = doorRoster.schema.mkInstanceRegistry {
            extraModules = [ readsLib ];
            specialArgs.lib = callerLib;
          } (schemaOf doorRoster).node;
          config.nodes.n1.addr = "10.0.0.1";
        }
      ]).config.nodes.n1.backendKind;
  presence =
    R:
    (R.merge.evalModuleTree { } [
      (
        { ... }@a:
        {
          options.p = R.merge.mkOption {
            type = R.merge.types.bool;
            default = a ? lib;
          };
        }
      )
    ]).config.p;

  # ── null, throw, laziness ──
  nullRoster = (gen.lib.instantiate { lib = null; }).mkGenLibs { };
  lazyRoster =
    (gen.lib.instantiate { lib = throw "lib-door: the instance lib was forced"; }).mkGenLibs
      { };
  lazyUnread =
    (lazyRoster.merge.evalModuleTree { } [
      {
        options.x = lazyRoster.merge.mkOption {
          type = lazyRoster.merge.types.str;
          default = "unread";
        };
      }
    ]).config.x;

  # ── K4: two rosters in one evaluation (ADR-0034, identity through the one mint) ──
  mintAns = R: [
    (R.identity.hashIdentity "spindle" [ "name" ] (_: "flax"))
    (R.identity.hashIdentity "spindle" [ "name" ] (_: "linen"))
  ];
  kindId = R: (schemaOf R).node.__moduleKey;

  # ── THE STANDALONE ENTRY, read the way `hub-entry` reads it ──
  # `../default.nix` re-imported under a scope whose `readFile` answers `flake.lock` with a given
  # lock, and whose `throw` lets only the expected refusal through (any other aborts with its text,
  # so a refusal naming the wrong thing reds loudly). `text`, when given, is a seeded copy of the
  # entry: its relative imports are never reached, since every cell supplies `wire`.
  entryText = builtins.readFile "${gen}/default.nix";
  entryWith =
    {
      lock ? hubLock,
      expected ? "a refusal no cell expects",
      text ? null,
    }:
    builtins.scopedImport {
      builtins = builtins // {
        readFile =
          p: if baseNameOf (toString p) == "flake.lock" then builtins.toJSON lock else builtins.readFile p;
      };
      throw =
        m:
        if builtins.match expected m != null then
          builtins.throw m
        else
          builtins.abort "lib-door: an unexpected refusal from the entry: ${m}";
    } (if text == null then "${gen}/default.nix" else builtins.toFile "default.nix" text);
  # A seed that changes nothing is a broken instrument, not a green.
  seed =
    from: to:
    let
      t = builtins.replaceStrings [ from ] [ to ] entryText;
    in
    if t == entryText then
      builtins.abort "lib-door: a seed did not change ../default.nix: ${from}"
    else
      t;
  fixtureMember = builtins.toFile "lib-door-fixture-member.nix" ''
    { inputs ? { }, src ? null, dep ? null }: builtins.seq (builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) inputs) null) { }
  '';
  # gen-merge's stand-in: accepts both the seams and the named-formal shapes, and records which arrived.
  fixtureMerge = builtins.toFile "lib-door-fixture-merge.nix" ''
    { inputs ? { }, src ? null, dep ? null, wire ? null, prelude ? null, types ? null, memo ? null, scope ? null }@a:
    { received = builtins.attrNames a; edges = builtins.attrNames inputs; }
  '';
  fixtureSrc = segs: if segs == [ "gen-merge" ] then fixtureMerge else fixtureMember;
  # Every member forced to WHNF, as the entry's own `forced` does, and no deeper: a deeper force reaches
  # into a built engine, whose own failure would read as this entry's refusal.
  refused =
    entry: args:
    !(builtins.tryEval (
      builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) (
        entry ({ wire = a: a.deps; } // args)
      )) true
    )).success;

  # C1 — a planted extra gen-merge edge: the lib-given gen-merge must receive the hub lock's edges
  # (all of them, the planted one included) through the seams, never a named subset.
  mergeNode = rootIn.gen-merge;
  plantedEdge = "gen-identity";
  lockExtraEdge = hubLock // {
    nodes = hubLock.nodes // {
      ${mergeNode} = hubLock.nodes.${mergeNode} // {
        inputs = hubLock.nodes.${mergeNode}.inputs // {
          ${plantedEdge} = [ plantedEdge ];
        };
      };
    };
  };
  mergeOn =
    l: text:
    (
      (entryWith {
        lock = l;
        inherit text;
      })
        {
          lib = nlib;
          src = fixtureSrc;
          wire = a: a.deps;
        }
    ).merge;
  edgesHanded =
    m:
    builtins.elem "inputs" m.received
    && m.edges == builtins.attrNames (lockExtraEdge.nodes.${mergeNode}.inputs);
  # The seed: gen-merge handed named formals instead of the seams (the hand-list shape).
  handListText = seed "segs: import (src segs) (seams segs // instantiate segs)" "segs: import (src segs) (if named.\${fetch.node segs} or \"\" == \"gen-merge\" then { inherit prelude types memo scope; } // instantiate segs else seams segs)";

  # C2 / construction precedence: `lib` beside an already-built `merge` or a caller's `dep`.
  mergeMsg = "gen: `lib' instantiates the engine this entry builds, and `merge' was supplied already built;.*";
  depMsg = "gen: `lib' instantiates the engine through this entry's own `dep', and a caller's `dep' was supplied;.*";
  fixtureArgs = {
    src = fixtureSrc;
  };
  noMergeRefusal = seed "if args ? lib && (args ? merge || inputs ? gen-merge) then" "if false then";
  noDepRefusal = seed "else if args ? lib && args ? dep then" "else if false then";

  # G4 — the door's `src` is the consumer's resolution: a consumer input the door must read. Its
  # `outPath` throws, its `.lib` is the real one, so the published flake roster (which reads `.lib`)
  # builds and the door (which reads `outPath`) refuses.
  plantedInputs = gen.inputs // {
    gen-identity = gen.inputs.gen-identity // {
      outPath = throw "lib-door: the door read the consumer's input";
    };
  };
  plantedHub = (import "${gen}/flake.nix").outputs plantedInputs;
  forcesIdentity = R: (builtins.tryEval (builtins.seq R.identity true)).success;

  # ── THE SEEDED DEFECTS over the flake construction ──
  # m2-escape: the door's gen-schema left on the published, no-lib schema (a pass-through).
  escaped = import "${gen}" {
    lib = nlib;
    src = flakeSrc;
    schema = pubRoster.schema;
  };
  # mg-oldengine: every member rebuilt over the no-lib engine, `merge` itself lib-built.
  oldEngine = noLib // {
    inherit (doorRoster) merge;
  };
  # m2-nolib: the reconstruction with `lib` withheld.
  noLib = import "${gen}" { src = flakeSrc; };

  doorCells = valueCells doorRoster door.compose;
  standaloneCells = valueCells standalone null;

  gate = {
    # G1 — the flake door serves nixpkgs' answer at every place a module meets an engine.
    door-serves-every-cell =
      allTrue doorCells
      && isServed (mergeRoot {
        merge = door.modules.merge;
      });
    door-equals-the-twin =
      v (mergeRoot doorRoster) == v npRoot && v (mergeNested doorRoster) == v npNested;
    # G2 — the standalone door, the same.
    standalone-serves-every-cell = allTrue standaloneCells;
    # G3 — every member but the hub lock's leaves is rebuilt.
    door-rebuilds-every-non-leaf = onlyLeavesShared doorRoster;
    # G4 — the door reads the consumer's inputs and fetches nothing of its own.
    door-reads-consumer-inputs =
      !forcesIdentity ((plantedHub.lib.instantiate { lib = nlib; }).mkGenLibs { })
      && forcesIdentity (plantedHub.lib.mkGenLibs { });
    # G5 — the published surface is unchanged: refused as before, and the argument still ignored.
    published-still-refuses =
      noneTrue (valueCells pubRoster gen.lib.compose) && v (presence pubRoster) == { v = false; };
    standalone-default-still-refuses = !(isServed (registry (import "${gen}" { })));
    mkGenLibs-argument-still-ignored =
      sharedWith (gen.lib.mkGenLibs { lib = nlib; }) pubRoster == rosterKeys;
    # G6 — precedence, each row equal to nixpkgs' twin.
    precedence-equals-the-twin = builtins.all (r: r.door == r.np) (builtins.attrValues precedence);
    precedence-rows-discriminate =
      precedence.caller-root.door == {
        v = "served:caller";
      }
      && precedence.caller-not-nested.door == { v = served; }
      && precedence.module-args-shadowed.door == { v = "nixpkgs"; }
      && precedence.submodule-own-args.door == { v = "served:caller"; }
      && precedence.presence.door == { v = true; };
    registry-specialArgs-wins = registrySpecialArgs == { v = "served:caller"; };
    # G6′ / C2 — construction precedence, each refusal by name.
    lib-beside-merge-refused = refused (entryWith { expected = mergeMsg; }) (
      fixtureArgs
      // {
        lib = nlib;
        merge = { };
      }
    );
    lib-beside-inputs-merge-refused = refused (entryWith { expected = mergeMsg; }) (
      fixtureArgs
      // {
        lib = nlib;
        inputs.gen-merge = { };
      }
    );
    lib-beside-dep-refused = refused (entryWith { expected = depMsg; }) (
      fixtureArgs
      // {
        lib = nlib;
        dep = segs: segs;
      }
    );
    merge-alone-builds = !(refused (entryWith { }) (fixtureArgs // { merge = { }; }));
    dep-alone-builds = !(refused (entryWith { }) { dep = segs: segs; });
    lib-beside-schema-builds =
      !(refused (entryWith { }) (
        fixtureArgs
        // {
          lib = nlib;
          schema = { };
        }
      ));
    # G7 — given null is a null instance (refused where read, the key present); a throwing `lib` is
    # forced only where read.
    given-null-refused-where-read =
      v (mergeRoot nullRoster) == "R" && v (presence nullRoster) == { v = true; };
    standalone-given-null-refused-where-read = v (mergeRoot (import "${gen}" { lib = null; })) == "R";
    throwing-lib-unread = v lazyUnread == { v = "unread"; };
    throwing-lib-read = v (mergeRoot lazyRoster) == "R";
    # G8 — K4: one mint and one kind key across the two rosters, and the two doors agree.
    k4-mint-agrees = mintAns doorRoster == mintAns pubRoster;
    k4-mint-control-differs =
      builtins.head (mintAns doorRoster) != builtins.elemAt (mintAns pubRoster) 1;
    k4-kind-id-agrees = kindId doorRoster == kindId pubRoster;
    k4-kind-id-control-differs = kindId doorRoster != (schemaOf doorRoster).port.__moduleKey;
    k4-roster-keys-agree = builtins.attrNames doorRoster == builtins.attrNames pubRoster;
    k4-doors-agree = v (registry standalone) == v (registry doorRoster);
    k4-mixed-redeclare =
      v
        (doorRoster.merge.evalModuleTree { } [
          { options.x = pubRoster.merge.mkOption { type = pubRoster.merge.types.str; }; }
          { options.x = doorRoster.merge.mkOption { type = doorRoster.merge.types.str; }; }
          { x = "both"; }
        ]).config.x == {
        v = "both";
      };
    # C1 — the lib-given gen-merge receives every edge the lock records, through the seams.
    merge-receives-the-lock-edges = edgesHanded (mergeOn lockExtraEdge null);

    # ── ARMING — a guard that cannot fire is not a passing guard ──
    arming-escape-reds-the-census =
      !(onlyLeavesShared escaped) && builtins.elem "schema" (sharedWith escaped pubRoster);
    arming-escape-reds-schema-level = !(isServed (schemaLevel escaped));
    # The census is blind to a member rebuilt over the no-lib engine; the dependent cells are not.
    arming-oldengine-reds-the-dependents =
      !(isServed (classApply oldEngine))
      && !(isServed (schemaLevel oldEngine))
      && isServed (mergeRoot oldEngine);
    arming-nolib-reds-every-cell = noneTrue (valueCells noLib null);
    arming-dropped-src-reads-the-hub-lock = forcesIdentity standalone;
    arming-hand-list-reds-c1 = !(edgesHanded (mergeOn lockExtraEdge handListText));
    arming-dropped-merge-refusal =
      !(refused (entryWith { text = noMergeRefusal; }) (
        fixtureArgs
        // {
          lib = nlib;
          merge = { };
        }
      ));
    arming-dropped-dep-refusal =
      !(refused (entryWith { text = noDepRefusal; }) (
        fixtureArgs
        // {
          lib = nlib;
          dep = segs: segs;
        }
      ));
  };
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  report = {
    governs = "`gen.lib.instantiate { lib }` and the standalone entry's `lib` formal: an engine instantiated with the caller's lib, every dependent rebuilt over it";
    inherit leaves precedence;
    door = doorCells;
    standalone = standaloneCells;
    shared = {
      door = sharedWith doorRoster pubRoster;
      escaped = sharedWith escaped pubRoster;
      oldEngine = sharedWith oldEngine pubRoster;
    };
    c1 = {
      live = mergeOn lockExtraEdge null;
      handList = mergeOn lockExtraEdge handListText;
    };
    # Not gating, an open defect (den-hoag-h5zcu): in a mixed evaluation a nested submodule's `lib`
    # follows the EVALUATING engine, where nixpkgs follows the type's instance.
    mixedMount =
      v
        (pubRoster.merge.evalModuleTree { } [
          (submoduleLoom pubRoster.merge.mkOption (doorRoster.merge.types.submodule [ readsLib ]))
        ]).config.loom.backendKind;
  };
}
