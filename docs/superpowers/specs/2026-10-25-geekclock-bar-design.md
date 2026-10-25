# GeekClock Bar — design

Date: 2026-10-25
Status: draft for approval

## Intent

A native macOS menu bar app that shows the user's Claude.ai usage limits at a
glance and keeps their GeekMagic SmallTV-Ultra desk clock showing the same
numbers. It replaces the current setup — a Python script
(`geekclock_claude.py` from
github.com/egerkuzma/geekclock-claude with one patch for the upload quirk) driven by a launchd job, with a
`sessionKey` cookie copied by hand out of DevTools into
`~/.claude_session_key`.

Why: the user wants this to be a normal app — sign in once like any app, type
the clock's IP once, and forget about it. No terminal, no cookie copying, no
Python environment.

## Goals

1. Menu bar shows usage at a glance (two mini bars).
2. Clicking it shows the details (all limits, percentages, reset countdowns,
   clock status).
3. First launch asks the user to sign in to Claude inside the app; after that
   the app keeps the session alive on its own.
4. The only clock configuration is its IP address.
5. The clock shows a new, better-looking face (design "B" below), updated every
   minute.

## Non-goals

- No cloud component; everything runs on this Mac.
- No support for multiple clocks or multiple Claude accounts.
- No notifications / alerts at thresholds.
- No App Store distribution, notarization, or auto-update.
- No Windows/Linux.
- No auto-discovery of the clock on the network (user types the IP).
- No deletion of the old script or launchd plist (left in place, unused).

## Anti-goals (would be a failure even if it "works")

- Asking the user to open DevTools or copy cookies.
- Showing stale numbers as if they were current (stale data must look stale).
- Popups or notifications nagging when the clock is offline.
- A Dock icon or a window that opens on every launch.

## Environment / constraints

- macOS on Apple Silicon; Swift 6 toolchain.
- Clock: GeekMagic SmallTV-Ultra, firmware `Ultra-V9.0.43`, at
  a local IP address, 240×240 display.
- Many users sign in to claude.ai with **Google**. Google blocks sign-in inside
  embedded web views, so the in-app flow uses claude.ai's **"Continue with
  email"** option with the same address (a code is emailed).
- Claude.ai web endpoints are behind Cloudflare bot protection; plain
  `URLSession` requests from native code may be challenged.

## Decided with the user

### Menu bar item — "B: mini bars"

- A small pixel-monster glyph followed by **two stacked thin horizontal bars**,
  no text. Top bar = 5-hour limit, bottom bar = weekly (all models) limit.
- Bar color by percentage: green < 50%, yellow 50–80%, red > 80% (same
  thresholds as the script).
- Signed out or no data → bars grey/empty.

### Dropdown panel (click the menu bar item)

Approved as a draft, roughly:
- **Current (5h)** — percentage, bar, "Resets in 3h 29m".
- **Weekly** — percentage, bar.
- **{Model} weekly** (e.g. "Fable") — percentage, bar, "Weekly resets in 4d".
  Shown only when the API reports a per-model weekly limit. The weekly reset
  line is shown once, under the last weekly bar (they share a reset time).
- Footer: clock status ("● Clock 192.168.1.50 · synced 05:21"), and a
  settings (⚙︎) button.
- When signed out / session expired: bars grey and a **"Sign in again"**
  button.

### Sign-in

- First launch (or after sign-out/expiry) opens a small window with the real
  claude.ai login page in a web view. User picks "Continue with email", enters
  their email address, types the emailed code.
- The app detects successful login and closes the window itself.
- The session persists across app restarts and is refreshed automatically by
  normal use; the user should rarely see the window again.

### Settings window

- **GeekMagic IP** text field (empty by default) + **Test** button showing ✓ or the error.
- **Send to clock** on/off toggle.
- **Open at login** toggle, on by default.
- **Signed in as …** + **Sign out**.

### Clock behavior

- Pushes a rendered 240×240 JPEG to the clock **every minute** (so the reset
  countdown ticks).
- When the IP is set or Test is pressed, the app also puts the clock into
  Photo Album mode showing the app's image (see protocol below), so the user
  never needs the GeekMagic app.
- Mac asleep / app quit → clock keeps the last image; the timestamp in the
  image's corner reveals staleness. Nothing more.
- Clock unreachable → the panel's status line turns red with the reason. No
  popups.

### Clock face — "B: big number"

240×240, black background:
- Header row: pixel monster (left), current time HH:MM in dim grey (right).
- "5-HOUR" small dim label; below it a **huge** 5h percentage (≈64 px, heavy
  weight, colored by threshold) on the left, and on the right "resets in" (dim,
  small) over the countdown ("3h 29m", ≈18 px semibold white).
- A full-width 8 px progress bar for 5h.
- Lower section: "Weekly ··· 13%" row with a slim 5 px bar; "{Model} ··· 0%"
  row with a slim bar (omitted if no per-model limit); then dim "weekly resets
  in 4d".
- Mockup reference: the face B mockup from the design session (not kept).

## Builder's calls (made by Claude, not explicitly confirmed by the user)

- **Stack:** native Swift + SwiftUI app (`MenuBarExtra`, window style), macOS
  14+ deployment target, built as an Xcode project or SwiftPM executable
  wrapped into an `.app`. Menu-bar-only (`LSUIElement = YES`, no Dock icon).
  Ad-hoc signed, installed by copying to `~/Applications`.
