# mkGenLibs: the hub's `lib/` — the roster, built from resolved member VALUES.
#
# ★★★ THIS FILE IS A CONSUMER OF THE PATTERN, NOT AN EXCEPTION TO IT (owner-ruled 2026-09-14):
# "`mkGenLibs` stops being a fixed point and becomes a CONSUMER of the same pattern every member
# follows: L3 applies to the hub." It takes named, REQUIRED dependency values keyed by the roster's
# own names — the module-layout pattern's L2 shape, identical to every member's `lib/default.nix` —
# and `../default.nix` is the L1 shim that defaults them, exactly as a member's root defaults its own.
#
# WHAT THAT REPLACED, AND WHY THE OLD SHAPE COULD NOT SURVIVE THE MIGRATION. This file used to take
# the gen-* flake inputs and reach each member as `<input>.gen-X.lib`. After the migration a
# plain-re-export member and an unapplied-arm member have the SAME root shape, a function of
# defaulted formals, so arity cannot tell them apart; yet this file demanded opposite things from
# them, an applied SET at its re-export sites and an unapplied FUNCTION at the two it applied.
# Neither single form is total over both, and the two failures are
# `attempt to call something which is not a function but a set` and
# `expected a set but found a function`. Taking VALUES dissolves it: whoever supplies a member
# resolves it, and ONE construction then serves both suppliers — `flake.nix` from the hub's own
# inputs under `follows`, `../default.nix` from the root `flake.lock`.
#
# A MISSING MEMBER IS LOUD BY CONSTRUCTION, which is what retired the old `input` helper. That
# helper existed to turn an uncatchable missing-attribute abort into a named, catchable `throw`. A
# formal needs no such conversion and is stronger: there is no `...` here, so a supplier that omits
# a member fails with `called without required argument`, NAMING it, and one that passes a name this
# file does not declare fails with `called with unexpected argument` instead of dropping it silently.
#
# THE TWO-STAGE PUBLISHED SURFACE LIVES IN `flake.nix`, NOT HERE. `gen.lib.mkGenLibs` keeps its
# vestigial argument for its consumers; this file is the roster's construction and returns the
# roster itself, so `import <gen> { }` yields it directly.
#
# ★ SELF-WIRED IS ABOUT WHO EVALUATES, NEVER ABOUT WHICH REVISION, and the two were once one
# sentence here. The hub's `flake.nix` binds every sibling's `gen-*` input with `follows`, so
# gen-schema still owns and resolves its gen-algebra input — against the HUB's gen-algebra, which it
# no longer chooses. Each member stays authoritative over its wiring and the hub is authoritative
# over the closure. Before those edges this re-export returned a DIFFERENT BUILD per path while
# reading as one value: 11 of the 21 libraries stood at more than one revision, gen-prelude at 9.
#
# The roster is a VALUE and not a recipe, and the stratum buckets select on that identity. Every
# member now arrives already resolved, so the two sites that used to re-import a member's `./lib`
# here — and therefore re-allocated it per application — are gone with the hand-written dep lists
# they carried.
{
  algebra,
  aspects,
  assemble,
  bind,
  class,
  delivery,
  dispatch,
  graph,
  identity,
  inspect,
  link,
  memo,
  merge,
  prelude,
  product,
  program,
  schema,
  scope,
  select,
  settings,
  types,
  view,
}:
let
  roster = {
    inherit prelude;
    # Self-contained: no inputs, so nothing to wire. The one minting authority
    # (ADR-0016 ruling 5) as a dependency-free leaf — which is what lets libraries UPSTREAM of
    # gen-schema reach it without closing a flake cycle, the whole reason it is its own library.
    inherit identity;
    inherit algebra;
    inherit types;
    inherit merge;
    inherit scope;
    # gen-memo is the INCREMENTAL PLANE over the evaluator above it (ADR-0008 §2): a decision layer
    # that never evaluates, defined by byte-parity against a cold evaluation. It sits beside `scope`
    # here because that is what it is a plane over, and it is self-wiring like the rest of this
    # block — its flake `.lib` resolves its own gen-prelude and gen-graph.
    inherit memo;
    inherit graph;
    # gen-inspect INTERROGATES a materialized graph: which nodes exist and of what kind, which edges
    # are declared, which a policy program produced and WHY, and what reaches what. It publishes its
    # `.lib` UNAPPLIED and takes its substrate injected, so the hub wires it through
    # `./hubSubstrate.nix` rather than re-exporting a self-resolved `.lib` — the fourth member that
    # file names. It implements no semantics and never evaluates: every fixpoint goes through
    # gen-scope, the sole evaluator (ADR-0006), and this library reads a model that evaluator already
    # produced. Entry landed when content existed, per the ruled roster timing.
    inherit inspect;
    inherit bind;
    inherit schema;
    inherit aspects;
    inherit select;
    inherit dispatch;
    # L2 concern libraries — each flake `.lib` self-resolves its own deps (product: prelude;
    # settings: prelude+algebra+bind+graph), so the hub re-exports them plainly like the
    # self-wiring libs above.
    #
    # ★ THE DELETION-GROUND RULE, RESTATED AT THE POINT REMOVAL EXECUTES (P7, owner-ruled
    # 2026-08-17): for any reference-grade member still on this roster, a usage count is
    # inadmissible as a deletion ground — dropping a binding here needs a domain argument (wrong
    # abstraction, subsumed, theory-unsound), exactly as the five removals below needed a named
    # ruling rather than a citation count.
    #
    # FIVE MEMBERS OF THIS BLOCK ARE OFF THE ROSTER, each by a ruling. The bindings are gone rather
    # than commented out — a `retiring` member is still reachable and this is the state past that,
    # where the hub no longer pins the input at all — but the rulings are recorded here because the
    # roster is where a reader asks "why is there no `edge` key?" and an unanswered absence reads as
    # a drop.
    #
    # WHAT LEAVES WITH A MEMBER IS ITS OBLIGATIONS, and they go to a NAMED DESTINATION or they are
    # DISSOLVED WITH A REASON — owner-ruled 2026-09-02: "any obligations of a retired/retiring
    # library transfer to their replacement -- if it's not relevant then the obligation dissolves
    # and can be closed." The first four below leave with their CONTENT already landed elsewhere,
    # which is the stronger case rather than the general one; a member may also leave on the
    # transfer alone, its surface dispositioned row by row. Either way removal is not deletion:
    # every repository below stays readable and keeps its surface.
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
    #   gen-flake   ADR-0031 F2 dissolves it; every surface landed at a successor — compose S2
    #               core at this hub's `lib.compose` / interim flakeModule, warm/override/trace
    #               in gen-memo, projection + realize in gen-delivery, inject/terminals at the
    #               crossing's Adapter set. Its repo orphans as reference per F3 (diff.nix stays
    #               there by explicit ruling).
    #   gen-resolve ADR-0008 §4 retires it as a library, and it leaves on the TRANSFER above rather
    #               than on a completed content move: its published exports are dispositioned ROW
    #               BY ROW — `view` takes the materialization vocabulary and the reference
    #               construct, `bind` the crossing terminal, `scope` the seal-level queries, `memo`
    #               the reuse key, two dissolve by ruling (`attr`, `cascade`), and two of the
    #               transfers still ride an open successor (`nta`, and `reference`'s `neededBy`
    #               reverse arm). THE ROW-BY-ROW MAP IS den-hoag-p3y9; the 2026-08-15 sitting that
    #               dispositioned the ELEVEN is den-hoag-8skr.
    #               ★ `_buildSchedule` AND `_scheduleWith` ARE NOT AMONG THAT ELEVEN AND THIS
    #               ROSTER ASSERTS NO DESTINATION FOR THEM. den-hoag-8skr HELD THEM OUT
    #               deliberately — they travel with the static-schedule phase, which engine-spec
    #               R§1.2 sequences OUT — so it is not authority for placing them anywhere. The
    #               owner ruled their home on 2026-08-11 (den-hoag-ui5c OPEN 4(a), normative at
    #               engine-spec R§5.2) and that ruling REJECTED `scope`, which was arm 4(b); an
    #               earlier form of this row asserted `scope` anyway, on 8skr's authority. THE
    #               MEMBER THAT INSTANTIATES THE RULED HOME IS `view`, owner-ruled 2026-09-09: the
    #               static Knuth gate landed in gen-view as `boundedWellDefinedSchedule`, a query
    #               over gen-graph's contracted declared relation —
    #               den-hoag-roster-wrong-schedule-destination-cbpfc, whose residue (b) carries the
    #               ruling and the landing. gen-scope's own
    #               lib/fold-equations.nix agrees it is not the builder: the schedule arrives
    #               there validated.
    #
    # All five repositories stay readable, orphaned for reference under ADR-0031 F3 — no content
    # is deleted — and none of them gains a new consumer.
    inherit product;
    inherit settings;
    # gen-link is Class B: its flake `.lib` self-resolves its own gen siblings, so the hub re-exports it
    # plainly like the other self-wiring libs.
    inherit link;
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
    inherit view;

    # gen-program turns a framework's policy declarations into a PROGRAM and reaches the solver
    # (gen-scope engine.solve). ADJACENT to the assembly layer, never inside it: gen-assemble's own
    # published principle is "The toolkit never evaluates", and this library's ruled purpose is to
    # evaluate through the sole evaluator (owner-ruled; policy spec R§2.11, O8). Entry landed when
    # content existed, per the ruled roster timing.
    inherit program;
    # gen-delivery is the DELIVERY-CLASS REALIZATION SURFACE (ADR-0028): the projection that
    # discovers which aspect keys are declared delivery classes and the fold that hands each
    # class's collected content to its target-owned terminal. Like gen-assemble and gen-program it
    # publishes its `.lib` UNAPPLIED and takes its substrate injected, so the hub wires it rather
    # than re-exporting a self-resolved `.lib` — see `./hubSubstrate.nix`, which names exactly these
    # three. It DOES declare flake inputs (owner-ruled Arm A, 2026-09-16: `den-hoag-4dfsv` §4.2), so
    # a consumer taking this input DOES gain a transitive pin; what it does not gain is an APPLIED
    # substrate, which is the distinction the unapplied root exists to hold. Entry landed when
    # content existed, per the ruled roster timing.
    inherit delivery;
    # gen-class is Class B: prelude required, merge injected for the tier-2 fixed-input path. Unlike the
    # self-wiring libs above (each resolves its own deps), gen-class's flake `.lib` leaves merge = null, so
    # the hub re-imports its ./lib with the tier-2 kernel injected — mkGenLibs.class carries applyCoreFixed.
    inherit class;

    # gen-assemble publishes its root UNAPPLIED: the shared framework toolkit takes its whole
    # substrate as injected values and constructs inside the consumer's own evaluation, which is what
    # the gen↔gen boundary rule asks of a library that composes another's constructor. So the hub
    # wires it the way it wires gen-class rather than re-exporting a self-resolved `.lib`. It DOES
    # declare flake inputs (owner-ruled Arm A, 2026-09-16: `den-hoag-4dfsv` §4.2) — the unapplied root
    # withholds an APPLIED substrate from a consumer, never the transitive pin.
    inherit assemble;

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
    #              removal from the roster once every obligation the member carries has a named
    #              destination or a stated dissolution — the member drops both lines and the hub
    #              stops pinning it, and its repository is orphaned for reference rather than
    #              deleted. That end has now been reached five times: gen-demand (ADR-0008 §4) was
    #              the first, gen-edge and gen-pipe walked it together on ADR-0010 §3 once their
    #              content landed in `view`, gen-flake completed it under ADR-0031 once its
    #              surfaces dissolved to their successors, and gen-resolve left on the 2026-09-02
    #              transfer ruling with its exports dispositioned row by row (see the block above).
    #              The value is not a waiting room — a member sits here only while that
    #              disposition is still being settled, and no member sits here today.
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
      product = "substrate";
      settings = "framework";
      assemble = "framework";
      program = "framework";
      # ★ The bucket turns on what the surface DOES. gen-inspect is a thing a person and a framework
      # plug INTO an assembled graph to interrogate it — "above the stack rather than a layer of it"
      # on the bucket's own words. It defines no substrate vocabulary in its own terms, which is the
      # bucket's second clause, and ADR-0035 conformance is asserted by its own CI.
      inspect = "framework";
      # ★ OWNER-RULED. The bucket turns on what the surface DOES, and this one is a thing
      # frameworks plug into: it realizes delivery targets by invoking a caller-supplied terminal,
      # which is "above the stack rather than a layer of it" on the bucket's own words. Putting the
      # fold that calls a terminal INSIDE the aspect layer would make S3 name delivery.
      delivery = "framework";
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
roster
