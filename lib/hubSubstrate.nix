# The substrate the hub hands the three members whose flake `.lib` is published UNAPPLIED. A FUNCTION
# OF THE HUB'S OWN `members` BINDINGS — never of `inputs` — so there is one expression per member in
# this flake and this file re-derives none of them. `inherit` binds without forcing, so a reader
# taking `attrNames` never forces a leaf, which is what lets `ci/` read the supplied key sets
# hermetically, the same direction `ci/hub-entry.nix` takes on the standalone root.
members: {
  assemble = { inherit (members) prelude scope algebra; };
  delivery = { inherit (members) algebra aspects; };
  # ★ gen-inspect's fifth declared dependency, gen-program, is NOT here and cannot be: this file is a
  # function of `members`, which holds exactly the eighteen roster entries whose `.lib` is published
  # APPLIED, and `program` is one of the three UNAPPLIED members the fold over this very attrset
  # produces. gen-inspect therefore declares four formals at this gate and takes gen-program at the
  # gate that builds its program route, when the fold this file feeds is rewritten to be
  # self-referential or the dependency arrives another way.
  inspect = {
    inherit (members)
      prelude
      graph
      select
      scope
      ;
  };
  program = { inherit (members) prelude scope; };
}
