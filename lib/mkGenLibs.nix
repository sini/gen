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
    # L2 concern libraries — each flake `.lib` self-resolves its own deps (product: prelude;
    # settings: prelude+algebra+bind+graph), so the hub re-exports them plainly like the
    # self-wiring libs above.
    #
    # THREE MEMBERS OF THIS BLOCK ARE OFF THE ROSTER, each by a ruling and each with its content
    # landed somewhere else. The bindings are gone rather than commented out — a `retiring` member
    # is still reachable and this is the state past that, where the hub no longer pins the input at
    # all — but the rulings are recorded here because the roster is where a reader asks "why is
    # there no `edge` key?" and an unanswered absence reads as a drop.
    #
    #   gen-demand  ADR-0008 §4 retires it as a library; its cascade re-expresses over gen-scope,
    #               the sole evaluator (ADR-0006).
    #   gen-edge    ADR-0010 §3 retires the content-movement contract into the movement vocabulary;
    #               its (S,T,P,M) algebra, edge-set derivation and Kahn-ordered materialization
    #               landed in `view` (the fourth destination §3 gained on 2026-08-20) alongside
    #               `select`, `graph` and `scope`. Its edge trace was the oracle that validated the
    #               spec retiring it, so it retired last, after movement AC-7 ran.
    #   gen-pipe    ADR-0010 §3, same retirement: scoped channels and the dataflow algebra over
    #               them re-express as `view` constructs, `sel` binds `select` directly, and the
    #               B5 determinism/provenance laws are restated as properties of the query
    #               construction rather than lost.
    #
    # All three repositories stay readable, orphaned for reference under ADR-0031 F3 — no content
    # is deleted — and none of them gains a new consumer.
    product = genInputs.gen-product.lib;
    settings = genInputs.gen-settings.lib;
    # gen-link is Class B: its flake `.lib` self-resolves its own gen siblings, so the hub re-exports it
    # plainly like the other self-wiring libs.
    link = genInputs.gen-link.lib;
    # ★★ TEMPORARY / WAY-STATION, and the marking is load-bearing rather than a note. The owner ruled
    # the name PROVISIONAL: "keep gen-view for now; we're going to fold its constructs into a
    # consolidated library later; gen-view is a temporary name." The CONSTRUCTS migrate at the
    # survivor consolidation; the CONTAINER does not. ⇒ NO CONSUMER SHOULD ADOPT THIS CONTAINER AS A
    # STABLE HOME, and the marking travels with every citation of the name.
    #
    # ★ TEMPORARY IS NOT THROWAWAY, and the distinction is the owner's own: "it should still be
    # grounded -- the lib will be a sublibrary of a larger domain library." The name DESCENDS INTO A
    # NAMESPACE rather than dissolving, which is why that library grounds its terms at a primary
    # instead of deferring them — and why this is a way-station rather than a `retiring` member.
    # `retiring` names a library whose content is moving OUT to an existing member and which no
    # consumer should newly adopt; this one's content is moving DOWN into a library that does not
    # exist yet, and it is the live home in the meantime.
    #
    # Self-wiring like the block above: its flake `.lib` resolves its own gen-prelude and gen-graph.
    view = genInputs.gen-view.lib;
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
    #              reference rather than deleted. That end has now been reached three times:
    #              gen-demand (ADR-0008 §4) was the first, and gen-edge and gen-pipe walked it
    #              together on ADR-0010 §3 once their content landed in `view`. The value is not
    #              a waiting room — a member sits here only while its destination is still being
    #              built, and `flake` and `resolve` are what remains of that
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
      product = "substrate";
      settings = "framework";
      assemble = "framework";
      link = "aspects";
      class = "aspects";
      # ★ OWNER-RULED. gen-view is the FOURTH DESTINATION of the same retirement that sends gen-pipe
      # and gen-edge into S1 vocabulary — alongside select, graph and scope, which are substrate —
      # so it takes their bucket. ★★ AND THE DECLARATION IS WHY THE ROW MAY EXIST AT ALL: under
      # ADR-0015 as amended a member with no stratum takes `strata-total` FALSE and names itself, so
      # a way-station could not enter this roster before its stratum was ruled. The TEMPORARY marking
      # is on the binding above and is about the NAME, never about the layer: a way-station sits in a
      # real layer while it stands, and `retiring` is not that marking — see the binding for why.
      view = "substrate";
    };
  };
in
_: roster
