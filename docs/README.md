# gen docs

The gen documentation site: [Astro](https://astro.build) +
[Starlight](https://starlight.astro.build), sharing the design pattern used by
[den's docs](https://github.com/denful/den/tree/main/docs).

Scaffolding and components only at this point — every page under
`src/content/docs/` is a placeholder.

## Running it

```bash
pnpm install
pnpm run dev      # local server
pnpm run build    # static build into dist/
```

## Layout

| Path                             | What it is                                                                                      |
| -------------------------------- | ----------------------------------------------------------------------------------------------- |
| `astro.config.mjs`               | Fonts, mermaid theming, the sidebar tree, component overrides                                   |
| `src/palettes.mjs`               | The palette table, the CSS it generates, and the pre-paint boot script                          |
| `src/ec-whole-token-markers.mjs` | Expressive Code plugin: string text markers match whole tokens                                  |
| `src/components/`                | Starlight component overrides                                                                   |
| `src/components/tabs/`           | The tabbed sidebar switcher (vendored, see its `LICENSE`)                                       |
| `src/styles/layout.css`          | Typography and surface layer — no hardcoded colours, everything resolves through `--sl-color-*` |
| `src/styles/custom.css`          | Font-family assignment                                                                          |

## Palettes

Colour is a runtime choice, not a build-time one. `src/palettes.mjs` is the
single source of truth: it declares the palettes, generates their CSS, emits the
boot script that applies one before first paint, and produces the upstream
attribution notices in the footer. Readers switch with `t` or `/`, or the
trigger in the header.

The table is validated when the module loads, so `astro build` refuses a palette
with a missing or malformed token, a duplicate id, incomplete upstream
attribution, or a `defaults` entry naming a palette that does not exist. Adding
a palette means adding a row and nothing else.

`origin` is a required discriminated union rather than an optional credit field:
a palette copied from an upstream project cannot be added without naming that
project.

## Not yet wired up

- `site` is unset in `astro.config.mjs`, so sitemap generation is skipped and
  canonical URLs are relative. Set it once the deploy URL is decided.
- No CI job builds this. gen's workflow is pure Nix and this needs node.
- No favicon; Starlight's default is in use.
