# gen docs

The gen documentation site: [Astro](https://astro.build) +
[Starlight](https://starlight.astro.build), sharing the design pattern used by
[den's docs](https://github.com/denful/den/tree/main/docs).

## Writing

Every page under `src/content/docs/` follows these rules.

- **Plain technical English.** Write the way a good man page or a Rust book
  chapter reads. Short declarative sentences, common words, one idea per
  sentence. A reader who knows Nix and nothing about gen should follow every
  paragraph on the first read.
- **Say what a thing is.** Never define something by what it is not. Cut "not
  X, but Y", "X isn't a Y — it's a Z", "It was not assembled. It was resolved."
  and "We did not invent this. We implemented it." Write "A policy is a rule in
  a logic program."
- **State, don't defend.** Present a design as the design. No justifying it
  against alternatives nobody raised, no "we say so", no "on purpose", no
  "honestly". Drop hedges ("in principle", "worth knowing about", "narrower
  and does more work").
- **Promote with facts.** Show what gen does and what that gets the user, with
  an example or a number. No marketing adjectives ("powerful", "seamless").
- **Concrete first.** Lead a section with the example or the one-sentence
  answer; the mechanism follows. Prefer a code block over a paragraph
  describing code.
- **No invented idiom.** Avoid coined phrasings the reader has to decode:
  "refuses by name", "by construction", "load-bearing", "the whole trick",
  "nothing less than", "the crossing", "owes". Say "fails with an error naming
  X", "always", "required".
- **Define a term once, where it first appears,** in one plain clause, and link
  to [terminology](src/content/docs/reference/terminology.mdx) for the rest.
- **Sparing punctuation.** At most one dash aside per paragraph. No
  semicolon chains. No rhetorical fragments.
- **Public audience.** No internal tracker ids (`den-hoag-*`), design-repo
  paths (`den-ag-design:`), session history or arc names.
- **Accurate to the code.** Every library name, function name and behaviour on
  a page matches the source at the current lock. The roster is
  `lib/mkGenLibs.nix`. gen is pre-release: document what ships today, never removed or renamed features.
- **Organise by domain, not by repository.** Pages cover what gen does (graphs
  and queries, typed configuration, aspects, policies, incremental evaluation,
  delivery) and name the library that provides it in passing. The library and
  stratum layout is an implementation detail that will change.
- **Facts earn their place.** A number, check or guarantee goes on a page when
  it helps a reader decide to use gen or use it correctly. Internal CI
  bookkeeping stays in the repositories.
- **Asides are for warnings a reader would act on.** Everything else goes in
  the prose.

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
