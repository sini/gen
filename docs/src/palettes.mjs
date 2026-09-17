/**
 * Single source of truth for docs colour palettes.
 *
 * Starlight derives every surface colour from twelve base tokens, so a palette
 * only needs to supply those; `--sl-color-bg`, `-bg-nav`, `-bg-sidebar`,
 * `-bg-inline-code`, `-hairline*` and `-text*` all resolve through `var()`
 * against them (see `@astrojs/starlight/style/props.css`).
 *
 * `origin` is a required discriminated union rather than an optional credit
 * field: a palette copied from an upstream project cannot be added without
 * naming that project, so attribution is a precondition of existing rather
 * than a step someone remembers to do afterwards.
 *
 * @typedef {{ kind: 'original' }
 *          | { kind: 'upstream', project: string, url: string, author: string, license: string }} Origin
 *
 * @typedef {{
 *   white: string, gray1: string, gray2: string, gray3: string, gray4: string,
 *   gray5: string, gray6: string, gray7: string, black: string,
 *   accentLow: string, accent: string, accentHigh: string,
 * }} Tokens
 *
 * Semantic hues drive asides, badges and callouts. Starlight ships fixed
 * defaults for these, so a palette that omits them themes its chrome but leaves
 * every `<Aside>` the same stock blue. Only the base colour is declared here;
 * the `-low` and `-high` shades are derived in `paletteCss()`.
 *
 * @typedef {{ blue: string, purple: string, orange: string, green: string, red: string }} Semantic
 *
 * @typedef {{ id: string, label: string, mode: 'dark' | 'light', origin: Origin,
 *             tokens: Tokens, semantic: Semantic }} Palette
 */

/** @type {Palette[]} */
export const palettes = [
  {
    // The project's own palette. The neutral ramp is the shared house scale;
    // the three accent tokens are what make it gen's rather than den's, and are
    // the knob to turn if the hue should move. `accent` is the one colour the
    // reader meets on every page, so `accentLow` (a background tint) and
    // `accentHigh` (a foreground) have to be re-derived alongside it.
    id: 'gen',
    label: 'gen',
    mode: 'dark',
    origin: { kind: 'original' },
    semantic: { blue: '#7ebae4', purple: '#b3a0e8', orange: '#e8b174', green: '#86c9a0', red: '#e08585' },
    tokens: {
      white: '#f2f5fa',
      gray1: '#d7dde7',
      gray2: '#b4bccb',
      gray3: '#8892a6',
      gray4: '#5b6478',
      gray5: '#333947',
      gray6: '#22262f',
      gray7: '#191c23',
      black: '#14161c',
      accentLow: '#173a36',
      accent: '#5fbfae',
      accentHigh: '#a9e0d6',
    },
  },
  {
    id: 'catppuccin-macchiato',
    label: 'catppuccin macchiato',
    mode: 'dark',
    origin: {
      kind: 'upstream',
      project: 'Catppuccin (Macchiato)',
      url: 'https://github.com/catppuccin/catppuccin',
      author: 'Catppuccin contributors',
      license: 'MIT',
    },
    semantic: { blue: '#8aadf4', purple: '#c6a0f6', orange: '#f5a97f', green: '#a6da95', red: '#ed8796' },
    tokens: {
      white: '#cad3f5',
      gray1: '#b8c0e0',
      gray2: '#a5adcb',
      gray3: '#939ab7',
      gray4: '#6e738d',
      gray5: '#494d64',
      gray6: '#363a4f',
      gray7: '#1e2030',
      black: '#24273a',
      accentLow: '#3b2f52',
      accent: '#c6a0f6',
      accentHigh: '#ddc4fb',
    },
  },
  {
    id: 'tokyo-night',
    label: 'tokyo night',
    mode: 'dark',
    origin: {
      kind: 'upstream',
      project: 'Tokyo Night',
      url: 'https://github.com/folke/tokyonight.nvim',
      author: 'Folke Lemaitre',
      license: 'Apache-2.0',
    },
    semantic: { blue: '#7aa2f7', purple: '#bb9af7', orange: '#ff9e64', green: '#9ece6a', red: '#f7768e' },
    tokens: {
      white: '#c0caf5',
      gray1: '#a9b1d6',
      gray2: '#9aa5ce',
      gray3: '#737aa2',
      gray4: '#565f89',
      gray5: '#414868',
      gray6: '#292e42',
      gray7: '#1f2335',
      black: '#1a1b26',
      accentLow: '#24304d',
      accent: '#7aa2f7',
      accentHigh: '#b4cbfa',
    },
  },
  {
    id: 'gruvbox',
    label: 'gruvbox',
    mode: 'dark',
    origin: {
      kind: 'upstream',
      project: 'gruvbox',
      url: 'https://github.com/morhetz/gruvbox',
      author: 'Pavel Pertsev',
      license: 'MIT',
    },
    semantic: { blue: '#83a598', purple: '#d3869b', orange: '#fe8019', green: '#b8bb26', red: '#fb4934' },
    tokens: {
      white: '#fbf1c7',
      gray1: '#ebdbb2',
      gray2: '#d5c4a1',
      gray3: '#a89984',
      gray4: '#928374',
      gray5: '#665c54',
      gray6: '#3c3836',
      gray7: '#32302f',
      black: '#282828',
      accentLow: '#4a3a12',
      accent: '#fabd2f',
      accentHigh: '#fbe3a0',
    },
  },
  {
    id: 'catppuccin-latte',
    label: 'catppuccin latte',
    mode: 'light',
    origin: {
      kind: 'upstream',
      project: 'Catppuccin (Latte)',
      url: 'https://github.com/catppuccin/catppuccin',
      author: 'Catppuccin contributors',
      license: 'MIT',
    },
    semantic: { blue: '#1e66f5', purple: '#8839ef', orange: '#fe640b', green: '#40a02b', red: '#d20f39' },
    tokens: {
      white: '#4c4f69',
      gray1: '#5c5f77',
      gray2: '#6c6f85',
      gray3: '#8c8fa1',
      gray4: '#acb0be',
      gray5: '#ccd0da',
      gray6: '#dce0e8',
      gray7: '#e6e9ef',
      black: '#eff1f5',
      accentLow: '#e5d5fb',
      accent: '#8839ef',
      accentHigh: '#5b1ca8',
    },
  },
  {
    id: 'rose-pine-dawn',
    label: 'rosé pine dawn',
    mode: 'light',
    origin: {
      kind: 'upstream',
      project: 'Rosé Pine (Dawn)',
      url: 'https://github.com/rose-pine/rose-pine-theme',
      author: 'Rosé Pine contributors',
      license: 'MIT',
    },
    semantic: { blue: '#56949f', purple: '#907aa9', orange: '#ea9d34', green: '#286983', red: '#b4637a' },
    tokens: {
      white: '#575279',
      gray1: '#6f6a8a',
      gray2: '#797593',
      gray3: '#9893a5',
      gray4: '#b5b0bd',
      gray5: '#cecacd',
      gray6: '#dfdad9',
      gray7: '#f4ede8',
      black: '#faf4ed',
      accentLow: '#ebe3f0',
      accent: '#907aa9',
      accentHigh: '#5b4a70',
    },
  },
];

