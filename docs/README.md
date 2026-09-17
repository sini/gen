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
pnpm run check    # typecheck only
pnpm run build    # typecheck, static build into dist/, validate every link
```

Published to <https://gen.wtf> by `.github/workflows/docs-pages.yml` on every
push to `main` that touches `docs/`. Pull requests get the build without the
deploy.

## Gates

Three things fail the build rather than reaching the site, because each one
would otherwise render as something plausible instead of as an error:

- **Broken internal links** — `starlight-links-validator` names the file, line
  and link. A dead cross-reference is indistinguishable from a live one on the
  page.
- **Type errors** — `astro check`, chained ahead of `astro build` so it cannot
  be skipped. `tsconfig.json` extends Astro's `strict` preset; leaving the
  checker out of the build made that preset decorative.
- **Malformed palettes** — see below.

`typescript` is held at 6.x on purpose. TypeScript 7 is the native compiler and
does not yet expose the programmatic API `astro check` needs; on 7.x the check
aborts rather than reporting. Likewise `mermaid` stays on 11.x because
`astro-mermaid` peers `^10 || ^11`.

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

- No favicon; Starlight's default is in use.
- No formatter covers this tree. gen's `treefmt` handles `*.nix`, `*.md` and
  the workflow files; `.astro`, `.mjs`, `.css` and `.mdx` are unmatched.
- No maths rendering (`remark-math` + `rehype-katex`) and no source-file code
  includes (`remark-code-import`), both of which the library documentation is
  likely to want.
