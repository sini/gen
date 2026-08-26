# `compose` — the successor compose: the S2 core that survives gen-flake's dissolution
# (ADR-0031 F2's "compose S2 core → S2" row). One construct: the engine invocation, the warm-knob
# splice, the re-compose merge law, the recursion, the collision guard, and the values/provenance
# projection. The DECISION half of the warm path lives in gen-memo (`warmAdmits`/`warmTrace`);
# this is the CALL half.
#
# THE CONSTRUCT BINDS NO CONSTRUCTOR VOCABULARY, AND `specialArgs` IS CALLER-TOTAL. ADR-0011's
# strata place the aspect layer above the module system; a construct that composes a tree it is
# HANDED cannot hold that tree's vocabulary set — which libraries a tree's modules need is a fact
# about the tree, not about the invoker. So no `genAspects`/`genSchema`/`genTypes`/`genPrelude`
# constant lives here: the caller supplies `specialArgs` whole and this construct merges nothing
# into it. The injection pattern survives one level up, at the framework surface that fronts the
# tree (the hub flakeModule performs `genLibs // specialArgs` as its own act).
#
# Tree loading is likewise the caller's: `(importTree.addPath dir).files` is one expression, the
# engine imports path leaves natively, and the source-layout convention belongs to whoever owns
# the source layout. This construct takes `modules` — a list — and nothing about directories.
{
  # The evaluator, handed in whole. The construct calls `engine.evalModuleTree` and holds no other
  # fact about it; today's evaluator is gen-merge (byte-mode `evalModuleTree`).
  engine,
  # The incremental plane's two decision functions (gen-memo), injected values in the roster's
  # injected-substrate pattern. `warmAdmits` decides whether an edit's SHAPE may ask for a warm
  # pass; `warmTrace` narrows the engine's published decision to the observed record and holds the
  # attachment rule as a property of the record.
  warmAdmits,
  warmTrace,
}:
let
  # The merge law of the `override` handle (feeds BOTH the warm and cold branches), per clause:
  #   modules      APPENDED to the originals — new module defs join the existing ones. Retraction
  #                of an existing def is `mkForce` in an appended module, NOT list removal.
  #   specialArgs  shallow-merged over the originals (`orig // edit`) — an edited key wins,
  #                untouched keys survive.
  #   engineArgs   shallow-merged over the originals (`orig // edit`), same as specialArgs.
  # `orig // edits` gives totality over any future key; the three explicit clauses re-derive the
  # APPEND / shallow-merge law for the three owned keys.
  mergeComposeArgs =
    orig: edits:
    orig
    // edits
    // {
      modules = (orig.modules or [ ]) ++ (edits.modules or [ ]);
      specialArgs = (orig.specialArgs or { }) // (edits.specialArgs or { });
      engineArgs = (orig.engineArgs or { }) // (edits.engineArgs or { });
    };

  # `composeAt ctx args` — the engine invocation + the shared result projection. `ctx` records HOW
  # this compose was reached, so a base compose and an override build the identical surface from
  # one place:
  #   warmFrom       previous FULL engine result to warm-splice against (null ⇒ the engine's cold
  #                  path; gen-merge README §"Warm re-eval"). Threaded WHOLE — the engine's memo is
  #                  its config/provenance/freeform records, so a projection would not do.
  #   editedModules  the appended module LIST of a fired warm override (the engine flattens it
  #                  itself — the flattened count is not caller-computable).
  #   traced         whether this result was reached through an edit; `warmTrace` holds the
  #                  attachment rule, so the record is spliced unconditionally below.
  composeAt =
    {
      warmFrom ? null,
      editedModules ? [ ],
      traced ? false,
    }:
    # `args@` keeps the ORIGINAL caller args attrset in scope for `override`'s re-compose
    # (mergeComposeArgs reads them); the destructured formals below stay the working defaults.
    args@{
      # Gen modules for the engine, in the caller's own order.
      modules ? [ ],
      # Module args, threaded to the engine CALLER-TOTAL (see the header: nothing is merged in).
      specialArgs ? { },
      # Threaded VERBATIM into `engine.evalModuleTree` (e.g. `check = false`). `modules` and
      # `specialArgs` are OWNED by compose; the warm knobs (`warmFrom`/`editedModules`) are
      # compose-owned too — only `override` supplies them. A colliding key would be silently
      # overridden by the `//` below, so name the offender(s) and throw instead. ONE construct
      # splices all four names into the engine call, so the guard lives whole beside the splice it
      # protects; the four names stay a literal list so a new colliding key is seen, not absorbed.
      engineArgs ? { },
    }:
    let
      engineArgsCollisions = builtins.filter (k: engineArgs ? ${k}) [
        "modules"
        "specialArgs"
        "warmFrom"
        "editedModules"
      ];
      _engineArgsCheck =
        if engineArgsCollisions != [ ] then
          throw "compose: engineArgs must not carry ${builtins.concatStringsSep ", " engineArgsCollisions} — compose owns these engine keys"
        else
          null;

      # The warm knobs reach the engine ONLY on a fired warm override (`warmFrom` non-null); a base
      # compose and a refused override pass neither ⇒ the engine's documented zero-behaviour-change
      # default (gen-merge README §"Warm re-eval").
      warmKnobs = if warmFrom == null then { } else { inherit warmFrom editedModules; };

      result = builtins.seq _engineArgsCheck (
        engine.evalModuleTree (
          engineArgs
          // {
            inherit modules specialArgs;
          }
          // warmKnobs
        )
      );

      projection = {
        # Resolved config VALUES — a thin read of the fixpoint config.
        values = result.config;

        # The engine PROVENANCE channel, projected VERBATIM under the engine's own name.
        # `provenance` is gen-merge's name for its channel (gen-merge README §Provenance); this is
        # a caller republishing an engine passthrough, and what is observed crosses as the observed
        # party said it — restating it under this construct's vocabulary would mint a second
        # spelling for one object and make the surface appear to answer a question it did not.
        provenance = result.provenance;

        # `override edits` → a fresh compose of the ORIGINAL args merged with `edits`
        # (mergeComposeArgs). The admission is the plane's: `warmAdmits` is handed the key this
        # construct's own warm splice is defined against, as a LITERAL at the call site — a
        # mis-declared key would flip the predicate fail-safe → fail-unsound (it would admit warm
        # passes for edits that changed arguments the splice assumes fixed), which is why the key
        # is not a parameter of this surface. On admission the captured `result` (this eval's FULL
        # engine memo) becomes the warmFrom and `edits.modules` the appended list; any other edit
        # shape ⇒ no warm context ⇒ the engine's cold path, stated in the trace. Override results
        # carry `override` again — chainable, and a chained warm threads THIS result as its own
        # warmFrom.
        override =
          edits:
          composeAt (
            if warmAdmits "modules" edits then
              {
                warmFrom = result;
                editedModules = edits.modules;
                traced = true;
              }
            else
              { traced = true; }
          ) (mergeComposeArgs args edits);
      };
    in
    # The observation is spliced UNCONDITIONALLY — a result reached without an edit carries no
    # `trace` because the record says so (gen-memo `warmTrace`'s attachment rule), not because a
    # branch here says so.
    projection
    // warmTrace {
      edited = traced;
      decision = result.warmDecision;
    };
in
{
  # The public entry: a base compose — no warm context, no `trace`. `override` re-enters with the
  # warm decision, so the warm path lands behind the standing byte-for-byte cold-parity oracle
  # (warm ≡ cold on `values` AND `provenance`; gen-memo `ci/tests/compose-parity.nix`).
  compose = composeAt { };
}
