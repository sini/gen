# Oracle for the treefmt TREE-ROOT invariant.
#
# INVARIANT: the generated formatter must resolve its tree root with an EXPLICIT,
# worktree-aware command. A marker-file walk is forbidden.
#
# WHY. A linked worktree's `.git` is a gitdir-POINTER FILE, not a directory, so a
# `.git/config` marker search finds nothing inside the worktree and climbs UP. Where the
# worktree lives under the main checkout (`.worktrees/<task>/`, this ecosystem's writer
# discipline) the walk crosses the worktree boundary and resolves the MAIN checkout.
# treefmt then reads AND writes that tree: a run invoked in the worktree reformats the main
# checkout, reports success, and leaves the worktree's own files unformatted — so a
# `--ci` gate passing from inside a worktree has verified the wrong tree's bytes.
#
# The predicate is an ABSENCE, and an absence proves nothing without a live control: a grep
# over a missing wrapper or an empty config passes exactly as loudly as a clean one. So each
# absence below is preceded by a positive control on the same artefact in the same run.
{
  pkgs,
  formatter,
  name,
}:
pkgs.runCommand "${name}-treefmt-tree-root" { inherit formatter; } ''
  wrapper="$formatter/bin/treefmt"

  # ── positive controls: the artefacts exist and the predicates below CAN fire ──
  if [ ! -s "$wrapper" ]; then
    echo "CONTROL FAILED: no non-empty formatter wrapper at $wrapper" >&2
    exit 1
  fi
  if ! grep -q -- '--config-file=' "$wrapper"; then
    echo "CONTROL FAILED: wrapper passes no --config-file=; the argv predicate cannot fire" >&2
    exit 1
  fi
  config=$(sed -n 's/.*--config-file=\([^ ]*\).*/\1/p' "$wrapper" | head -n1)
  if [ ! -s "$config" ]; then
    echo "CONTROL FAILED: wrapper's config $config is missing or empty" >&2
    exit 1
  fi
  if ! grep -qE '^[[:space:]]*on-unmatched[[:space:]]*=' "$config"; then
    echo "CONTROL FAILED: config carries no known top-level key; its predicates cannot fire" >&2
    exit 1
  fi

  # ── the invariant, over both artefacts that can carry a tree-root decision ──
  if grep -q -- '--tree-root-file' "$wrapper"; then
    echo "TREE-ROOT REGRESSION: the wrapper passes a marker-file walk (--tree-root-file)." >&2
    echo "A marker walk escapes a linked worktree and formats the main checkout." >&2
    echo "Set treefmt.projectRootFile = null (flake-parts otherwise mkDefaults it)." >&2
    exit 1
  fi
  if grep -qE '^[[:space:]]*tree-root-file[[:space:]]*=' "$config"; then
    echo "TREE-ROOT REGRESSION: the config declares tree-root-file; see above." >&2
    exit 1
  fi
  if ! grep -qE '^[[:space:]]*tree-root-cmd[[:space:]]*=.*rev-parse[[:space:]]+--show-toplevel' "$config"; then
    echo "TREE-ROOT REGRESSION: the config does not STATE its tree root." >&2
    echo 'Expected: tree-root-cmd = "git rev-parse --show-toplevel"' >&2
    echo "Leaving it unstated falls back to treefmt's default, which is correct today but" >&2
    echo "silently resolves the CONFIG FILE'S STORE DIRECTORY outside a git repo." >&2
    exit 1
  fi

  echo "── ${name}-treefmt-tree-root ──"
  echo "wrapper: $wrapper"
  echo "config:  $config"
  echo "no marker-file walk in either artefact; tree root stated as:"
  grep -E '^[[:space:]]*tree-root-cmd[[:space:]]*=' "$config"
  touch "$out"
''
