# Worth: notes for Claude

Worth is a minimal, iPhone-first wealth tracker, hosted on Vercel as a static site and used from the iPhone home screen.

## Architecture

- **Single `index.html`**: all HTML, CSS (one `<style>`) and JS (one IIFE in `<script>`) are inline. No framework, no bundler, no build step, no dependencies. Keep it that way: do not convert to React or add tooling.
- Vercel serves the repo root as is (Framework Preset "Other"). No `vercel.json` is needed because Vercel's static default is `max-age=0, must-revalidate`.
- `manifest.webmanifest` plus icons (`apple-touch-icon.png` 180, `icon-192.png`, `icon-512.png`, `icon-512-maskable.png`), all generated from `icon-1024.png`.
- `dev/` holds the development build's orange icons and its `manifest.webmanifest` ("Worth Dev"). A small script in `<head>` of `index.html` switches the icon links, manifest and title to these when the host is in `DEV_HOSTS` (the dev domain and localhost). If you change an icon, regenerate its orange copy in `dev/` too.
- `sw.js` caches the app shell. `index.html` and navigations are network-first (new deploys appear immediately, cache is the offline fallback). Other shell files are cache-first. **Bump `VERSION` in `sw.js` when you change an icon, the manifest, or add a file to `SHELL`.** Changes to `index.html` alone don't need a bump.
- Storage is `localStorage` only, nothing leaves the device:
  - `worth.v1`: the data object `S` (below).
  - `worth.ui`: UI state `{range, hide, tab, month}` (`tab` is one of `TABS`; an old `mode` key is ignored).
  - Never rename these keys or break the shape; existing users' data must stay readable. `normalize()` fills defaults for older data.
- Settings is the third tab (`renderSettings()` into `#vSettings`): base currency, live exchange rates (read-only), **Copy backup** / **Restore from backup**, and Erase all data. The footer always reads "Saved on this device".
- **Live exchange rates** (`fetchRates()`): Coinbase's public `v2/exchange-rates?currency=EUR` (keyless, CORS), falling back to open.er-api.com. Fetched on start when older than 30 minutes, checked every 5 minutes and on returning to the app. Only the current month takes new rates; past months keep theirs. Offline, the last rates stay. The service worker never touches these cross-origin requests.
- **Icons**: Material Symbols Rounded (Apache-2.0), inlined as SVG paths in `MI` and drawn by `ic(name)`; markup uses `<i data-mi="name">` placeholders that are swapped at startup. No icon font (it would break offline). In the Swift app these become SF Symbols.
- Main flow: mutate `S` → `commit()` → (`syncCurrentMonth()` unless `keepMonth`) → `saveLocal()` → `render()`.

## Environments and workflow

| | Branch | URL | Icon |
| --- | --- | --- | --- |
| Development | `dev` | https://worth-app-dev.vercel.app | Orange, "Worth Dev" |
| Production | `main` | https://worth-app-nine.vercel.app | Green, "Worth" |

- **Every change goes to `dev` first.** Work on the `dev` branch and push it. Vercel deploys it to the dev domain, where the user tests it on the iPhone.
- **Promote to production only when the user says so** after testing: merge `dev` into `main` and push `main` (Vercel deploys `main` to production). Never commit directly to `main`.
- **Sample data lives only in dev.** `dev/sample-data.js` generates a year of mock data (entries, debts, a car and a flat, 13 months). On the dev domain (and localhost) the app seeds it automatically at startup whenever there is no data, so a fresh install, or a reload after **Erase all data**, always shows it. Data you add or edit is never overwritten. There is no button for it.
- **Production never ships that file.** `vercel.json` runs a build command that deletes `dev/sample-data.js` when `VERCEL_ENV=production` (a push to `main`). The dev branch keeps it. To test the stripping without touching production: `vercel deploy --build-env STRIP_DEV_DATA=1` and check that `/dev/sample-data.js` is a 404. Keep any new dev-only data inside `dev/` and add it to that `rm` list.
- The two domains are different origins, so the dev and production apps have separate `localStorage`. Copy data between them with Copy backup / Restore from backup.
- Vercel Authentication is off for this project, so the dev domain and preview URLs are public (the app holds no secrets; data stays on the device).

## Data model

