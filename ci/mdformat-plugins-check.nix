# Oracle for the mdformat PLUGIN-DELIVERY invariant.
#
# INVARIANT: the mdformat the generated formatter actually runs must carry the base plugin set.
# It is not enough for a plugin list to appear in the Nix expression — the whole defect this
# check exists for is a list that was written, reviewed, and DISCARDED.
#
# WHY. treefmt-nix builds its final package as `cfg.package.withPlugins cfg.plugins`, and
# mdformat's `withPlugins` wraps a HARDCODED plain base rather than the package it is called on.
# So a set written into `package` never reaches the formatter: the shipped derivation is plain
# mdformat, store-path-identical to it. Every consumer then formats markdown with a plugin-less
# mdformat, which rewrites YAML frontmatter it does not recognise into a thematic break plus a
# heading. One repository's frontmatter was destroyed exactly that way, and the format gate went
# green afterwards — because the damage is IDEMPOTENT, so re-running the broken formatter over
# the wreckage reports nothing to do.
#
# ★ THAT IDEMPOTENCE IS WHY THIS CHECK LOOKS AT THE ARTEFACT AND NOT AT A FILE. A gate that
# formats and compares cannot see this class once the damage has landed. This one reads the
# built wrapper, so it fails on the configuration change that would reintroduce the class,
# before any file is touched — the same reason `treefmt-tree-root.nix` beside it gates the
# generated artefact rather than the settings above it.
#
# The core predicates are ABSENCES, and an absence proves nothing without a live control: a grep
# over a missing wrapper passes exactly as loudly as a clean one. Each is preceded by a positive
# control on the same artefact in the same run.
{
  pkgs,
  formatter,
  name,
  # The plain, unwrapped mdformat from the SAME pkgs the formatter was built from. Passing it in
  # rather than re-deriving it is what makes the O1 comparison exact: "not plain" has to mean
  # not-plain-for-this-nixpkgs, and a second evaluation could resolve a different one.
  plain ? pkgs.mdformat,
}:
pkgs.runCommand "${name}-mdformat-plugins"
  {
    inherit formatter;
    plainMdformat = plain;
  }
  ''
    wrapper="$formatter/bin/treefmt"

    # ── positive controls: the artefacts exist and the predicates below CAN fire ──
    if [ ! -s "$wrapper" ]; then
      echo "CONTROL FAILED: no non-empty formatter wrapper at $wrapper" >&2
      exit 1
    fi
    if ! grep -q -- '--config-file=' "$wrapper"; then
      echo "CONTROL FAILED: wrapper passes no --config-file=; the config predicates cannot fire" >&2
      exit 1
    fi
    config=$(sed -n 's/.*--config-file=\([^ ]*\).*/\1/p' "$wrapper" | head -n1)
    if [ ! -s "$config" ]; then
      echo "CONTROL FAILED: wrapper's config $config is missing or empty" >&2
      exit 1
    fi
    if ! grep -q '^\[formatter\.mdformat\]' "$config"; then
      echo "CONTROL FAILED: config declares no [formatter.mdformat]; this check has no subject." >&2
      echo "If mdformat was deliberately removed, remove this check with it." >&2
      exit 1
    fi
    md=$(sed -n '/^\[formatter\.mdformat\]/,/^\[/p' "$config" \
           | sed -n 's/^[[:space:]]*command[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' | head -n1)
    if [ ! -s "$md" ]; then
      echo "CONTROL FAILED: [formatter.mdformat] names no runnable command ($md)" >&2
      exit 1
    fi

    # ── O1 · the command must not BE plain mdformat ──
    # The defect's signature is exact rather than approximate: when the plugin list is discarded
    # the result is store-path-identical to the plain package, so this is an equality test and
    # not a heuristic.
    mdroot=$(dirname "$(dirname "$md")")
    if [ "$mdroot" = "$plainMdformat" ]; then
      echo "MDFORMAT PLUGIN REGRESSION: the formatter runs PLAIN mdformat." >&2
      echo "  command: $md" >&2
      echo "  plain:   $plainMdformat" >&2
      echo "The two are the same store path, which is the exact signature of a plugin list that" >&2
      echo "was DISCARDED. Route the set through programs.mdformat.plugins; a list written into" >&2
      echo "programs.mdformat.package does not reach the formatter and does not union with it." >&2
      exit 1
    fi

    # ── O2 · the base set must be reachable from the command the config names ──
    # Read off the wrapper the config actually runs, so a set that is present in the expression
    # but absent from the artefact still fails.
    missing=""
    for plugin in mdformat-footnote mdformat-frontmatter mdformat-gfm mdformat-simple-breaks; do
      if ! grep -q "$plugin" "$md"; then
        missing="$missing $plugin"
      fi
    done
    if [ -n "$missing" ]; then
      echo "MDFORMAT PLUGIN REGRESSION: the formatter is missing base plugins:$missing" >&2
      echo "  command: $md" >&2
      echo "These defend representational invariants — whether a leading '---' block is data," >&2
      echo "whether a '[^1]:' line is a footnote, whether a '|'-delimited row is a table, how a" >&2
      echo "thematic break renders. They are not stylistic, and dropping one silently rewrites" >&2
      echo "documents that use the construct." >&2
      echo "Note programs.mdformat.plugins REPLACES: to add a plugin, extend the base set" >&2
      echo "through gen.ci.mdformat.extraPlugins rather than assigning plugins directly." >&2
      exit 1
    fi

    touch $out
  ''
