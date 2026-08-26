# gen definition module: the devShell + formatter specs as plain typed gen-merge options (PURE).
#
# devShell carries the nixpkgs tool names it wants (resolved to `pkgs.<name>` at the terminal) and a
# shellHook; formatter is a `pkg`-shaped spec (builder + text). Kept as bare gen-merge options rather
# than a schema registry — these are single scalars, not a registry — mirroring the fixture idiom of
# declaring `genMerge.mkOption` surfaces directly beside a schema.
{
  genMerge,
  ...
}:
{
  options.devShell.packages = genMerge.mkOption {
    type = genMerge.types.listOf genMerge.types.str;
    default = [ ];
  };
  options.devShell.shellHook = genMerge.mkOption {
    type = genMerge.types.str;
    default = "";
  };

  options.formatter.builder = genMerge.mkOption {
    type = genMerge.types.str;
    default = "shellScript";
  };
  options.formatter.text = genMerge.mkOption { type = genMerge.types.str; };

  config.devShell = {
    packages = [
      "hello"
      "jq"
    ];
    shellHook = "echo entering flake-compare devshell";
  };

  config.formatter.text = "echo formatting; exit 0";
}
