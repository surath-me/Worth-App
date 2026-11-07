# Worth: notes for Claude

Worth is a minimal, iPhone-first wealth tracker, hosted on Vercel as a static site and used from the iPhone home screen.

## Architecture

- **Single `index.html`**: all HTML, CSS (one `<style>`) and JS (one IIFE in `<script>`) are inline. No framework, no bundler, no build step, no dependencies. Keep it that way: do not convert to React or add tooling.
- Vercel serves the repo root as is (Framework Preset "Other"). No `vercel.json` is needed because Vercel's static default is `max-age=0, must-revalidate`.
- `manifest.webmanifest` plus icons (`apple-touch-icon.png` 180, `icon-192.png`, `icon-512.png`, `icon-512-maskable.png`), all generated from `icon-1024.png`.
- `sw.js` caches the app shell. `index.html` and navigations are network-first (new deploys appear immediately, cache is the offline fallback). Other shell files are cache-first. **Bump `VERSION` in `sw.js` when you change an icon, the manifest, or add a file to `SHELL`.** Changes to `index.html` alone don't need a bump.
- Storage is `localStorage` only, nothing leaves the device:
  - `worth.v1`: the data object `S` (below).
  - `worth.ui`: UI state `{range, hide, tab, mode, month}`.
  - Never rename these keys or break the shape; existing users' data must stay readable. `normalize()` fills defaults for older data.
- Settings has **Copy backup** (JSON of `S` to the clipboard) and **Restore from backup**. The footer always reads "Saved on this device".
- Main flow: mutate `S` → `commit()` → (`syncCurrentMonth()` unless `keepMonth`) → `saveLocal()` → `render()`.

## Data model

```js
S = {
  v: 1,
  base: "EUR",                 // display currency, one of EUR INR USD GBP CHF
  rates: {EUR:1, INR:110, ...},// units per 1 EUR
  ratesAt: null | ms,
  accounts: [                  // the user's entries (internal name only)
    {id, name, type, platform, cur, bal}
  ],
  snaps: {                     // keyed by "YYYY-MM"
    "2026-11": {
      items: { [id]: [balance, currency, type, name] },
      rates: {...}             // the rates used that month
    }
  },
  lastCheckin: "YYYY-MM" | null,
  updatedAt: ms
}
```

- `S.accounts` holds the current entries. `type` is one of `bank stocks etf mf crypto cash other`.
- `S.snaps["YYYY-MM"]` is that month's record. Each item stores the name and type too, so deleted entries still show in history. The current month's snapshot is rebuilt from `S.accounts` on every `commit()`.
- Currencies offered are EUR INR USD GBP CHF (`CURS`). A backup may still contain another code: `fmt()` then formats it by its code instead of crashing, and a currency without a rate in `S.rates` converts 1:1.
- Rates are **units of that currency per 1 EUR** (`conv()` divides by the source rate and multiplies by the base rate). Each month keeps the rates it was saved with.

## Terminology

The user-facing word is **"entry"** (Add entry, New entry, Delete entry, "Removed entry"). Never show "account" in the UI, even though the code uses `S.accounts` / `accountSheet()` internally.

## Design rules

- **Apple Liquid Glass** style on the floating controls layer (tab bar, + button, icon buttons, segmented controls, sheets, toast, pill buttons): translucent glass (`--glass`, `--glass-strong`, `--lens`) with `backdrop-filter` blur, plus a light rim highlight (`::after` with `--rim`/`--rim2`).
- **Content cards are solid**: `.card` and month tiles use the opaque `--card` surface (`--card2` inside sheets), with large radii (26px cards, 22px tiles), no blur, no rim and no shadow.
- **Entry rows**: a 46px round icon in the type colour with a white line glyph for the type (`TYPE_ICON`, rendered by `avatar(t)`). The name and the platform/type (or, for a foreign currency, the platform and `≈` base-currency value) sit on the left. The balance and the entry's share of net worth sit on the right. Rows are about 76px tall with no dividers. The main list, the month detail and the update sheet all use `avatar()`.
- **Accent**: dark green → blue gradient, `--g1` → `--g2`, used via `--grad`. Text on the gradient is **white**. Gradient text uses `.gtext`.
- **Pill-shaped buttons** (`border-radius:999px`); chips and segmented controls are rounded.
- Bottom bar: a compact **two-tab bar** (Net worth, Monthly) with a sliding lens indicator, next to a **round + button** (`.fab`) for Add entry. The bar shrinks on scroll (`.tabbar.min`).
- **Spring-based motion**: `--spring`, `--bounce` easings for micro interactions (presses, toggles, the tab indicator squash) and macro ones (sheets growing from the + button, staggered view `rise`, number count-ups, chart draw-in).
- **Keep motion smooth**: animate only `transform` and `opacity`. Don't animate `filter`, `background-position`, or layout properties on large areas, because each frame then has to be repainted. The aura drift is a transformed layer (`.aura-drift`), and the aura pauses while a sheet is open (`body.sheet-open`). The chart's blurred glow fades in, and only the sharp line is drawn with `stroke-dashoffset`. `backdrop-filter` is the most expensive part of the glass look, so don't add more of it to elements that animate.
- The **slowly looping gradient aura** (`.aura`) behind the net worth.
- **Dark mode only, for now.** Colours are CSS variables. The dark palette is the default on `:root`, and the light palette is kept under `:root[data-theme="light"]` for later (nothing sets it yet). Add new colours as variables in both places. `theme-color`, the manifest colours and `color-scheme` are all dark, and the status bar style is `black-translucent`.
- Respect **safe-area insets** (`env(safe-area-inset-*)`) and `viewport-fit=cover`.
- Respect **`prefers-reduced-motion`**: CSS disables animations, and JS checks `matchMedia` before animating numbers, the chart and the tab indicator.
- **iPhone-first**: designed at 390×844, max width 560px, system font (`-apple-system`), compact type: 15px base, 28px large title, 38px net worth, 15/13px entry rows. Text inputs stay at 16px or larger, because iOS zooms into smaller inputs on focus.

## Checking changes

Serve the root (`python3 -m http.server`) and load it in a headless browser at 390×844 in light and dark mode. Check for no console errors, that the manifest and icons load, and that existing `worth.v1` data still renders.
