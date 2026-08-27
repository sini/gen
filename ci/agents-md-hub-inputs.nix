# agents-md-hub-inputs — binds AGENTS.md's hub-input enumeration block to the flake's OWN gen-*
# input set (den-hoag-bzcb4, successor to den-hoag-8j5b: the block is prose and drifted once,
# 19-vs-21, caught only because the owner counted it by hand).
#
# AGENTS.md publishes an enumeration command and its literal JSON output as the hub's gen-*
# roster, for a reader who will not run Nix. Nothing bound the two together, so a new hub input
# can land while the block stays exactly as it was — the command still runs and still prints the
# TRUE list, but nothing re-runs it against the printed one. This check does: it reads the fenced
# block back out of the committed file, between the `<!-- gen-inputs:begin/end -->` markers (the
# document carries a SECOND ```json fence later — the root Drift-check section — so an
# unmarked/first-fence extraction would only be accidentally correct), and compares it, both
# directions, against the flake's actual gen-* inputs — reached through `genInputs` (the root
# flake's pinned `inputs`, the same route every other check in this file uses), never by
# re-shelling the sheet's own `nix eval --impure` command from inside a pure eval.
{
  genInputs,
  lib,
}:
let
  agentsSheet = builtins.readFile ../AGENTS.md;

  beginMarker = "<!-- gen-inputs:begin -->";
  endMarker = "<!-- gen-inputs:end -->";

  # Marker-delimited window first (structural, not line-numbered), THEN the fence stripped out of
  # that window — so a second ```json block elsewhere in the file cannot be picked up by accident.
  window = lib.elemAt (lib.splitString endMarker (lib.elemAt (lib.splitString beginMarker agentsSheet) 1)) 0;
  jsonText = lib.elemAt (lib.splitString "```" (lib.elemAt (lib.splitString "```json" window) 1)) 0;

  documented = builtins.fromJSON jsonText;

  actual = builtins.filter (n: lib.hasPrefix "gen-" n) (builtins.attrNames genInputs);

  missing = builtins.filter (n: !(builtins.elem n documented)) actual; # in the flake, not the sheet
  extra = builtins.filter (n: !(builtins.elem n actual)) documented; # in the sheet, not the flake
in
{
  gate = {
    sheet-total = missing == [ ]; # every actual gen-* input is named in the sheet
    sheet-exact = extra == [ ]; # the sheet names nothing the flake doesn't actually have
    sheet-ordered = documented == actual; # byte-for-byte: same set AND same order
  };
  gateKeys = [
    "sheet-total"
    "sheet-exact"
    "sheet-ordered"
  ];
  inherit
    documented
    actual
    missing
    extra
    ;
}
