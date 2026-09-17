import { defineCollection, z } from 'astro:content';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({
		loader: docsLoader(),
		schema: docsSchema({
			extend: z.object({
				/**
				 * The markdown this page adapts, as a repository-relative path — or
				 * `<repo>:<path>` for a roster member's own documentation.
				 *
				 * Recorded in frontmatter rather than in prose so the corpus can be
				 * swept: the ecosystem's documentation is ~28k lines across 97 files,
				 * and the failure mode of adapting it by hand is a source document
				 * that no page claims and nobody notices is missing.
				 */
				source: z.array(z.string()).optional(),
			}),
		}),
	}),
	// Declared even though the site is single-language: Starlight looks the
	// collection up unconditionally and warns on every build when it is absent.
	// `src/content/i18n/` is where UI string overrides go.
	i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
};
