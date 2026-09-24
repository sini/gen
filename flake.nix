{
  inputs = {
    # The only non-gen input, and it is here because `ci/flake.nix` follows it — this flake
    # evaluates no nixpkgs itself. The seven tool inputs that used to sit beside it (nix-unit,
    # import-tree, treefmt-nix, devshell, flake-root, git-hooks-nix, flake-parts) existed to feed
    # `mkCi`'s `resolve` fallback through `genInputs`. `mkCi` lives in gen-harness now and that
    # repository declares them itself, so here they were reachable from nothing.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    # ── THE ROSTER — and every cross-dependency edge follows back to this list ──
    # One `follows` line per sibling edge, so a gen library resolves to exactly ONE version across
    # the whole graph. Without them nix must materialise a node per (input, path): 90 of 114 nodes
    # in this lock were duplicates, `gen-prelude` alone reaching 44 copies, and a lock read by node
    # NAME then returns a transitive copy rather than the pin the hub declares.
    #
    # The convergence is the point rather than a tidy-up. A member that cannot evaluate against the
    # hub's rev of a sibling now reds its own check, where the divergence used to be silent and
    # permanent — that failure is a regression caught, not a price paid for the dedup.
    #
    # The list is DERIVED: each line mirrors an edge the sibling's own flake declares. A sibling
    # that grows an input needs its line here, or that one input re-forks while the rest converge.
    gen-prelude.url = "github:sini/gen-prelude";
    gen-identity.url = "github:sini/gen-identity";
    gen-algebra.url = "github:sini/gen-algebra";

    gen-types.url = "github:sini/gen-types";
    gen-types.inputs.gen-identity.follows = "gen-identity";
    gen-types.inputs.gen-prelude.follows = "gen-prelude";

    gen-merge.url = "github:sini/gen-merge";
    gen-merge.inputs.gen-memo.follows = "gen-memo";
    gen-merge.inputs.gen-prelude.follows = "gen-prelude";
    gen-merge.inputs.gen-types.follows = "gen-types";

    gen-schema.url = "github:sini/gen-schema";
    gen-schema.inputs.gen-algebra.follows = "gen-algebra";
    gen-schema.inputs.gen-identity.follows = "gen-identity";
    gen-schema.inputs.gen-merge.follows = "gen-merge";
    gen-schema.inputs.gen-prelude.follows = "gen-prelude";

    gen-aspects.url = "github:sini/gen-aspects";
    gen-aspects.inputs.gen-identity.follows = "gen-identity";
    gen-aspects.inputs.gen-merge.follows = "gen-merge";
    gen-aspects.inputs.gen-prelude.follows = "gen-prelude";
    gen-aspects.inputs.gen-schema.follows = "gen-schema";

    gen-scope.url = "github:sini/gen-scope";
    gen-scope.inputs.gen-graph.follows = "gen-graph";
    gen-scope.inputs.gen-identity.follows = "gen-identity";
    gen-scope.inputs.gen-prelude.follows = "gen-prelude";

    gen-memo.url = "github:sini/gen-memo";
    gen-memo.inputs.gen-graph.follows = "gen-graph";
    gen-memo.inputs.gen-prelude.follows = "gen-prelude";

    gen-graph.url = "github:sini/gen-graph";
    gen-graph.inputs.gen-prelude.follows = "gen-prelude";

    gen-select.url = "github:sini/gen-select";
    gen-select.inputs.gen-algebra.follows = "gen-algebra";

    gen-bind.url = "github:sini/gen-bind";
    gen-bind.inputs.gen-graph.follows = "gen-graph";
    gen-bind.inputs.gen-prelude.follows = "gen-prelude";

    gen-dispatch.url = "github:sini/gen-dispatch";
    gen-dispatch.inputs.gen-prelude.follows = "gen-prelude";

    gen-class.url = "github:sini/gen-class";
    gen-class.inputs.gen-prelude.follows = "gen-prelude";

    gen-product.url = "github:sini/gen-product";
    gen-product.inputs.gen-prelude.follows = "gen-prelude";

    gen-settings.url = "github:sini/gen-settings";
    gen-settings.inputs.gen-algebra.follows = "gen-algebra";
    gen-settings.inputs.gen-bind.follows = "gen-bind";
    gen-settings.inputs.gen-graph.follows = "gen-graph";
    gen-settings.inputs.gen-identity.follows = "gen-identity";
    gen-settings.inputs.gen-prelude.follows = "gen-prelude";
    gen-settings.inputs.gen-schema.follows = "gen-schema";
    gen-settings.inputs.gen-types.follows = "gen-types";

    gen-link.url = "github:sini/gen-link";
    gen-link.inputs.gen-algebra.follows = "gen-algebra";
    gen-link.inputs.gen-aspects.follows = "gen-aspects";
    gen-link.inputs.gen-identity.follows = "gen-identity";
    gen-link.inputs.gen-prelude.follows = "gen-prelude";
    gen-link.inputs.gen-schema.follows = "gen-schema";
    gen-link.inputs.gen-scope.follows = "gen-scope";
    gen-link.inputs.gen-view.follows = "gen-view";

    gen-assemble.url = "github:sini/gen-assemble";

    gen-view.url = "github:sini/gen-view";
    gen-view.inputs.gen-graph.follows = "gen-graph";
    gen-view.inputs.gen-prelude.follows = "gen-prelude";

    gen-inspect.url = "github:sini/gen-inspect";
    gen-inspect.inputs.gen-prelude.follows = "gen-prelude";
    gen-inspect.inputs.gen-graph.follows = "gen-graph";
    gen-inspect.inputs.gen-select.follows = "gen-select";
    gen-inspect.inputs.gen-scope.follows = "gen-scope";
    gen-inspect.inputs.gen-program.follows = "gen-program";

    gen-program.url = "github:sini/gen-program";
    gen-delivery.url = "github:sini/gen-delivery";

    # The import-tree FORK (nixpkgs-lib-free; `(addPath dir).files` yields a bare path list the
    # engine imports natively). It is a TOOL input, not a roster member: the tree-loading line is
    # the framework surface's own wiring (`flakeModules/default.nix`), so the fork's pin lives
    # here at the hub rather than inside an S2 construct. Same pin gen-flake carried.
    import-tree.url = "github:denful/import-tree/a164a12202f58eb67559bd33b5592f20660d9baf";
  };

  outputs =
    inputs:
    let
      # ★★★ L3 APPLIED TO THE HUB — the flake output IS the root, applied to what this flake's own
      # inputs supply (owner-ruled 2026-09-14: "`mkGenLibs` stops being a fixed point and becomes a
      # CONSUMER of the same pattern every member follows"). There is ONE construction of the roster
      # and `./default.nix` is it; the two entry paths differ only in WHO supplies the members. Here
      # the flake supplies them, so `follows` governs every one; the standalone path falls back to
      # `ci/flake.lock`. Before this, `./default.nix` did not exist and the hub was flake-only.
      #
      # ★★ THE THREE UNAPPLIED `.lib`s ARE L3's SECOND ARM ARRIVING, NOT AN EXCEPTION LIST.
      # gen-program, gen-delivery and gen-assemble declare NO gen input, so their OWN flakes have
      # nothing to pass and publish `lib = import ./.` UNAPPLIED; the other 18 publish an applied
      # set. What is written here is therefore the member's own L3 arm read off its published
      # surface, and it is LOUD if that arm ever changes — applying an already-applied set is
      # `attempt to call something which is not a function but a set`, and a member that went the
      # other way arrives as a function and reds the `roster` output's own force below. The rejected
      # alternative was to arity-dispatch here (`if builtins.isFunction v then v { } else v`), which
      # makes the hub TOLERANT of either shape and so accepts a member that landed the wrong arm in
      # silence — the failure L3 exists to make loud.
      #
      # AN UNAPPLIED ARM IS PRECISELY THE ONE WHOSE ARGUMENTS THE CONSUMER OWES (ADR-0008 §1).
      # Until this fold, the three were applied to `{ }`, so each self-fetched its own substrate
      # instance out of its own `ci/flake.lock` instead of receiving the hub's — the defect
      # `./lib/hubSubstrate.nix` closes. That file is a pure function of `members` below (never of
      # `inputs`), naming exactly the substrate each of the three needs; the `mapAttrs` fold applies
      # every member's `.lib` — applied set or unapplied function alike — at this ONE site, so there
      # is nowhere else in this file a mis-keyed application could be written.
      members = {
        algebra = inputs.gen-algebra.lib;
        aspects = inputs.gen-aspects.lib;
        bind = inputs.gen-bind.lib;
        class = inputs.gen-class.lib;
        dispatch = inputs.gen-dispatch.lib;
        graph = inputs.gen-graph.lib;
        identity = inputs.gen-identity.lib;
        link = inputs.gen-link.lib;
        memo = inputs.gen-memo.lib;
        merge = inputs.gen-merge.lib;
        prelude = inputs.gen-prelude.lib;
        product = inputs.gen-product.lib;
        schema = inputs.gen-schema.lib;
        scope = inputs.gen-scope.lib;
        select = inputs.gen-select.lib;
        settings = inputs.gen-settings.lib;
        types = inputs.gen-types.lib;
        view = inputs.gen-view.lib;
      };

      # THE FOLD IS SELF-REFERENTIAL: `hubSubstrate.nix` reads `members // applied`, so an unapplied
      # member (gen-inspect) can take another unapplied member (gen-program) APPLIED, and each is
      # applied exactly once. `mapAttrs` needs only the file's key set, which its attrset literal
      # supplies without forcing `members // applied`. See that file for the cycle hazard.
      applied = builtins.mapAttrs (k: args: inputs."gen-${k}".lib args) (
        import ./lib/hubSubstrate.nix (members // applied)
      );

      roster = import ./. (members // applied);

      # The PUBLISHED two-stage surface, kept exactly as its consumers call it. Stage 2's argument
      # was always vestigial — every caller passes `{ }`, `{ inherit lib; }` or `{ lib = null; }` and
      # the roster ignores it — so the compat wrapper belongs here, at the publication site, while
      # `lib/mkGenLibs.nix` is the construction and returns the roster itself. That is what lets
      # `import <gen> { }` yield the roster directly while `gen.lib.mkGenLibs { … }` still answers
      # for its thirteen call sites across this hub and gen-demo.
      mkGenLibs = _: roster;

      # A stratum bucket is a SELECTION from the flat roster, never a re-import: `substrate.prelude`
      # and the flat `prelude` are one value rather than two evaluations of the same source. That
      # distinction is invisible to a names-and-types comparison — a library re-imported at a
      # different pin has identical names and identical types while being a different build — so it
      # is the roster, not a reconstruction of it, that the buckets are cut from.
      bucket =
        s:
        builtins.listToAttrs (
          map (n: {
            name = n;
            value = roster.${n};
          }) (builtins.filter (n: roster.strata.${n} == s) (builtins.attrNames roster.strata))
        );
    in
    {
      # `lib.mkCi` is NOT here, and its absence is the point rather than an omission: the CI
      # wrapper is `gen-harness.lib.mkCi`, in its own repository. A library's test harness must
      # not depend on the aggregator that pins that library, and re-exporting it from here was
      # the last edge that made it.
      lib.mkGenLibs = mkGenLibs;

      # The successor compose (ADR-0031 F2's "compose S2 core → S2" row), bound against the
      # roster: gen-merge as the engine, gen-memo's two decision functions as the plane. The
      # construct itself (lib/compose.nix) binds no constructor vocabulary and takes `specialArgs`
      # caller-total; a bare caller performs its own constructor threading, and the flakeModule
      # below performs it for hub-fronted trees.
      #
      # INTERIM EXPOSURE. The construct is the settled S2 core, but this hub surface does NOT
      # satisfy ADR-0027 — it is the same interim standing as `flakeModules.default` below, and
      # the true framework surface that arrives with den v2 / quiver is what re-homes the
      # exposure. Do not build a framework contract on top of the exposure's location.
      lib.compose =
        (import ./lib/compose.nix {
          engine = roster.merge;
          inherit (roster.memo) warmAdmits warmTrace;
        }).compose;

      # The stack layers, each selected by the roster's own stratum declaration. The `retiring`
      # declaration publishes no path here by design: inviting a consumer to select a library on its
      # way off the roster is the adoption that value exists to prevent, and its members stay
      # reachable through `mkGenLibs`.
      #
      # `framework` DOES publish, and the asymmetry with `retiring` is the point rather than an
      # inconsistency. The two were once excluded by one sentence whose stated ground — a consumer
      # selecting a leaving library — is true of `retiring` alone; a framework library is not
      # leaving. What forced the reading is that a framework TOOLKIT is a library every assembling
      # framework is meant to reach, so withholding its path made the intended consumption path the
      # one case the hub does not serve.
      lib.substrate = bucket "substrate";
      lib.modules = bucket "modules";
      lib.aspects = bucket "aspects";
      lib.framework = bucket "framework";

      flakeModules.genLibs = ./flakeModules/genLibs.nix;

      # `nix flake check` forces the WHNF of every top-level output and nothing deeper — measured: a
      # throwing `lib.mkGenLibs` passes it, a throwing `lib` SPINE fails it. This root declares no
      # `checks`, so without an output whose WHNF is the roster itself, `all checks passed!` quantifies
      # over the empty set. Forcing is to NAMES depth and not `deepSeq`: a retirement tombstone is a
      # published `throw` by design (gen-scope's `buildNodes`), so a deep force is red on a healthy tree.
      #
      # INTERIM, the same standing as `lib.compose` and `flakeModules.default` below: it does NOT
      # satisfy ADR-0027, and joins the pending surface rather than outliving it — ADR-0027 disposes of
      # all three together when it arrives (den-hoag-z5wsg).
      roster = builtins.deepSeq (builtins.mapAttrs (_: builtins.attrNames) (
        builtins.removeAttrs roster [ "strata" ]
      )) roster.strata;

      # The flake-parts entry surface, rehomed from gen-flake under ADR-0031 F1 — the hub is the
      # single input a consumer takes, so the ergonomics module belongs beside the roster it binds
      # against. `default` is flake-parts' own convention and the name the source exported under, so
      # a consumer's `imports = [ inputs.gen.flakeModules.default ]` reads unchanged.
      #
      # INTERIM. It does NOT satisfy ADR-0027; the true framework surface arrives with den v2 /
      # quiver bound against that interface, and this module is what that replaces. The file header
      # carries the marker and names the two measured defects that travelled with it unfixed
      # (den-hoag-es9g).
      flakeModules.default = ./flakeModules/default.nix;
    };
}
