# Worth for iPhone (Swift)

The native version of Worth, built with SwiftUI. It keeps the web app's data in the **same format** (`worth.v1`), so a
backup from the web app restores straight into the native app, and back.

## Open and run

1. Open `ios/Worth.xcodeproj` in Xcode.
2. Pick an iPhone simulator at the top and press **Run** (⌘R).
3. To see realistic data: **Settings → Developer → Load sample data** (Debug builds only).

Files under `ios/Worth/` are picked up automatically (the project uses a synced folder), so new Swift files need no
project changes.

## On your own iPhone (free, no paid developer account)

1. Xcode → Settings → Accounts → add your Apple ID. This gives you a free "Personal Team".
2. Select the **Worth** target → **Signing & Capabilities** → Team: your Personal Team. If Xcode says the bundle
   identifier is taken, change `me.surath.worth` to something unique to you.
3. Connect the iPhone (cable, or the same Wi-Fi after the first time), pick it at the top, press **Run**.
4. First time on the phone: turn on **Settings → Privacy & Security → Developer Mode** (it restarts), then trust your
   profile under **Settings → General → VPN & Device Management**.

Free-account limits: the app stops opening after **7 days** (connect and press Run again, your data stays), at most 3
of your own apps on the phone, no TestFlight, and no iCloud/CloudKit, push notifications or Sign in with Apple. Those
come with the paid Apple Developer Program ($99/year), needed later for TestFlight and the App Store.

## Layout

| Path | What |
| --- | --- |
| `Worth/WorthApp.swift` | App entry, tab bar (Net worth · Monthly · Settings), rate refresh on launch/foreground |
| `Worth/Model/WorthData.swift` | The `worth.v1` data shape (Codable, lenient decoding), month helpers |
| `Worth/Model/Catalog.swift` | Currencies, entry types, groups and colours (mirrors the web app), SF Symbols, icon mapping |
| `Worth/Model/Store.swift` | State, JSON persistence, totals, grouping (`split`), backup, live rates, money formatting |
| `Worth/Views/` | Net worth, entry sheet + icon picker, Monthly, Settings |
| `Worth/Resources/DevSample.json` | Sample data made by `dev/sample-data.js` (Debug "Load sample data") |

To refresh the sample after changing `dev/sample-data.js`:

```bash
node --input-type=module -e 'import {makeSample} from "./dev/sample-data.js"; import {writeFileSync} from "node:fs"; writeFileSync("ios/Worth/Resources/DevSample.json", JSON.stringify(makeSample()))'
```
