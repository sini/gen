// @ts-check
import { fileURLToPath } from 'node:url';
import { defineConfig, fontProviders } from 'astro/config';
import starlight from '@astrojs/starlight';

import mermaid from 'astro-mermaid';
import starlightLinksValidator from 'starlight-links-validator';
import { unified } from '@astrojs/markdown-remark';
import { codeImport } from 'remark-code-import';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import { wholeTokenTextMarkers } from './src/ec-whole-token-markers.mjs';

// The repository root, one level above docs/. Code fences cite library sources
// relative to it, which live outside the Astro project.
const repoRoot = fileURLToPath(new URL('..', import.meta.url));

// remark-code-import declares its transformer as returning `Promise<void[]>`,
// which unified's `Plugin` return type does not admit. The plugin is a valid
// remark plugin — the assertion is confined to that declaration mismatch rather
// than applied to the plugin list, so a genuinely wrong entry there still fails.
const codeImportPlugin = /** @type {import('@astrojs/markdown-remark').RemarkPlugin} */ (
	/** @type {unknown} */ (codeImport)
);

// https://astro.build/config
export default defineConfig({
	// Served from an apex domain, so no `base` path. This is what canonical URLs,
	// the sitemap and Open Graph tags are built against; leaving it unset makes
	// all three either relative or absent.
	site: 'https://gen.wtf',
	// `markdown.remarkPlugins` / `rehypePlugins` are the deprecated path now that
	// Sätteri is Astro's default processor; the remark pipeline is opted into
	// explicitly through `unified()`.
	markdown: {
		processor: unified({
			remarkPlugins: [
				// Code fences cite real source instead of carrying a copy:
				//   ```nix file=<rootDir>/lib/compose.nix#L10-L24
				// A snippet copied by hand goes stale silently, and a docs site whose
				// examples no longer match the library is worse than one with none.
				// This way a rename or a refactor fails the build.
				[codeImportPlugin, { rootDir: repoRoot, allowImportingFromOutside: true, removeRedundantIndentations: true }],
				// gen's documentation argues from algebra, so the notation has to render.
				remarkMath,
			],
			rehypePlugins: [rehypeKatex],
		}),
	},
	// Weights must cover every weight the stylesheets actually request. Without
	// them only 400 is fetched and the browser synthesises the rest by thickening
	// the 400 glyphs, which reads as blur — most visibly on the sidebar, which
	// renders Victor Mono at 600.
	fonts: [
		{
			provider: fontProviders.google(),
			name: "Victor Mono",
			cssVariable: "--font-victor-mono",
			weights: [400, 600, 700],
			styles: ["normal", "italic"],
		},
		{
			provider: fontProviders.google(),
			name: "JetBrains Mono",
			cssVariable: "--font-jetbrains-mono",
			weights: [400, 600],
			styles: ["normal", "italic"],
		},
	],
	integrations: [
		// Diagrams read the palette directly instead of carrying their own colour
		// scheme. astro-mermaid's autoTheme only ever picks from {light:'default',
		// dark:'dark'} and falls back to the configured base, so a themed base
		// clashes with whatever palette is active ('forest' rendered green on
		// gruvbox brown). Disabling it and styling the 'base' theme through
		// themeCSS means the SVG resolves --sl-color-* at paint time, so diagrams
		// also recolour on a palette switch with no re-render.
		mermaid({
			theme: 'base',
			autoTheme: false,
			mermaidConfig: {
				themeCSS: [
					'.node rect, .node circle, .node ellipse, .node polygon, .node path {',
					'  fill: color-mix(in srgb, var(--sl-color-accent) 12%, var(--sl-color-bg)) !important;',
					'  stroke: color-mix(in srgb, var(--sl-color-accent) 55%, transparent) !important;',
					'}',
					'.node .label, .nodeLabel, .node text { color: var(--sl-color-white) !important; fill: var(--sl-color-white) !important; }',
					'.edgePath .path, .flowchart-link, .messageLine0, .messageLine1 { stroke: var(--sl-color-gray-3) !important; }',
					'.arrowheadPath, marker path, defs marker path { fill: var(--sl-color-gray-3) !important; stroke: none !important; }',
					'.edgeLabel, .edgeLabel p { background: var(--sl-color-bg) !important; color: var(--sl-color-gray-2) !important; fill: var(--sl-color-bg) !important; }',
					'.edgeLabel .label text, .edgeLabel text { fill: var(--sl-color-gray-2) !important; }',
					'.cluster rect { fill: color-mix(in srgb, var(--sl-color-accent) 5%, var(--sl-color-bg)) !important; stroke: var(--sl-color-hairline-light) !important; }',
					'.cluster text, .cluster .label { fill: var(--sl-color-gray-2) !important; color: var(--sl-color-gray-2) !important; }',
				].join('\n'),
			},
		}),
		starlight({
			title: 'gen',
			expressiveCode: {
				plugins: [wholeTokenTextMarkers()],
			},
			// A broken cross-reference is the failure this site is most exposed to:
			// it renders as ordinary text, so nothing about the page says the link
			// went nowhere. Fail the build on one instead.
			plugins: [
				starlightLinksValidator({
					errorOnRelativeLinks: false,
					errorOnLocalLinks: false,
				}),
			],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/sini/gen' }
			],
			// Starlight's own sidebar: a collapsible tree. A custom tab switcher
			// used to live here, where picking a tab silently replaced the panel
			// below it — clicking navigation should expand it or go somewhere, not
			// reshuffle a region you are not looking at.
			sidebar: [
				{
					label: 'Gen',
					items: [
						{ label: 'Overview', slug: 'overview' },
						{ label: 'Why gen', slug: 'motivation' },
						{ label: 'Trust', slug: 'trust' },
						{ label: 'Validation', slug: 'validation' },
						{ label: 'Benchmarks', slug: 'benchmarks' },
					],
				},
				{
					label: 'Understand',
					items: [
						{ label: 'Architecture', slug: 'explanation/architecture' },
						{ label: 'Strata', slug: 'explanation/strata' },
						{ label: 'The Graph Model', slug: 'explanation/graph-model' },
						{ label: 'Policies', slug: 'explanation/policies' },
						{ label: 'Execution', slug: 'explanation/execution' },
					],
				},
				{
					label: 'Start',
					items: [
						{ label: 'Getting Started', slug: 'guides/getting-started' },
						{ label: 'Add Gen to a Flake', slug: 'guides/flake' },
						{ label: 'Your First Graph', slug: 'guides/first-graph' },
					],
				},
				// Grouped by the stratum `lib/mkGenLibs.nix` assigns each member, not
				// alphabetically. That declaration is total — a member cannot join the
				// roster without one — so it is the only grouping that cannot drift out
				// of step with the roster itself.
				{
					label: 'Libraries',
					items: [
						{ label: 'The Roster', slug: 'libraries/roster' },
						{
							label: 'Substrate',
							items: [
								{ label: 'gen-prelude', slug: 'libraries/prelude' },
								{ label: 'gen-identity', slug: 'libraries/identity' },
								{ label: 'gen-algebra', slug: 'libraries/algebra' },
								{ label: 'gen-scope', slug: 'libraries/scope' },
								{ label: 'gen-memo', slug: 'libraries/memo' },
								{ label: 'gen-graph', slug: 'libraries/graph' },
								{ label: 'gen-bind', slug: 'libraries/bind' },
								{ label: 'gen-schema', slug: 'libraries/schema' },
								{ label: 'gen-select', slug: 'libraries/select' },
								{ label: 'gen-dispatch', slug: 'libraries/dispatch' },
								{ label: 'gen-product', slug: 'libraries/product' },
								{ label: 'gen-view', slug: 'libraries/view' },
							],
						},
						{
							label: 'Modules',
							items: [
								{ label: 'gen-types', slug: 'libraries/types' },
								{ label: 'gen-merge', slug: 'libraries/merge' },
							],
						},
						{
							label: 'Aspects',
							items: [
								{ label: 'gen-aspects', slug: 'libraries/aspects' },
								{ label: 'gen-link', slug: 'libraries/link' },
								{ label: 'gen-class', slug: 'libraries/class' },
							],
						},
						{
							label: 'Framework',
							items: [
								{ label: 'gen-settings', slug: 'libraries/settings' },
								{ label: 'gen-assemble', slug: 'libraries/assemble' },
								{ label: 'gen-program', slug: 'libraries/program' },
								{ label: 'gen-inspect', slug: 'libraries/inspect' },
								{ label: 'gen-delivery', slug: 'libraries/delivery' },
							],
						},
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Terminology', slug: 'reference/terminology' },
						{ label: 'References', slug: 'reference/papers' },
						{ label: 'Reading List', slug: 'reference/reading-list' },
						// One page per paper we have written a reading of. Autogenerated
						// because the list grows with the archive, and a hand-kept copy
						// here would be a second place for it to fall out of step.
						{
							label: 'Paper Summaries',
							collapsed: true,
							items: [{ autogenerate: { directory: 'reference/papers' } }],
						},
						{ label: 'Retirements', slug: 'reference/retirements' },
						{ label: 'CI and Checks', slug: 'reference/ci' },
						{ label: 'Tooling', slug: 'reference/tooling' },
					],
				},
			],
			components: {
				Head: './src/components/Head.astro',
				Footer: './src/components/Footer.astro',
				ThemeProvider: './src/components/ThemeProvider.astro',
				ThemeSelect: './src/components/ThemeSelect.astro',
			},
			editLink: {
				baseUrl: 'https://github.com/sini/gen/edit/main/docs/',
			},
			customCss: [
				// KaTeX ships its own stylesheet; rehype-katex only emits the markup.
				'katex/dist/katex.min.css',
				'./src/styles/layout.css',
				'./src/styles/custom.css'
			],
		}),
	],
});
