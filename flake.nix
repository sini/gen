{
  inputs = {
    # The only non-gen input, and it is here because `ci/flake.nix` follows it — this flake
    # evaluates no nixpkgs itself. The seven tool inputs that used to sit beside it (nix-unit,
    # import-tree, treefmt-nix, devshell, flake-root, git-hooks-nix, flake-parts) existed to feed
    # `mkCi`'s `resolve` fallback through `genInputs`. `mkCi` lives in gen-harness now and that
    # repository declares them itself, so here they were reachable from nothing.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    gen-prelude.url = "github:sini/gen-prelude";
    gen-identity.url = "github:sini/gen-identity";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-schema.url = "github:sini/gen-schema";
    gen-aspects.url = "github:sini/gen-aspects";
    gen-scope.url = "github:sini/gen-scope";
    gen-memo.url = "github:sini/gen-memo";
    gen-graph.url = "github:sini/gen-graph";
    gen-select.url = "github:sini/gen-select";
    gen-bind.url = "github:sini/gen-bind";
    gen-dispatch.url = "github:sini/gen-dispatch";
    gen-resolve.url = "github:sini/gen-resolve";
    gen-class.url = "github:sini/gen-class";
    gen-product.url = "github:sini/gen-product";
    gen-settings.url = "github:sini/gen-settings";
    gen-link.url = "github:sini/gen-link";
    gen-assemble.url = "github:sini/gen-assemble";
    gen-view.url = "github:sini/gen-view";
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
      mkGenLibs = import ./lib/mkGenLibs.nix { genInputs = inputs; };
      roster = mkGenLibs { }; # the `lib` arg is vestigial (lib/mkGenLibs.nix)

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
