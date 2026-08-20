# mkGenLibs: two-stage instantiation of the gen library ecosystem.
#
# Stage 1 (definition time): captures genInputs (the gen-* flake inputs).
# Stage 2: each lib is self-wired — every gen flake exposes a `.lib` value that
# resolves its own deps internally (gen-schema owns its gen-algebra input, etc.),
# so the hub just re-exports `genInputs.gen-X.lib`. The `lib` arg is now vestigial
# (real consumers read `inputs.gen-X.lib` directly); kept as `_` for call-compat.
#
# The roster is bound ONCE, at stage 1, and every stage-2 application yields that same value.
# Every member but `class` is already shared across applications by input memoization; `class` is not,
# because it is an `import` the hub applies itself — bound per application it re-allocates, and two
# routes to "the roster" then hold two evaluations of the same source rather than one value. The
# stratum buckets select on that identity, so the roster has to be a value and not a recipe.
{ genInputs }:
let
  roster = {
    prelude = genInputs.gen-prelude.lib;
    # Self-contained: no inputs, so nothing to wire. The one minting authority
    # (ADR-0016 ruling 5) as a dependency-free leaf — which is what lets libraries UPSTREAM of
    # gen-schema reach it without closing a flake cycle, the whole reason it is its own library.
    identity = genInputs.gen-identity.lib;
    algebra = genInputs.gen-algebra.lib;
    types = genInputs.gen-types.lib;
    merge = genInputs.gen-merge.lib;
    scope = genInputs.gen-scope.lib;
    # gen-memo is the INCREMENTAL PLANE over the evaluator above it (ADR-0008 §2): a decision layer
    # that never evaluates, defined by byte-parity against a cold evaluation. It sits beside `scope`
    # here because that is what it is a plane over, and it is self-wiring like the rest of this
    # block — its flake `.lib` resolves its own gen-prelude and gen-graph.
    memo = genInputs.gen-memo.lib;
    graph = genInputs.gen-graph.lib;
    bind = genInputs.gen-bind.lib;
    schema = genInputs.gen-schema.lib;
    aspects = genInputs.gen-aspects.lib;
    select = genInputs.gen-select.lib;
    dispatch = genInputs.gen-dispatch.lib;
    resolve = genInputs.gen-resolve.lib;
    flake = genInputs.gen-flake.lib;
    # L2 concern libraries — each flake `.lib` self-resolves its own deps (edge: prelude+graph;
    # product: prelude; settings: prelude+algebra+bind+graph; pipe: prelude+select+scope), so the
    # hub re-exports them plainly like the self-wiring libs above. gen-demand was one of these and
    # is off the roster: ADR-0008 §4 retires it as a library and its cascade re-expresses over
    # gen-scope, the sole evaluator (ADR-0006). The repository stays readable, orphaned for
    # reference, and gains no new consumers.
    edge = genInputs.gen-edge.lib;
    product = genInputs.gen-product.lib;
    settings = genInputs.gen-settings.lib;
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

    # gen-assemble declares NO inputs at all: the shared framework toolkit takes its whole substrate
    # as injected values and constructs inside the consumer's own evaluation, which is what the
    # gen↔gen boundary rule asks of a library that composes another's constructor. So the hub wires
    # it the way it wires gen-class rather than re-exporting a self-resolved `.lib` — and a consumer
    # taking this input gains no transitive pin from it.
    assemble = import "${genInputs.gen-assemble}/lib" {
      prelude = genInputs.gen-prelude.lib;
      scope = genInputs.gen-scope.lib;
      algebra = genInputs.gen-algebra.lib;
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
    #              still reachable but no consumer should newly adopt it. The end of that path is
    #              removal from the roster once the content has landed — the member drops both
    #              lines and the hub stops pinning it, and its repository is orphaned for
    #              reference rather than deleted (gen-demand, ADR-0008 §4, is the first)
    #
    # `substrate`, `modules`, `aspects` and `framework` publish consumer paths on the hub's `lib`
    # output (flake.nix). `retiring` publishes none: a consumer selecting a library on its way off
    # the roster is the adoption that value exists to prevent, and its members stay reachable on the
    # flat roster through `mkGenLibs`.
    strata = {
      prelude = "substrate";
      # ADR-0016 ruling 5 assigned this concern to the SUBSTRATE in the sentence that created it —
      # "the substrate refuses rather than inventing an identity" — so extracting the code into its
      # own library relocated the code and not the assignment. It also fits the bucket's own gloss:
      # a total function from an inert value to a string, carrying no module-system, aspect or
      # framework notion. Its consumers span four buckets, which is what a base-layer library looks
      # like from above.
      identity = "substrate";
      algebra = "substrate";
      types = "modules";
      merge = "modules";
      scope = "substrate";
      memo = "substrate";
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
      assemble = "framework";
      pipe = "retiring";
      link = "aspects";
      class = "aspects";
    };
  };
in
_: roster
