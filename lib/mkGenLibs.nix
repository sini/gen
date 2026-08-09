# mkGenLibs: two-stage instantiation of the gen library ecosystem.
#
# Stage 1 (definition time): captures genInputs (the gen-* flake inputs).
# Stage 2: each lib is self-wired — every gen flake exposes a `.lib` value that
# resolves its own deps internally (gen-schema owns its gen-algebra input, etc.),
# so the hub just re-exports `genInputs.gen-X.lib`. The `lib` arg is now vestigial
# (real consumers read `inputs.gen-X.lib` directly); kept as `_` for call-compat.
#
# The roster is bound ONCE, at stage 1, and every stage-2 application yields that same value.
# Nineteen members are already shared across applications by input memoization; `class` is not,
# because it is an `import` the hub applies itself — bound per application it re-allocates, and two
# routes to "the roster" then hold two evaluations of the same source rather than one value. The
# stratum buckets select on that identity, so the roster has to be a value and not a recipe.
{ genInputs }:
let
  roster = {
    prelude = genInputs.gen-prelude.lib;
    algebra = genInputs.gen-algebra.lib;
    types = genInputs.gen-types.lib;
    merge = genInputs.gen-merge.lib;
    scope = genInputs.gen-scope.lib;
    graph = genInputs.gen-graph.lib;
    bind = genInputs.gen-bind.lib;
    schema = genInputs.gen-schema.lib;
    aspects = genInputs.gen-aspects.lib;
    select = genInputs.gen-select.lib;
    dispatch = genInputs.gen-dispatch.lib;
    resolve = genInputs.gen-resolve.lib;
    flake = genInputs.gen-flake.lib;
    # L2 concern libraries — each flake `.lib` self-resolves its own deps (edge: prelude+graph;
    # product: prelude; settings: prelude+algebra+bind+graph; demand: prelude+graph; pipe:
    # prelude+select+scope), so the hub re-exports them plainly like the self-wiring libs above.
    edge = genInputs.gen-edge.lib;
    product = genInputs.gen-product.lib;
    settings = genInputs.gen-settings.lib;
    demand = genInputs.gen-demand.lib;
    pipe = genInputs.gen-pipe.lib;
    # gen-link is Class B: its flake `.lib` self-resolves its own gen siblings, so the hub re-exports it
    # plainly like the other self-wiring libs.
    link = genInputs.gen-link.lib;
    # gen-class is Class B: prelude required, merge injected for the tier-2 fixed-input path. Unlike the
    # self-wiring libs above (each resolves its own deps), gen-class's flake `.lib` leaves merge = null, so
    # the hub re-imports its ./lib with the tier-2 kernel injected — mkGenLibs.class carries applyCoreFixed.
    class = import "${genInputs.gen-class}/lib" {
      prelude = genInputs.gen-prelude.lib;
      merge = genInputs.gen-merge.lib;
    };

    # The stratum declaration — which layer of the stack each member belongs to. It is TOTAL and
    # EXPLICIT: a member with no entry here is a build error, never a member of an implicit residue
    # bucket. A defaulted stratum would let a new library join the roster and land silently in
    # whatever bucket the default names, so a missing declaration would read as a design choice
    # nobody made. Adding a roster member is therefore two lines — the binding above and the
    # stratum here — in the same commit, exactly as the ci roster tripwire already requires.
    #
    #   substrate  the base layer: values, graphs, selection, evaluation
    #   modules    the module system: the checking half and the merging half
    #   aspects    the aspect layer, built on the module system
    #   framework  above the stack rather than a layer of it — a configuration framework assembles
    #              with this, and no substrate vocabulary may be defined in its terms
    #   retiring   on the roster and leaving it: its content is moving to another member, so it is
    #              still reachable but no consumer should newly adopt it
    #
    # `substrate`, `modules` and `aspects` publish consumer paths on the hub's `lib` output
    # (flake.nix). `framework` and `retiring` publish none — they are facts about the roster, and
    # their members stay reachable exactly where they are today, on the flat roster.
    strata = {
      prelude = "substrate";
      algebra = "substrate";
      types = "modules";
      merge = "modules";
      scope = "substrate";
      graph = "substrate";
      bind = "substrate";
      schema = "substrate";
      aspects = "aspects";
      select = "substrate";
      dispatch = "substrate";
      resolve = "retiring";
      flake = "retiring";
      edge = "retiring";
      product = "substrate";
      settings = "framework";
      demand = "retiring";
      pipe = "retiring";
      link = "aspects";
      class = "aspects";
    };
  };
in
_: roster
