// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import starlight from '@astrojs/starlight';

import mermaid from 'astro-mermaid';
import { wholeTokenTextMarkers } from './src/ec-whole-token-markers.mjs';

// https://astro.build/config
export default defineConfig({
	// Served from an apex domain, so no `base` path. This is what canonical URLs,
	// the sitemap and Open Graph tags are built against; leaving it unset makes
	// all three either relative or absent.
	site: 'https://gen.wtf',
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
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/sini/gen' }
			],
			// Top-level groups are the tabs in Sidebar.astro, and it assigns each an
			// icon by position, so the order here is also the icon order. Six is the
			// ceiling before a seventh tab renders without one.
			sidebar: [
				{
					label: 'Gen',
					items: [
						{ label: 'Overview', slug: 'overview' },
					],
				},
				{
					label: 'Understand',
					items: [
						{ label: 'Architecture', slug: 'explanation/architecture' },
					],
				},
				{
					label: 'Start',
					items: [
						{ label: 'Getting Started', slug: 'guides/getting-started' },
					],
				},
				{
					label: 'Libraries',
					items: [
						{ label: 'The Roster', slug: 'libraries/roster' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Terminology', slug: 'reference/terminology' },
					],
				},
			],
			components: {
				Head: './src/components/Head.astro',
				Sidebar: './src/components/Sidebar.astro',
				Footer: './src/components/Footer.astro',
				ThemeProvider: './src/components/ThemeProvider.astro',
				ThemeSelect: './src/components/ThemeSelect.astro',
			},
			editLink: {
				baseUrl: 'https://github.com/sini/gen/edit/main/docs/',
			},
			customCss: [
				'./src/styles/layout.css',
				'./src/styles/custom.css'
			],
		}),
	],
});