- **Fetching through the web view:** keep a hidden `WKWebView` that shares the
  sign-in `WKWebsiteDataStore` (persistent, default store) and run
  `fetch('/api/organizations/{org}/usage', {credentials:'include'})` via
  `callAsyncJavaScript` on a loaded claude.ai page. This rides the real
  browser session, so Cloudflare and cookie refresh are handled like a normal
  browser tab. If this proves unworkable, fallback is reading the
  `sessionKey` cookie from `WKHTTPCookieStore` and calling with `URLSession` —
  builder's choice.
- **Login detection:** poll `GET /api/organizations` (same mechanism); a 200
  with a non-empty array = signed in; take `[0].uuid` as the org id.
- **Polling:** claude.ai usage fetched every 5 minutes (and immediately on
  panel open if the data is > 1 minute old); countdowns and clock image
  re-rendered every minute from the stored reset timestamps.
- **Staleness (user said "you decide"; this is Claude's call):**
  - Data counts as **stale** when the last successful usage fetch is more than
    15 minutes old (i.e. ~3 missed polls).
  - Stale → menu bar bars are drawn dimmed (≈40% opacity); panel shows
    "Updated N min ago" in its status line; the clock face's header shows
    "⚠ HH:MM" with HH:MM = time of the last successful fetch, instead of the
    current time.
  - Fresh → clock header shows current time; panel shows "synced HH:MM".
  - A block whose `resets_at` is in the past and has no newer data is shown
    as "—" (bar empty, grey) everywhere, rather than the pre-reset percentage.
  - A block whose data is older than 12 hours is shown as "—" (same as the
    script). A partial API response keeps previous values for the missing
    blocks (same per-block merge as the script).
- **Signed out / 401 / redirect to login (Claude's call):** stored usage values
  are cleared; menu bar bars grey and empty; panel shows empty grey bars and
  a "Sign in again" button; the clock gets a dedicated signed-out face (black
  background, pixel monster, "Sign in on your Mac" centered, current time in
  the header), pushed once and then on the normal minute cadence.
- **Other errors** (403, 429, 5xx, network): keep last values (subject to the
  staleness rules above) and show the error in the panel status line.
- **Cutover from the old script (Claude's call):** the old launchd job
  `com.geekclock.claude` is currently loaded and uploads the same
  `/image/claude.jpg` every minute. The plan's last step, after the new app
  is confirmed working on the real clock, is to stop it with
  `launchctl bootout gui/$(id -u)/com.geekclock.claude` — asking the user
  first. The plist and script files stay on disk. Until then, test the new
  face with dry renders to a PNG, not by uploading.
- **Open at login:** `SMAppService.mainApp`.
- **Settings storage:** `UserDefaults`. No secrets stored by the app itself —
  the session lives in WebKit's cookie store.
- **Local Network permission:** include `NSLocalNetworkUsageDescription` in
  Info.plist so macOS can prompt for access to the clock.
- **Image rendering:** draw the face with SwiftUI `ImageRenderer` (or Core
  Graphics) at exactly 240×240 px (scale 1), encode JPEG quality ~0.92.
- **App name:** "GeekClock Bar"; bundle id `com.alexpoliukh.geekclockbar`.

## Reference: Claude usage API (from the existing script)

- `GET https://claude.ai/api/organizations` → JSON array; use `[0].uuid`.
- `GET https://claude.ai/api/organizations/{uuid}/usage` → JSON object:
  - `five_hour.utilization` (number, 0–100 percent) and
    `five_hour.resets_at` (ISO 8601).
  - `seven_day.utilization`, `seven_day.resets_at`.
  - `limits[]`: the per-model weekly limit is the first entry with
    `kind == "weekly_scoped"` and a non-empty
    `scope.model.display_name`; fields `percent`, `resets_at`.
  - Any block may be missing or null.
- Sample response: `Tests/GeekClockCoreTests/Fixtures/usage_response_2026-09-04.json` (from geekclock-claude's test fixtures).
- Countdown format: `37m`, `1h 35m`, `4h`, `6d 8h`, `4d`.

## Reference: GeekMagic SmallTV-Ultra HTTP API (verified on the device)

- Upload: `POST http://{ip}/doUpload?dir=/image/` multipart, field `file`,
  filename `claude.jpg`, `image/jpeg`. **Quirk:** the firmware's response has
  two conflicting `Content-Length` headers; strict clients reject it even
  though the upload succeeded. Treat that specific failure as success, or
  verify via `GET /filelist?dir=/image/`.
- Select image: `GET /set?img=%2Fimage%2F%2Fclaude.jpg` → `OK`.
- Photo Album theme: `GET /set?theme=3` → `OK`. Check with `GET /app.json` →
  `{"theme":3}`.
- Album autoplay is off (`/album.json` → `{"autoplay":0,...}`); leave it.
- Device info: `GET /v.json` → `{"m":"SmallTV-Ultra","v":"Ultra-V9.0.43"}`.
- Free space is small (~260 KB); always overwrite the same filename.

## Left to the builder

- Exact SwiftUI layout, spacing, and fonts of the panel and settings (keep
  close to the approved draft; system font is fine).
- Pixel-monster glyph details (port from the script's `_draw_pixel_monster`).
- Error-message wording.
- Project structure, tests (pure logic — parsing, merge, countdown format,
  color thresholds — should be unit tested).