```js
S = {
  v: 1,
  base: "EUR",                 // display currency, one of EUR INR USD GBP CHF
  rates: {EUR:1, INR:110, ...},// units per 1 EUR
  ratesAt: null | ms,
  ratesSrc: "coinbase" | "er-api" | undefined, // where the live rates came from
  accounts: [                  // the user's entries (internal name only)
    {id, name, type, platform, cur, bal, dep?}   // dep: yearly value change in %, physical assets only
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

- `S.accounts` holds the current entries. `type` is a key of `TYPES`: assets `bank stocks etf mf crypto cash property vehicle valuables other`, debts `mortgage loan card` (`liab:true`).
- **Debts** are stored as the positive amount owed and subtracted from every total via `sgn(type)` (`liveTotal()`, `snapTotal()`). Allocation percentages cover assets only; debts get their own row. Old data needs no migration: snapshot items already carry the type.
- **Depreciation**: `property`, `vehicle` and `valuables` have a default yearly change (`TYPES[].dep`: 0, −15, 0) that the entry can override with `dep`. It is applied only when a month is carried over (`carried()` in the update sheet), never silently to stored values.
- **Carry-over**: the update sheet pre-fills a month that isn't recorded yet (or the current month before its check-in, `S.lastCheckin`) from the latest earlier month, with depreciation applied. Editing a past month keeps that month's own rates.
- `S.snaps["YYYY-MM"]` is that month's record. Each item stores the name and type too, so deleted entries still show in history. The current month's snapshot is rebuilt from `S.accounts` on every `commit()`.
- Currencies offered are EUR INR USD GBP CHF (`CURS`). A backup may still contain another code: `fmt()` then formats it by its code instead of crashing, and a currency without a rate in `S.rates` converts 1:1.
- Rates are **units of that currency per 1 EUR** (`conv()` divides by the source rate and multiplies by the base rate). Each month keeps the rates it was saved with.

## Terminology

The user-facing word is **"entry"** (Add entry, New entry, Delete entry, "Removed entry"). Never show "account" in the UI, even though the code uses `S.accounts` / `accountSheet()` internally.

## Design rules

- **Apple Liquid Glass** style on the floating controls layer (tab bar, + button, icon buttons, segmented controls, sheets, toast, pill buttons): translucent glass (`--glass`, `--glass-strong`, `--lens`) with `backdrop-filter` blur, plus a light rim highlight (`::after` with `--rim`/`--rim2`).
- **Content cards are solid**: `.card` uses the opaque `--card` surface (`--card2` inside sheets), with a 26px radius, no blur, no rim and no shadow.
- **Entry rows**: a 40px round icon in the type colour with the white filled Material glyph for the type (`avatar(t)`). The name and the platform/type (or, for a foreign currency, the platform and `≈` base-currency value) sit on the left. The balance and the entry's share of net worth ("Debt" for debts, shown with a minus) sit on the right. Rows are about 66px tall with no dividers. The main list, the month view and the update sheet all use `avatar()`.
- **Accent**: dark green → blue gradient, `--g1` → `--g2`, used via `--grad`. Text on the gradient is **white**. Gradient text uses `.gtext`.
- **Pill-shaped buttons** (`border-radius:999px`); chips and segmented controls are rounded.
- **No top bar.** The large title sits right under the status bar; the hide-amounts eye sits next to the "Today" label above the total (tapping the total also toggles it).
- Bottom bar: a **floating pill** that stretches across the screen with three evenly spaced tabs (Net worth, Monthly, Settings; `TABS`) and a **darker capsule** (`--tabind`) that slides under the selected tab, plus a **round + button** (`.fab`) at its right for Add entry. Pill and button are both 58px, 20px from the sides and about 18px above the bottom edge (`max(10px, safe-area-inset-bottom − 16px)`). The bar does not shrink on scroll. Keep this placement; it follows the reference app the user chose.
- **Monthly shows one month at a time**: a ‹ Month › switcher (arrows or a sideways swipe), the total and change, one Update button, then that month's assets and debts. Keep it minimal: no tables or grids of all months.
- **Chart scrubbing**: dragging (or a short press on touch) shows a floating value label at the point (`#sTip`) and the value in the hero.
- **Spring-based motion**: `--spring`, `--bounce` easings for micro interactions (presses, toggles, the tab indicator squash) and macro ones (sheets growing from the + button, staggered view `rise`, number count-ups, chart draw-in).
- **Keep motion smooth**: animate only `transform` and `opacity`. Don't animate `filter`, `background-position`, or layout properties on large areas, because each frame then has to be repainted. The aura drift is a transformed layer (`.aura-drift`), and the aura pauses while a sheet is open (`body.sheet-open`). The chart's blurred glow fades in, and only the sharp line is drawn with `stroke-dashoffset`. `backdrop-filter` is the most expensive part of the glass look, so don't add more of it to elements that animate.
- The **slowly looping gradient aura** (`.aura`) behind the net worth.
- **Dark mode only, for now.** Colours are CSS variables. The dark palette is the default on `:root`, and the light palette is kept under `:root[data-theme="light"]` for later (nothing sets it yet). Add new colours as variables in both places. `theme-color`, the manifest colours and `color-scheme` are all dark, and the status bar style is `black-translucent`.
- Respect **safe-area insets** (`env(safe-area-inset-*)`) and `viewport-fit=cover`.
- Respect **`prefers-reduced-motion`**: CSS disables animations, and JS checks `matchMedia` before animating numbers, the chart and the tab indicator.
- **iPhone-first**: designed at 390×844, max width 560px, system font (`-apple-system`), compact type: 15px base, 30px large title, 38px net worth, 15/13px entry rows. Text inputs stay at 16px or larger, because iOS zooms into smaller inputs on focus.

## Checking changes

Serve the root (`python3 -m http.server`) and load it in a headless browser at 390×844 in light and dark mode. Check for no console errors, that the manifest and icons load, and that existing `worth.v1` data still renders.
