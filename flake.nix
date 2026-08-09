{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    import-tree.url = "github:sini/import-tree";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";

    gen-prelude.url = "github:sini/gen-prelude";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-schema.url = "github:sini/gen-schema";
    gen-aspects.url = "github:sini/gen-aspects";
    gen-scope.url = "github:sini/gen-scope";
    gen-graph.url = "github:sini/gen-graph";
    gen-select.url = "github:sini/gen-select";
    gen-bind.url = "github:sini/gen-bind";
    gen-dispatch.url = "github:sini/gen-dispatch";
    gen-resolve.url = "github:sini/gen-resolve";
    gen-flake.url = "github:sini/gen-flake";
    gen-class.url = "github:sini/gen-class";
    gen-edge.url = "github:sini/gen-edge";
    gen-product.url = "github:sini/gen-product";
    gen-settings.url = "github:sini/gen-settings";
    gen-demand.url = "github:sini/gen-demand";
    gen-pipe.url = "github:sini/gen-pipe";
    gen-link.url = "github:sini/gen-link";
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
      lib.mkCi = import ./ci/mkCi.nix { inherit inputs; };
      lib.mkGenLibs = mkGenLibs;

      # The three stack layers, each selected by the roster's own stratum declaration. The
      # `framework` and `retiring` declarations publish no path here by design: they are facts
      # about the roster, and inviting a consumer to select a leaving library is the adoption the
      # `retiring` value exists to prevent. Both remain reachable on the flat roster.
      lib.substrate = bucket "substrate";
      lib.modules = bucket "modules";
      lib.aspects = bucket "aspects";

      flakeModules.genLibs = ./flakeModules/genLibs.nix;
    };
}
