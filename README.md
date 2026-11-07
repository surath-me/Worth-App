# Worth

A minimal, iPhone-first wealth tracker. Add your entries (bank accounts, brokers, funds, cash), update their balances once a month, and Worth shows your net worth over time, your allocation and a month-by-month history.

It is a single static web app: `index.html` holds all the HTML, CSS and JavaScript. There is no framework, no build step and no server. Your data lives in your browser's `localStorage` on your device and never leaves it. Use **Settings → Copy backup** to keep a copy, and **Restore from backup** to bring it back on another device.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole app |
| `manifest.webmanifest` | Web app manifest (name, colours, icons) |
| `sw.js` | Service worker that caches the app so it opens offline |
| `apple-touch-icon.png` | 180×180 home screen icon for iOS |
| `icon-192.png`, `icon-512.png` | Manifest icons |
| `icon-512-maskable.png` | Maskable icon with safe-zone padding (Android) |
| `icon-1024.png` | Source artwork for all icons |

## Run locally

Any static file server works. From the repo root:

```sh
python3 -m http.server 8000
```

Then open http://localhost:8000. The service worker only registers on `localhost` or HTTPS.

## Deploy on Vercel

1. Push this repo to GitHub.
2. In Vercel, choose **Add New → Project** and import the repo.
3. Set **Framework Preset** to **Other**. Leave the build command and output directory empty, so Vercel serves the repo root as is.
4. Click **Deploy**.

Every push to `main` deploys again. No `vercel.json` is needed: Vercel serves static files with `Cache-Control: public, max-age=0, must-revalidate`, so `index.html` and `sw.js` are always revalidated. The service worker loads `index.html` network-first, so a new deploy shows up on the next launch while online.

## Add it to your iPhone home screen

1. Open your Vercel URL in **Safari**.
2. Tap the **Share** button.
3. Tap **Add to Home Screen**, then **Add**.

Worth then opens full screen from its icon, like an app, and works offline after the first visit.

Data is stored per browser. The home screen app and a Safari tab may not share storage, so to move your data between them, use **Copy backup** in one and **Restore from backup** in the other.
