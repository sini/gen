# The substrate the hub hands the four members whose flake `.lib` is published UNAPPLIED. A FUNCTION
# OF THE HUB'S OWN BINDINGS — never of `inputs` — so there is one expression per member in this flake
# and this file re-derives none of them. Its argument is `members // applied`: the eighteen APPLIED
# roster entries plus the applied values of the unapplied members this file's own fold produces.
# `inherit` binds without forcing, so a reader taking `attrNames` never forces a leaf, which is what
# lets `ci/` read the supplied key sets hermetically, the same direction `ci/hub-entry.nix` takes on
# the standalone root.
members: {
  assemble = { inherit (members) prelude scope algebra; };
  delivery = { inherit (members) algebra aspects; };
  # ★★ THE FOLD IS WELL-FOUNDED ONLY WHILE THE UNAPPLIED MEMBERS' DEPENDENCIES ARE ACYCLIC. The
  # order is `inspect → program → {prelude, scope}`, and `program` is applied once and shared by
  # gen-inspect and the roster. A key here naming an unapplied member that (transitively) names
  # this one back is a CYCLE, and it is LOUD BUT UNNAMED: every hub consumer — not only the member
  # involved — dies with `infinite recursion encountered`, because `default.nix`'s eager boundary
  # force reaches the fold. A fold over `members` alone cannot form a cycle, and a stratified
  # two-pass fold would keep that guarantee, at the cost of a second pass.
  inspect = {
    inherit (members)
      prelude
      graph
      select
      scope
      program
      ;
  };
  program = { inherit (members) prelude scope; };
}