/**
 * Palette applied when the reader has expressed no preference.
 *
 * The dark default is the project's own palette — it is the one a first-time
 * reader sees. There is no original light palette, so light falls to an
 * upstream one.
 */
export const defaults = {
  dark: 'gen',
  light: 'catppuccin-latte',
};

/** `localStorage` key holding the reader's chosen palette id. */
export const storageKey = 'gen-palette';

/** Compact `id -> mode` map, inlined into the head script. */
export const modeMap = Object.fromEntries(palettes.map((p) => [p.id, p.mode]));

const TOKEN_KEYS = [
  'white', 'gray1', 'gray2', 'gray3', 'gray4', 'gray5', 'gray6', 'gray7', 'black',
  'accentLow', 'accent', 'accentHigh',
];
const SEMANTIC_KEYS = ['blue', 'purple', 'orange', 'green', 'red'];
const UPSTREAM_KEYS = ['project', 'url', 'author', 'license'];
const HEX = /^#[0-9a-f]{6}$/i;

/*
 * Checked here rather than in a separate test: this module is imported by every
 * rendered page, so the checks run on `astro build` and `astro dev` and cannot
 * be skipped. A palette short a token would otherwise inherit that colour from
 * whichever palette Starlight's defaults land on — a wrong colour, not a blank
 * one, which is the kind of defect that ships.
 */
const missing = (obj, keys) => keys.filter((k) => !HEX.test(obj?.[k] ?? ''));

for (const [i, p] of palettes.entries()) {
  const at = `palettes[${i}] (${p.id ?? 'unnamed'})`;
  if (!p.id || !p.label) throw new Error(`${at}: id and label are required`);
  if (palettes.findIndex((o) => o.id === p.id) !== i) throw new Error(`${at}: duplicate id`);
  if (p.mode !== 'dark' && p.mode !== 'light') throw new Error(`${at}: mode must be dark or light`);

  const badTokens = missing(p.tokens, TOKEN_KEYS);
  if (badTokens.length) throw new Error(`${at}: missing or malformed tokens: ${badTokens.join(', ')}`);
  const badSemantic = missing(p.semantic, SEMANTIC_KEYS);
  if (badSemantic.length) throw new Error(`${at}: missing or malformed semantic colours: ${badSemantic.join(', ')}`);

  if (p.origin?.kind === 'upstream') {
    const blank = UPSTREAM_KEYS.filter((k) => !p.origin[k]);
    if (blank.length) throw new Error(`${at}: upstream origin is missing ${blank.join(', ')}`);
  } else if (p.origin?.kind !== 'original') {
    throw new Error(`${at}: origin.kind must be 'original' or 'upstream'`);
  }
}

