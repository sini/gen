# gen definition module: the package specs as a typed gen-schema registry (PURE — no nixpkgs).
#
# A `pkg` kind (each instance = a builder tag + its script/file text) and an instance registry of the
# three comparison packages. `gen.lib.compose` (the hub successor compose) resolves this via
# gen-merge's byte-mode `evalModuleTree` with zero nixpkgs; the flake's per-system data terminal
# then maps each resolved spec to the SAME `writeShellScriptBin` / `writeText` derivation the
# flake-parts/ and adios/ variants build directly. Mirrors the gen-schema instance idiom
# (originally modeled on gen-flake's ci fixture tree/schema.nix).
{
  config,
  genSchema,
  genMerge,
  ...
}:
{
  options.schema = genSchema.mkSchemaOption { };
  options.packages = genSchema.mkInstanceRegistry config.schema.pkg { };

  config.schema.pkg = {
    # "shellScript" -> writeShellScriptBin, "text" -> writeText (resolved at the terminal).
    options.builder = genMerge.mkOption {
      type = genMerge.types.str;
      default = "shellScript";
    };
    options.text = genMerge.mkOption { type = genMerge.types.str; };
  };

  config.packages = {
    greeter = {
      builder = "shellScript";
      text = ''echo "hello from flake-compare"'';
    };
    farewell = {
      builder = "shellScript";
      text = ''echo "goodbye, $1"'';
    };
    notes = {
      builder = "text";
      text = "flake-compare shared notes\n";
    };
  };
}
