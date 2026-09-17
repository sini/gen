import { defineCollection } from 'astro:content';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
	// Declared even though the site is single-language: Starlight looks the
	// collection up unconditionally and warns on every build when it is absent.
	// `src/content/i18n/` is where UI string overrides go.
	i18n: defineCollection({ loader: i18nLoader(), schema: i18nSchema() }),
};