for (const [mode, id] of Object.entries(defaults)) {
  if (modeMap[id] !== mode) throw new Error(`defaults.${mode}: no ${mode} palette with id '${id}'`);
}

/**
 * Render every palette as an unlayered CSS rule.
 *
 * Starlight wraps its own declarations in `@layer starlight.*`, and unlayered
 * CSS outranks layered CSS regardless of specificity, so these win without
 * needing `!important` or a specificity ladder.
 *
 * @returns {string}
 */
export function paletteCss() {
  // `-low` is a background tint and `-high` a foreground, so each is mixed
  // toward the palette's own background and strongest text colour. Those two
  // tokens swap roles between light and dark palettes, so the shades invert for
  // light palettes without a second formula.
  const shades = (name, hex) =>
    [
      `--sl-color-${name}:${hex};`,
      `--sl-color-${name}-low:color-mix(in srgb, ${hex} 22%, var(--sl-color-black));`,
      `--sl-color-${name}-high:color-mix(in srgb, ${hex} 72%, var(--sl-color-white));`,
    ].join('');

  return palettes
    .map(({ id, tokens: t, semantic: s }) =>
      [
        `:root[data-palette="${id}"], [data-palette="${id}"] ::backdrop {`,
        ...Object.keys(s).map((name) => shades(name, s[name])),
        `--sl-color-white:${t.white};`,
        `--sl-color-gray-1:${t.gray1};`,
        `--sl-color-gray-2:${t.gray2};`,
        `--sl-color-gray-3:${t.gray3};`,
        `--sl-color-gray-4:${t.gray4};`,
        `--sl-color-gray-5:${t.gray5};`,
        `--sl-color-gray-6:${t.gray6};`,
        `--sl-color-gray-7:${t.gray7};`,
        `--sl-color-black:${t.black};`,
        `--sl-color-accent-low:${t.accentLow};`,
        `--sl-color-accent:${t.accent};`,
        `--sl-color-accent-high:${t.accentHigh};`,
        `}`,
      ].join('')
    )
    .join('\n');
}

/**
 * Attribution rows for palettes taken from an upstream project.
 *
 * @returns {{ label: string, project: string, url: string, author: string, license: string }[]}
 */
export function attributions() {
  return palettes
    .filter((p) => p.origin.kind === 'upstream')
    .map(({ label, origin }) => ({
      label,
      ...Object.fromEntries(UPSTREAM_KEYS.map((k) => [k, origin[k]])),
    }));
}

/**
 * Parse-check an inline script at build time and return it unchanged.
 *
 * The palette scripts are template strings written straight into the page with
 * `set:html`, so no part of the toolchain ever parses them — a typo ships and
 * surfaces only in the reader's console, with the palette switcher silently
 * dead. `new Function` compiles the body without running it.
 *
 * @param {string} source
 * @returns {string}
 */
export function inlineScript(source) {
  new Function(source);
  return source;
}

/**
 * Pre-paint boot script, and the only definition of "which palette is active".
 *
 * It runs in the head so the palette is settled before anything renders, and
 * publishes `window.__palette` so the overlay resolves, reads and writes the
 * preference through the same code rather than a second copy that can drift out
 * of step with this one. Every `localStorage` touch is guarded: the API throws
 * outright when site data is blocked, and an unguarded read there would take
 * the palette switcher down with it.
 *
 * @returns {string}
 */
export function bootScript() {
  return inlineScript(`(function(){
var M=${JSON.stringify(modeMap)},D=${JSON.stringify(defaults)},K=${JSON.stringify(storageKey)};
var r=document.documentElement;
function read(){try{var s=localStorage.getItem(K);return s&&M[s]?s:null}catch(e){return null}}
function write(id){try{localStorage.setItem(K,id)}catch(e){}}
function fallback(){return matchMedia("(prefers-color-scheme: light)").matches?D.light:D.dark}
function apply(id){r.dataset.palette=id;r.dataset.theme=M[id]}
window.__palette={modes:M,read:read,write:write,fallback:fallback,apply:apply,
active:function(){return read()||fallback()}};
apply(window.__palette.active());
})();`);
}
