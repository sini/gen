# compose-parity — BYTE-PARITY OF THE COMPOSE MIGRATION, ADR-0008's definitional oracle, instanced
# for the two functions gen-memo's `lib/warmTrace.nix` received from gen-flake's `composeAt`.
#
# ── WHY IT LIVES IN THE HUB ──
# It was gen-memo's `ci/tests/compose-parity.nix` (19 cells) plus the `non-option-cycle` and
# `mutual-cycle` groups of that repository's `ci/tests-error.nix` (5 cells reusing its walk). Hosting
# it there needed a gen-memo/ci → gen-merge edge, and gen-merge's root declares gen-memo, so the
# roster's ci graph carried one two-member cycle. gen-memo `5b0c4a8` cut the edge and retired the
# cells; the owner ruled (den-hoag-i34de, 2026-09-24) to keep the oracle WITHOUT the cycle by moving
# it here. The hub already depends on both engines and hosts the subject, `lib/compose.nix`.
#
# THE SUBJECT IS THE DECISION CROSSING, NOT THE PLANE'S OWN FOLD. gen-memo's `byte-parity.nix` and
# `warm-parity.nix` carry the plane's defining property over the memo fold. Neither can see this
# one: the question here is whether routing a caller's warm-fire decision through `warmAdmits` —
# and its published record through `warmTrace` — leaves that caller's own output byte-identical to
# the cold evaluation of the same input. That is a property of the CALLER's evaluation, so the
# caller's evaluator has to be present; a stub would make the oracle an oracle for the stub.
#
# THE CALLER IS THE SUCCESSOR COMPOSE ITSELF, AS PUBLISHED: `gen.lib.compose` — `lib/compose.nix`
# bound to the roster's gen-merge as the engine and gen-memo's `warmAdmits`/`warmTrace` as the
# plane (`flake.nix`). The arms are the migration spec's §3.1: the successor compose evaluated
# with and without the warm path. It takes `specialArgs` caller-total and has no tree formal, so
# the fixture feeds it `modules` alone — no tree loader, no aspect registry, no host projection is
# compared by this oracle, which reads `values` and `provenance` only.
#
# R1 — THE ENGINE REVISION IS PART OF THE ORACLE, and an unpinned run is not a reading. Both arms
# run at the ROOT `flake.lock`'s gen-merge and gen-memo, reached through `gen` — the one pin set
# this ci reads (`ci-declares-no-member`). The root lock sends gen-merge's own gen-memo onto the
# hub's gen-memo (`follows`), so one evaluation holds one revision of each; `r1-*` asserts that,
# and the report records both revisions with the result. The reason is not procedural: the overflow
# bracket this oracle's ancestor was written against moved once already, and it was only visible
# because the revisions had been recorded on both sides.
#
# ── THE CELLS ARE GATE KEYS, NOT A nix-unit PLANE ──
# The hub runs flake `checks`, not nix-unit (`ci-plane-coverage` reads `no-plane`). Every cell is
# `expr == expected`, evaluated in-process by whichever evaluator runs `nix flake check ./ci`, so
# each evaluator reads its own verdict. A cell whose `expr` aborts takes the check red rather than
# green. ONE cell cannot live here: `mutual-cycle.test-mutual-same-tag-cycle-aborts-uncaught`,
# whose green state IS an abort that `tryEval` does not catch — measured under upstream,
# Determinate and Lix. It is exposed as `overflowPin` and read across a process boundary by the
# `checks` job in `.github/workflows/ci.yml`, by the job's own evaluator.
#
# ★ THE COMPARATOR IS A COPY, AND THAT IS A KNOWN, CARRIED WEAKNESS. `dropFns` below is a
# hand-written instance of the walk gen-flake shipped at `lib/diff.nix:116-159` — a `let`-local
# inside `diff`'s lambda body, which no caller can name. A drift between the shipped walk and this
# copy is a drift this oracle cannot see, and nothing below should be read as closing that gap. The
# residue is owner-ruled as CARRIED (2026-08-25) rather than discharged. The error groups' former
# `walkCopy` was a third copy of the same walk; in one file it is `dropFns` itself.
{ gen }:
let
  roster = gen.lib.mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)
  inherit (gen.lib) compose;
  inherit (roster.merge)
    types
    mkOption
    mkForce
    ;

  # ── the comparator ─────────────────────────────────────────────────────────────────────────────
  # Functions are nulled rather than skipped, so a topology change still moves the bytes even though
  # the closures themselves cannot be compared — which is exactly the blindness the H1 control below
  # measures. The walk is cycle-aware at EVERY attrs node on the current path, not only the
  # option-type protocol marker it was first written against
  # (den-hoag-memo-cycle-guard-shape-wt4b9): a completed type's `functor.type` is the type itself, so
  # an unguarded descent would not terminate — and neither would one through any other
  # self-referential attrset. `builtins.isAttrs x` already decided which nodes reach this branch; a
  # `_type` tag would be an arbitrary narrowing of that same domain, not a distinct completeness
  # claim.
  dropFns =
    let
      # The revisited ancestor's index on the path, or null when x is not one of them. `seen` is
      # nearest-ancestor-first, so 0 is the innermost, and holds EVERY attrs node walked so far on
      # the current path. `==` on attrsets short-circuits on pointer identity, so a genuine
      # self-reference reads cheaply; a coincidental structural match would force a deeper compare,
      # bounded by path depth rather than by the whole visited set.
      #
      # ★ A CARRIED RESIDUAL, PINNED RATHER THAN CLOSED (cells: `mutual-cycle.*` and `overflowPin`).
      # This scan fingerprints a candidate SOLELY by `==` against the ancestors, and `==` has no
      # cycle detection of its own; Nix exposes no pointer-identity primitive a userland comparator
      # could call instead. A candidate that is NOT pointer-identical to an ancestor but is mutually
      # cyclic WITH one makes the structural compare recurse through that same cycle, and whether it
      # terminates first on a discriminating scalar is an evaluator comparison-order detail, not a
      # guarantee. Bounding the scan to avoid that would also refuse the pointer-identical revisits
      # this guard exists to cut (the option-type functor self-cycle the fixture below depends on):
      # general cycle detection over arbitrary Nix attrsets is INEXPRESSIBLE in userland without
      # breaking the working arm.
      carrierIndex =
        seen: x:
        let
          n = builtins.length seen;
          scan =
            i:
            if i >= n then
              null
            else if builtins.elemAt seen i == x then
              i
            else
              scan (i + 1);
        in
        scan 0;
      walk =
        seen: x:
        if builtins.isFunction x then
          null
        else if builtins.isList x then
          map (walk seen) x
        else if builtins.isAttrs x then
          let
            revisit = carrierIndex seen x;
          in
          if revisit != null then
            "<cycle:${toString revisit}>"
          else
            builtins.mapAttrs (_: walk ([ x ] ++ seen)) x
        else
          x;
    in
    walk [ ];

  # Both halves, always. A values-only comparison passes while the provenance topology is corrupt,
  # and the two halves are sensitive to different corruptions — see the two RED controls, which are
  # separate cells for that reason.
  image = r: {
    values = builtins.toJSON (dropFns r.values);
    provenance = builtins.toJSON (dropFns r.provenance);
  };

  # Occurrences of a literal in an image. `builtins.split` returns the non-matching segments as
  # strings and each match's capture list as a LIST, so counting the lists counts the matches.
  countIn =
    needle: hay: builtins.length (builtins.filter builtins.isList (builtins.split needle hay));

  # ── the migration fixture ──────────────────────────────────────────────────────────────────────
  # `hooks` is declared `attrsOf raw` and defined with a lambda. That is not decoration: H1's class
  # is the leaf that is a FUNCTION on both sides of a comparison, and a fixture that never carries
  # one cannot exhibit it.
  decls = {
    options = {
      hosts = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              addr = mkOption { type = types.str; };
              role = mkOption {
                type = types.str;
                default = "worker";
              };
            };
          }
        );
        default = { };
      };
      hooks = mkOption {
        type = types.attrsOf types.raw;
        default = { };
      };
      fleet = {
        name = mkOption { type = types.str; };
        size = mkOption {
          type = types.int;
          default = 0;
        };
      };
    };
  };

  # Parameterised on the hook's closure ALONE — every other byte of the module list is shared, which
  # is what lets the H1 seed differ in the closure and in nothing else.
  #
  # ★ `hooks.ty` PUTS AN OPTION-TYPE OBJECT IN `values`, AND WITHOUT IT THIS ORACLE WOULD NOT
  # EXERCISE THE HALF OF THE COMPARATOR IT WAS CHOSEN FOR. A completed type's `functor.type` is the
  # type itself, so the resolved config carries a self-cycle; the same subject walked WITHOUT the
  # carrier seen-test aborts with a stack overflow that propagates THROUGH `builtins.tryEval`. With
  # the cut, the walk completes and the cut is visible as `<cycle:N>` markers, which is what the
  # hedges control below asserts.
  mkBase = hook: [
    decls
    {
      config.hosts.n1.addr = "10.0.1.1";
      config.hosts.n2.addr = "10.0.1.2";
      config.hooks.transform = hook;
      config.hooks.ty = types.listOf types.str;
      config.fleet.name = "prod";
      config.fleet.size = 2;
    }
  ];
  base = mkBase (x: x + 1);
  addN3 = {
    config.hosts.n3.addr = "10.0.1.3";
  };

  ovBase = compose { modules = base; };

  # ARM WARM — the override whose edit `warmAdmits` admits, so the engine splices.
  armWarm = ovBase.override { modules = [ addN3 ]; };
  # ARM COLD — the same fixture and the same revision with no warm context at all.
  armCold = compose { modules = base ++ [ addN3 ]; };

  # ★★ BOTH RED CONTROLS SEED ON THE WARM ARM'S OWN MODULE SET — `[ addN3 <seed> ]`, NOT `[ <seed> ]`.
  # §3.1 says "the same pair", and a control built as `ovBase.override { modules = [ <seed> ]; }`
  # differs from `armWarm` in the seed AND in host `n3`, so it reddens whether or not the seed does
  # anything. On the shape below a null seed goes GREEN, so the seed is necessary as well as
  # sufficient.

  # ── RED CONTROL 1 — the ordinary leaf ──────────────────────────────────────────────────────────
  ovDiffering = ovBase.override {
    modules = [
      addN3
      { config.hosts.n1.addr = mkForce "10.4.4.4"; }
    ];
  };

  # ── RED CONTROL — the provenance half, armed on its own ────────────────────────────────────────
  # Control 1's forced definition sits INSIDE a submodule, and this engine's provenance stops at the
  # declared leaf `hosts` (nested evaluations are a documented provenance boundary), so what control
  # 1 moves is the DEF COUNT at the same priority. This seed is the only one that changes a priority
  # VALUE, introducing 50 at a TOP-LEVEL declared leaf (`fleet.size`, winning priority 100 → 50).
  # Adding a def and changing a priority are not the same event, and a channel half that records the
  # winner's priority is not exercised by a cell that only ever adds peers at 100.
  ovProvSeed = ovBase.override {
    modules = [
      addN3
      { config.fleet.size = mkForce 9; }
    ];
  };

  # ── RED CONTROL 2 — inside the comparator's own blind class (H1) ────────────────────────────────
  # Two composes differing ONLY in the closure a function-valued leaf resolves to. Both sides are
  # functions — a function↔data flip is a change the walk DOES catch and would test the wrong thing.
  #
  # ★ THE EXPECTED READING IS GREEN, AND GREEN IS THE REFUSAL BRANCH: the nulling is total, both
  # halves are byte-equal, so the byte-parity oracle does NOT discharge for function-valued content
  # by this comparator. A RED here is an INSTRUMENT FINDING, never a pass: it would mean the seed
  # leaked. The seed-integrity cells exist so that a green cannot be read without them.
  c2a = compose { modules = mkBase (x: x + 1); };
  c2b = compose { modules = mkBase (x: x + 2); };

  # ── the admission key, exercised from the refusing side ────────────────────────────────────────
  # An edit carrying `specialArgs` must NOT warm-fire — the fail-unsound direction is a warm pass for
  # an edit that changed an argument the splice assumes fixed — so it takes the engine's cold path
  # and the trace says so, with the reason.
  ovColdEdit = ovBase.override {
    specialArgs = {
      seeded = true;
    };
  };

  # ── the engineArgs collision guard, seeded per owned key ───────────────────────────────────────
  # One seed per compose-owned key; the non-colliding control keeps four reds from being a guard
  # that fires on everything.
  guardFires = c: !(builtins.tryEval (builtins.seq c.values true)).success;
  # Each seed's value is what the key would carry legitimately, so only the guard can throw.
  guardSeed =
    k: v:
    compose {
      modules = base;
      engineArgs = {
        ${k} = v;
      };
    };

  # ── the cycle fixtures (formerly gen-memo's error plane) ────────────────────────────────────────
  # A non-option-type self-cycle and two MUTUAL cycles between DISTINCT attrsets, each injected
  # through a `types.raw` leaf the way `hooks.ty` injects the option-type one, and run through the
  # real successor compose. Kept out of `armWarm`/`armCold`: a value that can abort the walk would
  # take down every cell that calls `image`. The two mutual fixtures share their tags and differ
  # ONLY in `b`'s attribute count, which isolates WHEN the ancestor scan's `==` terminates.
  plainCycle =
    let
      self = {
        tag = "plain-cycle";
        ref = self;
      };
    in
    self;
  mutual =
    extraB:
    let
      a = {
        tag = "same";
        ref = b;
      };
      b = {
        tag = "same";
        ref = a;
      }
      // extraB;
    in
    a;
  leafDecls.options.leaf = mkOption {
    type = types.raw;
    default = null;
  };
  withLeaf =
    v:
    compose {
      modules = [
        leafDecls
        { config.leaf = v; }
      ];
    };
  subject = withLeaf plainCycle;
  subjectMutualSame = withLeaf (mutual { });
  subjectMutualWider = withLeaf (mutual {
    side = "b";
  });

  cells = {
    # ---- R1: one revision of each engine in this evaluation ----------------------------------------
    # gen-merge's published `lib` is built over its OWN gen-memo input; the root lock's `follows`
    # sends that onto the hub's gen-memo. Were it cut, the engine would carry a second gen-memo
    # while `compose` hands it the hub's `warmAdmits`/`warmTrace`.
    r1-engine-reads-the-hub-memo = {
      expr = gen.inputs.gen-merge.inputs.gen-memo.rev;
      expected = gen.inputs.gen-memo.rev;
    };

    # ---- the decision path is live -------------------------------------------------------------
    compose-parity.test-warm-fires-through-the-migrated-predicate = {
      expr = armWarm.trace.mode;
      expected = "warm";
    };
    # The splice actually reused locs; a "warm" mode over an empty reuse set would be a warm label on
    # a cold evaluation and the parity cells below would pass for the wrong reason.
    compose-parity.test-warm-reuses-the-untouched-locs = {
      expr = armWarm.trace.reused;
      expected = [
        "fleet.name"
        "fleet.size"
        "hooks"
      ];
    };
    compose-parity.test-base-carries-no-trace = {
      expr = ovBase ? trace;
      expected = false;
    };

    # ---- §3.1's two arms ------------------------------------------------------------------------
    compose-parity.test-cold-parity-values = {
      expr = (image armWarm).values;
      expected = (image armCold).values;
    };
    compose-parity.test-cold-parity-provenance = {
      expr = (image armWarm).provenance;
      expected = (image armCold).provenance;
    };

    # ---- the comparator's two hedges are LIVE on this subject ------------------------------------
    # The cut fired, functions were nulled, and a token that is not there reads absent — the last
    # keeps the first two from being a zero out of a predicate that could not have matched. The
    # FUNCTION leaf specifically: a bare `null` count cannot read false here, since most of the
    # image's nulls do not come from a function.
    compose-parity.test-control-comparator-hedges-are-live = {
      expr = {
        cycleCutFired = countIn "<cycle:" (image armWarm).values > 0;
        functionsNulled = countIn "\"transform\":null" (image armWarm).values > 0;
        absentTokenReadsZero = countIn "qzwvxk" (image armWarm).values == 0;
      };
      expected = {
        cycleCutFired = true;
        functionsNulled = true;
        absentTokenReadsZero = true;
      };
    };

    # ---- the RED controls -----------------------------------------------------------------------
    compose-parity.test-control-ordinary-leaf-moves-values = {
      expr = (image ovDiffering).values != (image armWarm).values;
      expected = true;
    };
    compose-parity.test-control-added-def-moves-provenance = {
      expr = (image ovProvSeed).provenance != (image armWarm).provenance;
      expected = true;
    };

    # ---- the H1 blindness probe, with its seed integrity asserted first -------------------------
    compose-parity.test-control-h1-seed-is-a-function-on-both-sides = {
      expr =
        builtins.isFunction c2a.values.hooks.transform && builtins.isFunction c2b.values.hooks.transform;
      expected = true;
    };
    compose-parity.test-control-h1-seed-carries-two-different-functions = {
      expr = c2a.values.hooks.transform 1 != c2b.values.hooks.transform 1;
      expected = true;
    };
    compose-parity.test-control-h1-seed-holds-provenance-fixed = {
      expr = (image c2a).provenance;
      expected = (image c2b).provenance;
    };
    # The reading. GREEN — the two images are equal — is the PREDICTED outcome and the refusal.
    compose-parity.test-control-h1-blind-class-reads-green = {
      expr = (image c2a).values == (image c2b).values;
      expected = true;
    };

    # ---- the admission key is pinned (the refusing half; the warm half is the arm) --------------
    compose-parity.test-admission-wider-edit-refuses-warm = {
      expr = ovColdEdit.trace.mode;
      expected = "cold";
    };
    compose-parity.test-admission-refusal-states-its-reason = {
      expr = ovColdEdit.trace.reason;
      expected = "no warmFrom (cold)";
    };

    # ---- the engineArgs collision guard bites, once per owned key -------------------------------
    compose-parity.test-guard-refuses-engineargs-modules = {
      expr = guardFires (guardSeed "modules" [ ]);
      expected = true;
    };
    compose-parity.test-guard-refuses-engineargs-specialargs = {
      expr = guardFires (guardSeed "specialArgs" { });
      expected = true;
    };
    compose-parity.test-guard-refuses-engineargs-warmfrom = {
      expr = guardFires (guardSeed "warmFrom" null);
      expected = true;
    };
    compose-parity.test-guard-refuses-engineargs-editedmodules = {
      expr = guardFires (guardSeed "editedModules" [ ]);
      expected = true;
    };
    # The paired non-colliding call: a legal engine key rides through the splice and the guard
    # stays quiet — the eval completes and the values read.
    compose-parity.test-control-engineargs-noncolliding-passes = {
      expr =
        (compose {
          modules = base;
          engineArgs = {
            check = true;
          };
        }).values.fleet.name;
      expected = "prod";
    };

    # ---- the non-option-type self-cycle cuts ------------------------------------------------------
    # LIVE CONTROL — the fixture is genuinely self-referential before anything walks it; `==` on
    # attrsets short-circuits on pointer identity, so this reads cheaply.
    non-option-cycle.test-control-fixture-is-a-genuine-self-reference = {
      expr = {
        selfReferential = subject.values.leaf.ref == subject.values.leaf;
        inherit (subject.values.leaf) tag;
      };
      expected = {
        selfReferential = true;
        tag = "plain-cycle";
      };
    };
    # `self` is pushed onto `seen` the first time it is walked and the revisit through `self.ref` is
    # caught at index 0, the innermost (and only) attrs ancestor.
    non-option-cycle.test-nonoption-type-cycle-cuts = {
      expr = builtins.toJSON (dropFns subject.values);
      expected = builtins.toJSON {
        leaf = {
          tag = "plain-cycle";
          ref = "<cycle:0>";
        };
      };
    };

    # ---- the mutual-cycle residual ---------------------------------------------------------------
    # LIVE CONTROL — the same-tag fixture is a genuine 2-cycle between DISTINCT attrsets that
    # SURVIVED the compose pipeline, asserted WITHOUT a deep compare of `a` against `b` (that compare
    # is the pathology `overflowPin` measures): `leaf.ref.ref` loops back to the SAME thunk as `leaf`.
    mutual-cycle.test-control-same-tag-fixture-is-a-genuine-mutual-cycle = {
      expr = {
        loopsBack = subjectMutualSame.values.leaf.ref.ref == subjectMutualSame.values.leaf;
        outerTag = subjectMutualSame.values.leaf.tag;
        innerTag = subjectMutualSame.values.leaf.ref.tag;
      };
      expected = {
        loopsBack = true;
        outerTag = "same";
        innerTag = "same";
      };
    };
    # THE COUNTEREXAMPLE THAT PROVES THE PIN IS NARROW: the pinned fixture with ONE attribute added
    # to `b`. `==` on attrsets of different sizes is false before any element is compared, so the
    # scan rejects `b` against `a` at once and the walk completes, `b`'s `ref` revisiting `a`, the
    # OUTER ancestor (index 1). It controls that the overflow belongs to an ancestor compare that
    # must RECURSE, not to every mutual cycle.
    # ★ THE COUNT DIFFERS, NOT A TAG, AND THAT IS THE POINT. The gen-memo form differed in `tag`
    # and terminated only when `tag` was compared before `ref` — attrset `==` walks attributes in
    # symbol-interning order, so the verdict was a fact about what the host had interned first. It
    # read green in gen-memo's plane and overflowed here under all three evaluators. The size check
    # precedes every element compare, so this reading does not depend on the host.
    mutual-cycle.test-control-mutual-cycle-diff-count-terminates = {
      expr = builtins.toJSON (dropFns subjectMutualWider.values);
      expected = builtins.toJSON {
        leaf = {
          tag = "same";
          ref = {
            side = "b";
            tag = "same";
            ref = "<cycle:1>";
          };
        };
      };
    };
  };

  # Flattened to `<group>.<cell>` keys, so the check names a failing cell the way the retired suite
  # did.
  flat = builtins.foldl' (
    acc: g:
    acc
    // (
      if cells.${g} ? expr then
        { ${g} = cells.${g}; }
      else
        builtins.listToAttrs (
          map (c: {
            name = "${g}.${c}";
            value = cells.${g}.${c};
          }) (builtins.attrNames cells.${g})
        )
    )
  ) { } (builtins.attrNames cells);
  gate = builtins.mapAttrs (_: c: c.expr == c.expected) flat;
in
{
  inherit gate;
  gateKeys = builtins.attrNames gate;

  # THE PIN, read across a process boundary (see the header). The ancestor scan compares `b` against
  # `a` by `==`; both carry the same `tag`, so the compare recurses into `ref` — `a` and `b` pointing
  # at each other — until the evaluator overflows, and the overflow passes THROUGH `tryEval`. GREEN
  # is `nix eval` of this attribute failing with `stack overflow`; a value, or any other error, is
  # red. The `tryEval` makes "uncaught" part of the reading: an evaluator that caught the overflow
  # would return `{ success = false; }` and the eval would exit 0.
  overflowPin = builtins.tryEval (builtins.toJSON (dropFns subjectMutualSame.values));

  report = {
    governs = "the successor compose as published (`gen.lib.compose`): warm ≡ cold on values and provenance, with the comparator's hedges and the collision guard";
    revisions = {
      gen-merge = gen.inputs.gen-merge.rev;
      gen-memo = gen.inputs.gen-memo.rev;
    };
  };
}
