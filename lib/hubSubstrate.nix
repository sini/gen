# The substrate the hub hands the three members whose flake `.lib` is published UNAPPLIED. A FUNCTION
# OF THE HUB'S OWN `members` BINDINGS — never of `inputs` — so there is one expression per member in
# this flake and this file re-derives none of them. `inherit` binds without forcing, so a reader
# taking `attrNames` never forces a leaf, which is what lets `ci/` read the supplied key sets
# hermetically, the same direction `ci/hub-entry.nix` takes on the standalone root.
members: {
  assemble = { inherit (members) prelude scope algebra; };
  delivery = { inherit (members) algebra aspects; };
  program = { inherit (members) prelude scope; };
}
