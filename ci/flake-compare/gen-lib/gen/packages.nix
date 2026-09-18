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
  # EXCLUDED from the §2.6 evalSchema migration (den-hoag-0pk67; the ruled crossing class,
  # ADR-0018/ADR-0033) — MEASURED, not assumed. This tree's `gen` input is the NESTED,
  # deliberately-unswept lock ../flake.nix documents ("THIS LOCK IS NESTED, AND NOTHING SWEEPS
  # IT" — flake-compare gates nothing, so no relock schedule reaches it). Driven 2026-09-18: that
  # pin (`gen` 8dd9fda4, 2026-08-26) resolves `gen-schema` to `996097c2` (2026-08-18), four weeks
  # before `evalSchema` landed (`f8e0e171`, 2026-09-15) — `roster.schema ? evalSchema` reads
  # `false` on this pin and `roster.schema.evalSchema { ... }` throws `attribute 'evalSchema'
  # missing`, while the same call on this repo's own (unpinned) `gen.lib.mkGenLibs` reads `true`,
  # same run. What would have to change: hand-bump this flake's `gen` input (`nix flake update
  # gen` in `ci/flake-compare/gen-lib/` — its own documented remedy) to a rev whose gen-schema
  # exports `evalSchema`, then rewrite this as the ordinary `frozen = genSchema.evalSchema {
  # modules = [ { config.schema.pkg = <the kind body below>; } ]; }` let-bind per
  # specs/2026-09-15-gen-schema-inheritance-relocation-spec.md §2.6, mirroring `ci/inject-payload.nix`.
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
