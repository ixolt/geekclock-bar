# GeekClock Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu bar app that shows Claude.ai usage as two mini bars and pushes a "big number" usage face to a GeekMagic SmallTV-Ultra clock every minute.

**Architecture:** One SwiftPM package with two targets. `GeekClockCore` (library) holds everything testable without a UI: API parsing, the usage state model (merge, staleness, unknown blocks), formatting, colour levels, the clock-face view model, the clock face renderer, and the GeekMagic HTTP client. `GeekClockBar` (executable) is the SwiftUI app: `MenuBarExtra`, the hidden/visible `WKWebView` Claude session, settings, timers. A shell script wraps the executable into an ad-hoc signed `.app`.

**Tech Stack:** Swift 6.4, SwiftUI (`MenuBarExtra`, `ImageRenderer`), WebKit (`WKWebView`, `callAsyncJavaScript`), ServiceManagement (`SMAppService`), Swift Testing (`import Testing`). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-25-geekclock-bar-design.md` (read it before starting any task).

## Global Constraints

- Project root: the repository root (all paths below are relative to it). Git repo created in Task 1.
- Toolchain: always prefix `swift` commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the default `xcode-select` points at Command Line Tools, which lacks the test frameworks).
- Deployment target macOS 14 (`.macOS(.v14)`); Apple Silicon.
- App name "GeekClock Bar"; executable/product `GeekClockBar`; bundle id `com.alexpoliukh.geekclockbar`; installed to `~/Applications/GeekClockBar.app`.
- Menu-bar-only: `LSUIElement = YES`, no Dock icon, no window on launch (except the sign-in window when signed out).
- Info.plist must include `NSLocalNetworkUsageDescription` = "GeekClock Bar sends your usage image to your GeekMagic clock on the local network."
- Colour levels (same as the script): `< 50` green, `>= 50 && < 80` yellow, `>= 80` red, unknown → grey. RGB: green (0,240,60), yellow (255,210,40), red (240,70,80), grey/dim (150,150,160), bar track (45,45,55), monster (255,95,50), monster eyes (20,15,18).
- Usage fetched every 300 s, and immediately on panel open when the last attempt is older than 60 s. Clock image re-rendered and pushed every 60 s.
- Stale: last successful fetch older than 900 s (15 min). Block unknown ("—"): missing, `fetchedAt` older than 43200 s (12 h), or `resetsAt` in the past.
- Clock upload: `POST http://{ip}/doUpload?dir=/image/`, multipart field `file`, filename `claude.jpg`, `image/jpeg`, JPEG quality 0.92, exactly 240×240 px. Select: `GET /set?img=%2Fimage%2F%2Fclaude.jpg`; theme: `GET /set?theme=3`; both answer body `OK`.
- Countdown copy: `37m`, `1h 35m`, `4h`, `6d 8h`, `4d`; zero/negative → empty string.
- No popups or notifications for errors; errors go in the panel status line.
- The old launchd job `com.geekclock.claude` keeps running until Task 9. Before Task 9, never upload to the real clock; check faces with PNG previews.
- Do not delete the old geekclock-claude setup or its LaunchAgent `com.geekclock.claude`.

## Review Focus

1. Firmware's duplicate `Content-Length` reply: URLSession may fail the upload request even though the clock stored the file — expect success after confirming via `/filelist`. (Test in Task 4.)
2. `resets_at` with 6-digit fractional seconds and `+00:00` offset (`2026-09-04T18:49:59.978553+00:00`) — must parse; `ISO8601DateFormatter` can reject >3 fraction digits. (Test in Task 1.)
3. A block that reset while fetches were failing must show "—", not the old red percentage. (Test in Task 2.)
4. Session expiring while running: a 401 must flip to signed-out, clear stored values, and the clock must get the signed-out face, not frozen numbers. (Test in Task 2 for the state; Task 7 wires it.)
5. Empty or invalid IP / clock offline: tick must not crash or block the UI; status line shows the error, menu bar keeps working. (Test in Task 4 for invalid host; Task 7 for status.)

---

### Task 1: Package scaffold and usage API parsing

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `*.app`, `.swiftpm/`)
- Create: `Sources/GeekClockCore/UsageParsing.swift`
- Create: `Sources/GeekClockBar/main.swift` (placeholder `print("GeekClockBar")`, replaced in Task 5)
- Create: `Tests/GeekClockCoreTests/UsageParsingTests.swift`
- Create: `Tests/GeekClockCoreTests/Fixtures/usage_response_2026-09-04.json` (copy from geekclock-claude's `tests/fixtures/`)

**Interfaces:**
- Produces:
  - `public enum BlockKind: String, CaseIterable, Codable, Sendable { case fiveHour, sevenDay, modelWeekly }`
  - `public struct ParsedBlock: Equatable, Sendable { public var percent: Double; public var resetsAt: Date?; public var label: String? }`
  - `public func parseUsage(_ data: Data) throws -> [BlockKind: ParsedBlock]`
  - `public func parseISODate(_ string: String) -> Date?`
  - `public enum UsageParseError: Error { case notAnObject }`
  - `public func parseOrganizationID(_ data: Data) -> String?` — `[0].uuid` of a JSON array, nil otherwise.

- [ ] **Step 1: `git init`, create `Package.swift`** with targets `GeekClockCore` (library), `GeekClockBar` (executable, depends on core), `GeekClockCoreTests` (test target, `resources: [.copy("Fixtures")]`), platform `.macOS(.v14)`, swift-tools-version 6.0. Copy the fixture.

- [ ] **Step 2: Write the failing tests** in `UsageParsingTests.swift` (Swift Testing):
  - `fixtureParsesAllThreeBlocks`: `parseUsage(fixture)` → `fiveHour.percent == 37`, `sevenDay.percent == 27`, `modelWeekly.percent == 32`, `modelWeekly.label == "Fable"`, `fiveHour.resetsAt == parseISODate("2026-09-04T18:49:59.978Z")` within 0.001 s.
  - `parsesSixDigitFractionWithOffset`: `parseISODate("2026-09-04T18:49:59.978553+00:00")` is non-nil and equals `2026-09-04T18:49:59Z` + 0.978553 s (±0.001).
  - `parsesWithoutFraction`: `parseISODate("2026-09-06T17:59:59Z")` non-nil.
  - `nullAndMissingBlocksAreAbsent`: `{"five_hour":null,"seven_day":{"utilization":5,"resets_at":null}}` → keys == `[.sevenDay]`, `resetsAt == nil`.
  - `boolOrStringUtilizationIsIgnored`: `{"five_hour":{"utilization":true},"seven_day":{"utilization":"7"}}` → empty dict.
  - `modelWeeklyNeedsDisplayName`: `limits` with a `weekly_scoped` entry whose `scope` is null, then one with `display_name` "Opus" percent 12 → `modelWeekly.label == "Opus"`, percent 12.
  - `nonObjectThrows`: `parseUsage(Data("[]".utf8))` throws `UsageParseError.notAnObject`.
  - `orgIdFromArray`: `parseOrganizationID(Data(#"[{"uuid":"abc"},{"uuid":"def"}]"#.utf8)) == "abc"`; `"[]"` → nil; `{}` → nil.

- [ ] **Step 3: Run** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — Expected: compile failure (symbols undefined).

- [ ] **Step 4: Implement** in `UsageParsing.swift` with `JSONSerialization`. Mapping: `five_hour.utilization`/`resets_at`, `seven_day.utilization`/`resets_at`, `modelWeekly` = first `limits[]` entry with `kind == "weekly_scoped"` and non-empty `scope.model.display_name` (fields `percent`, `resets_at`). A number is `NSNumber` that is not a CFBoolean. `parseISODate`: try `Date.ISO8601FormatStyle(includingFractionalSeconds: true)`, then without fraction; if both fail and the string has >3 fraction digits, truncate the fraction to 3 digits and retry.

- [ ] **Step 5: Run tests** — Expected: all pass.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: package scaffold and usage API parsing"` (include the spec and this plan in the first commit).

---

### Task 2: Usage state model (merge, staleness, unknown blocks, signed-out)

**Files:**
- Create: `Sources/GeekClockCore/UsageState.swift`
- Test: `Tests/GeekClockCoreTests/UsageStateTests.swift`

**Interfaces:**
- Consumes: `BlockKind`, `ParsedBlock` (Task 1).
- Produces:
  - `public struct StoredBlock: Codable, Equatable, Sendable { public var percent: Double; public var resetsAt: Date?; public var label: String?; public var fetchedAt: Date }`
  - `public struct UsageState: Codable, Equatable, Sendable { public var blocks: [BlockKind: StoredBlock]; public var lastSuccess: Date?; public static let empty: UsageState }`
  - `public func merging(_ fresh: [BlockKind: ParsedBlock], at now: Date) -> UsageState` — blocks present in `fresh` replace stored ones with `fetchedAt = now`; absent blocks keep the old value and old `fetchedAt`; `lastSuccess = now`.
  - `public enum BlockDisplay: Equatable, Sendable { case value(percent: Double, resetsInMinutes: Int?, label: String?); case unknown }`
  - `public func display(_ kind: BlockKind, now: Date) -> BlockDisplay`
  - `public func isStale(now: Date) -> Bool`
  - `public static let staleAfter: TimeInterval = 900`, `public static let hideAfter: TimeInterval = 43200`

- [ ] **Step 1: Write the failing tests** (`let t0 = Date(timeIntervalSince1970: 1_800_000_000)`):
  - `mergeKeepsMissingBlocks`: state with sevenDay 13 fetched at t0; merge `[.fiveHour: 7]` at t0+300 → fiveHour 7 `fetchedAt == t0+300`, sevenDay 13 `fetchedAt == t0`, `lastSuccess == t0+300`.
  - `displayShowsValueAndCountdown`: fiveHour 7, resetsAt t0+209*60 (209 min), fetched t0 → `display(.fiveHour, now: t0) == .value(percent: 7, resetsInMinutes: 209, label: nil)`.
  - `blockOlderThan12hIsUnknown`: fetched t0, `now = t0 + 43201` → `.unknown`; `now = t0 + 43199` → `.value`.
  - `blockPastResetIsUnknown`: fiveHour 90, resetsAt t0+60; `now = t0+61` → `.unknown`.
  - `missingBlockIsUnknown`: `UsageState.empty.display(.modelWeekly, now: t0) == .unknown`.
  - `staleAfter15Minutes`: lastSuccess t0 → `isStale(now: t0+900) == false`, `isStale(now: t0+901) == true`; `UsageState.empty.isStale(now: t0) == true`.
  - `codableRoundTrip`: encode/decode a state with all three blocks equals itself.

- [ ] **Step 2: Run** `swift test` (with `DEVELOPER_DIR`) — Expected: FAIL, symbols undefined.

- [ ] **Step 3: Implement** in `UsageState.swift`. `resetsInMinutes = max(0, Int(resetsAt - now) / 60)`; nil when `resetsAt` nil.

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: usage state model with staleness rules`.

---

### Task 3: Formatting, colour levels, and the clock-face view model

**Files:**
- Create: `Sources/GeekClockCore/Formatting.swift`
- Create: `Sources/GeekClockCore/ClockFaceModel.swift`
- Test: `Tests/GeekClockCoreTests/FormattingTests.swift`, `Tests/GeekClockCoreTests/ClockFaceModelTests.swift`

**Interfaces:**
- Consumes: `UsageState`, `BlockDisplay`, `BlockKind` (Task 2).
- Produces:
  - `public func formatCountdown(minutes: Int) -> String`
  - `public enum UsageLevel: Equatable, Sendable { case green, yellow, red, unknown }`, `public func usageLevel(_ percent: Double?) -> UsageLevel`
  - `public func formatPercent(_ display: BlockDisplay) -> String` — `.value(7.0…)` → `"7%"` (rounded, no decimals), `.unknown` → `"—"`.
  - `public struct FaceRow: Equatable, Sendable { public var title: String; public var percentText: String; public var fraction: Double; public var level: UsageLevel }`
  - `public enum ClockFace: Equatable, Sendable { case usage(UsageFace); case signedOut(headerTime: String) }`
  - `public struct UsageFace: Equatable, Sendable { public var headerText: String; public var isStale: Bool; public var fiveHour: FaceRow; public var fiveHourCountdown: String; public var weekly: FaceRow; public var model: FaceRow?; public var weeklyResetText: String }`
  - `public func makeClockFace(state: UsageState?, now: Date, timeZone: TimeZone) -> ClockFace` — `state == nil` means signed out.

- [ ] **Step 1: Write the failing tests:**
  - `countdownFormats`: 37→`"37m"`, 95→`"1h 35m"`, 240→`"4h"`, 9120→`"6d 8h"`, 5760→`"4d"`, 0→`""`, -5→`""`.
  - `levels`: nil→`.unknown`, 0→`.green`, 49.9→`.green`, 50→`.yellow`, 79.9→`.yellow`, 80→`.red`, 100→`.red`.
  - `percentText`: `.value(percent: 7.0, …)`→`"7%"`, `13.4`→`"13%"`, `.unknown`→`"—"`.
  - `freshFaceUsesCurrentTime` (timeZone `Europe/Kyiv`, now = 2026-10-25T03:30:00Z → local 05:30): fiveHour 7 resets in 209 min, sevenDay 13, modelWeekly 0 label "Fable" resets in 5760 min, lastSuccess = now − 60 → `headerText == "05:30"`, `isStale == false`, `fiveHour.percentText == "7%"`, `fiveHour.fraction == 0.07`, `fiveHourCountdown == "3h 29m"`, `weekly.title == "Weekly"`, `model?.title == "Fable"`, `weeklyResetText == "weekly resets in 4d"`.
  - `staleFaceShowsLastSuccessWithWarning`: same but lastSuccess = 2026-10-25T03:12:00Z, now 03:30Z → `headerText == "⚠ 05:12"`, `isStale == true`.
  - `noModelLimitOmitsRow`: no modelWeekly → `model == nil`; weekly reset text uses sevenDay's reset.
  - `unknownBlockRendersDash`: fiveHour past reset → `fiveHour.percentText == "—"`, `fraction == 0`, `level == .unknown`, `fiveHourCountdown == ""`.
  - `signedOutFace`: `makeClockFace(state: nil, now:…, timeZone: Kyiv) == .signedOut(headerTime: "05:30")`.

- [ ] **Step 2: Run tests** — Expected: FAIL, symbols undefined.

- [ ] **Step 3: Implement.** Weekly reset text = `"weekly resets in " + countdown` from the last weekly row that has a countdown (modelWeekly, else sevenDay); empty when none. `fraction = min(max(percent/100, 0), 1)`. Header time format `HH:mm` in the given time zone.

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: formatting, levels and clock face model`.

---

### Task 4: Clock face renderer and GeekMagic client

**Files:**
- Create: `Sources/GeekClockCore/ClockFaceView.swift` (SwiftUI views for both faces + pixel monster)
- Create: `Sources/GeekClockCore/ClockFaceRenderer.swift`
- Create: `Sources/GeekClockCore/GeekMagicClient.swift`
- Test: `Tests/GeekClockCoreTests/ClockFaceRendererTests.swift`, `Tests/GeekClockCoreTests/GeekMagicClientTests.swift`

**Interfaces:**
- Consumes: `ClockFace`, `UsageFace`, `FaceRow`, `UsageLevel` (Task 3).
- Produces:
  - `@MainActor public func renderClockFaceJPEG(_ face: ClockFace) -> Data?` (240×240 px at scale 1, quality 0.92)
  - `@MainActor public func renderClockFacePNG(_ face: ClockFace) -> Data?` (for previews)
  - `public struct PixelMonster: View { public init(scale: CGFloat) }` — 15×10 sprite from the script's `_draw_pixel_monster` (body (255,95,50), eyes (20,15,18)); reused by the menu bar icon in Task 7.
  - `public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, Int) }`
  - `public struct URLSessionTransport: HTTPTransport` (timeout 5 s, ephemeral session)
  - `public enum ClockError: Error, Equatable { case invalidAddress; case badReply(String); case unreachable(String) }`
  - `public struct GeekMagicClient: Sendable { public init(host: String, transport: HTTPTransport); public func upload(jpeg: Data) async throws; public func showAppImage() async throws }`

- [ ] **Step 1: Write the failing tests:**
  - Renderer: `jpegIs240Square` — render a `.usage` face from Task 3's fresh fixture and `.signedOut(headerTime: "05:30")`; decode with `NSBitmapImageRep(data:)` → `pixelsWide == 240 && pixelsHigh == 240`. `writesPreviews` — write PNGs of fresh, stale, unknown-5h, no-model and signed-out faces to `.build/previews/<name>.png` (no assertion beyond non-nil data).
  - Client, with a `FakeTransport` recording requests and returning scripted results:
    - `uploadBuildsMultipart`: `upload(jpeg: Data([1,2,3]))` → one request, `POST`, URL `http://192.168.1.50/doUpload?dir=/image/`, `Content-Type` starts with `multipart/form-data; boundary=`, body contains `name="file"; filename="claude.jpg"` and `Content-Type: image/jpeg`.
    - `uploadTreatsUnparseableReplyAsSuccessWhenFileListed`: first send throws `URLError(.cannotParseResponse)`, then `GET /filelist?dir=/image/` returns 200 with body containing `claude.jpg` → no throw.
    - `uploadFailsWhenNotListed`: same error but filelist lacks `claude.jpg` → throws `ClockError.badReply`.
    - `uploadUnreachable`: send throws `URLError(.cannotConnectToHost)` → `ClockError.unreachable`.
    - `showAppImageCallsBothEndpoints`: requests in order `GET /set?img=%2Fimage%2F%2Fclaude.jpg`, `GET /set?theme=3`; non-`OK` body → `ClockError.badReply`.
    - `invalidHostThrows`: hosts `""`, `"not a host"`, `"http://x"` → `ClockError.invalidAddress` before any request.

- [ ] **Step 2: Run tests** — Expected: FAIL, symbols undefined.

- [ ] **Step 3: Implement the views** to match the spec's face B and the mockup (the face B mockup from the design session). Layout in px: header at y 8 (monster scale 1 ≈15×10 left, header text 11 pt right, dim, or yellow for stale); "5-HOUR" 11 pt dim at y 30; percent 64 pt heavy coloured by level; right column "resets in" 11 pt dim over countdown 18 pt semibold; 8 px bar at ≈ y 120; lower section from y 150: rows 12 pt with 5 px bars, then 10 pt dim weekly reset text. Signed-out face: header time, centred monster (scale 4), "Sign in on your Mac" 18 pt semibold white. Renderer: `ImageRenderer` with `scale = 1`, `proposedSize` 240×240, convert `nsImage` → `NSBitmapImageRep` → JPEG/PNG.

- [ ] **Step 4: Implement `GeekMagicClient`.** Host must match an IPv4 address or a hostname of `[A-Za-z0-9.-]+` (no scheme, no spaces). Accepted "unparseable reply" errors: `URLError.cannotParseResponse`, `.badServerResponse`, `.networkConnectionLost`. All other `URLError`s → `.unreachable(localizedDescription)`.

- [ ] **Step 5: Run tests** — Expected: PASS. Then open `.build/previews/*.png` and look at each against the mockup; fix layout until the fresh face matches card B.

- [ ] **Step 6: Commit** — `feat: clock face renderer and GeekMagic client`.

---

### Task 5: App shell and .app bundle

**Files:**
- Delete: `Sources/GeekClockBar/main.swift`
- Create: `Sources/GeekClockBar/GeekClockBarApp.swift` (`@main` App with a `MenuBarExtra("GeekClock Bar") { Text("Hello") }`, `.menuBarExtraStyle(.window)`)
- Create: `Resources/Info.plist`
- Create: `scripts/build-app.sh`

**Interfaces:**
- Produces: `scripts/build-app.sh` → builds `swift build -c release`, assembles `build/GeekClockBar.app/Contents/{MacOS/GeekClockBar,Info.plist}`, `codesign --force --sign - --deep`, then copies to `~/Applications/GeekClockBar.app` (replacing it; quits a running instance first with `pkill -x GeekClockBar || true`). Later tasks use it to run the app.

- [ ] **Step 1: Write `Info.plist`** with `CFBundleIdentifier` `com.alexpoliukh.geekclockbar`, `CFBundleName`/`CFBundleDisplayName` "GeekClock Bar", `CFBundleExecutable` `GeekClockBar`, `CFBundlePackageType` `APPL`, `CFBundleShortVersionString` `1.0`, `CFBundleVersion` `1`, `LSMinimumSystemVersion` `14.0`, `LSUIElement` true, `NSLocalNetworkUsageDescription` (Global Constraints text). Lint: `plutil -lint Resources/Info.plist` → `OK`.

- [ ] **Step 2: Write the app shell and `scripts/build-app.sh`** (`set -euo pipefail`, uses `DEVELOPER_DIR`).

- [ ] **Step 3: Verify** — `./scripts/build-app.sh && open ~/Applications/GeekClockBar.app`. Expected: an item appears in the menu bar; clicking shows "Hello"; no Dock icon. `pgrep -x GeekClockBar` prints a PID.

- [ ] **Step 4: Commit** — `feat: menu bar app shell and bundle script`.

---

### Task 6: Claude web session and sign-in window

**Files:**
- Create: `Sources/GeekClockBar/ClaudeSession.swift`
- Create: `Sources/GeekClockBar/SignInWindow.swift`

**Interfaces:**
- Consumes: `parseOrganizationID`, `parseUsage` (Task 1).
- Produces:
  - `enum FetchOutcome: Sendable { case ok(Data); case signedOut; case failed(String) }`
  - `@MainActor final class ClaudeSession { func organizationID() async -> Result<String, SessionError>; func usage(orgID: String) async -> FetchOutcome; func accountLabel() async -> String?; func signOut() async }` where `enum SessionError: Error { case signedOut, failed(String) }`.
  - `@MainActor final class SignInWindowController { init(onSignedIn: @escaping (String) -> Void); func show() }` — `String` is the org id.

- [ ] **Step 1: Implement `ClaudeSession`.** Owns one off-screen `WKWebView` (frame 1×1, `WKWebsiteDataStore.default()`, Safari-like `customUserAgent` matching the system Safari, not in any window). Before each fetch, if the web view has no loaded `https://claude.ai` page, load `https://claude.ai/` and await `didFinish` (timeout 20 s). Fetch via `callAsyncJavaScript`:
  ```js
  const r = await fetch(path, {credentials: 'include', headers: {'accept': 'application/json'}});
  return {status: r.status, body: await r.text(), url: r.url};
  ```
  Mapping: 200 → `.ok`; 401, or 403 whose body is JSON with an `error` (not a Cloudflare HTML page), or a final URL containing `/login` → `.signedOut`; anything else → `.failed("HTTP \(status)")`; JS errors → `.failed(message)`. `accountLabel()`: `GET /api/account`, return `email_address` if present, else nil (tolerate any shape). `signOut()`: remove all `WKWebsiteDataStore.default()` records whose display name contains `claude.ai` or `anthropic`.

- [ ] **Step 2: Implement `SignInWindowController`.** An `NSWindow` (480×640, titled "Sign in to Claude", centred, `NSApp.activate`) containing a `WKWebView` on the same default data store, loading `https://claude.ai/login`. Every 2 s while open, call `ClaudeSession.organizationID()`; on success close the window and call `onSignedIn(orgID)`.

- [ ] **Step 3: Temporary wiring for manual check.** In the shell's `MenuBarExtra` content, add a "Sign in" button that shows the window, and a "Fetch" button that calls `usage` and shows `parseUsage` result or the outcome as text.

- [ ] **Step 4: Verify manually** — `./scripts/build-app.sh && open ~/Applications/GeekClockBar.app`, click Sign in, choose "Continue with email", enter the email address, enter the emailed code. Expected: window closes by itself; "Fetch" shows three blocks with the same percentages as claude.ai Settings → Usage. Quit and relaunch: "Fetch" still works without signing in. If the hidden web view's fetch gets a Cloudflare challenge (HTML 403), stop and report — fallback is the spec's `WKHTTPCookieStore` + `URLSession` route.

- [ ] **Step 5: Commit** — `feat: claude.ai web session and sign-in window`.

---

### Task 7: App model, scheduling, menu bar icon and panel

**Files:**
- Create: `Sources/GeekClockCore/FetchPolicy.swift`, Test: `Tests/GeekClockCoreTests/FetchPolicyTests.swift`
- Create: `Sources/GeekClockBar/AppModel.swift`
- Create: `Sources/GeekClockBar/MenuBarIcon.swift`
- Create: `Sources/GeekClockBar/UsagePanel.swift`
- Modify: `Sources/GeekClockBar/GeekClockBarApp.swift` (remove the temporary Task 6 buttons)

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces:
  - `public func shouldFetch(now: Date, lastAttempt: Date?, panelOpened: Bool) -> Bool` — true if `lastAttempt == nil`, or `now − lastAttempt >= 300`, or (`panelOpened` and `now − lastAttempt > 60`).
  - `enum AuthState: Equatable { case checking, signedIn(orgID: String, label: String?), signedOut }`
  - `enum ClockStatus: Equatable { case disabled, notConfigured, ok(Date), failed(String) }`
  - `@MainActor final class AppModel: ObservableObject` with `@Published var auth: AuthState`, `@Published var usage: UsageState`, `@Published var clockStatus: ClockStatus`, `@Published var lastError: String?`, `@Published var now: Date`; settings via `@AppStorage`-compatible `UserDefaults` keys `clockIP` (default `""`), `sendToClock` (default `true`), `openAtLogin` (default `true`); methods `start()`, `panelOpened()`, `signIn()`, `signOut()`, `testClock() async -> ClockStatus`, `pushToClock() async`.

- [ ] **Step 1: Write failing `FetchPolicyTests`:** nil → true; 299 s → false; 300 s → true; panel 61 s → true; panel 60 s → false; panel 10 s → false.

- [ ] **Step 2: Run tests** — Expected: FAIL. **Step 3: Implement `shouldFetch`.** **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Implement `AppModel`.**
  - `usage` persisted as JSON in `UserDefaults` key `usageState`; loaded at start.
  - `start()`: resolve auth via `organizationID()`; `.signedOut` → show sign-in window. A 60 s `Timer` (`.common` run loop mode) calls `tick()`: update `now`; if signed in and `shouldFetch` → fetch usage; then `pushToClock()`.
  - Fetch results: `.ok` → `parseUsage` → `usage = usage.merging(…, at: now)`, `lastError = nil`; parse failure → `lastError = "Unexpected response from claude.ai"`; `.signedOut` → `auth = .signedOut`, `usage = .empty` (persisted), show sign-in window; `.failed(msg)` → `lastError = msg`, keep usage.
  - `pushToClock()`: skip with `.disabled` when `sendToClock` false, `.notConfigured` when `clockIP` empty; face = `makeClockFace(state: auth is signedIn ? usage : nil, now:, timeZone: .current)`; `renderClockFaceJPEG` → `GeekMagicClient.upload`; status `.ok(now)` or `.failed(reason)`. Never awaits on the main thread longer than the request; errors never throw out of `tick()`.
  - `testClock()`: upload, then `showAppImage()`; returns status. Also called when `clockIP` changes to a non-empty value (debounced 1 s).
  - `openAtLogin`: on start, if true and `SMAppService.mainApp.status != .enabled` → `register()`; toggling false → `unregister()`. Log failures to `lastError`.

- [ ] **Step 6: Implement `MenuBarIcon`.** Render an `NSImage` (height 18 pt, `isTemplate = false`) of `PixelMonster(scale: 1)` + two stacked 28×4 pt rounded bars, 2 pt gap, track (45,45,55), fill by level colour; whole image at 40% opacity when `usage.isStale(now:)`; both bars grey track only when signed out or unknown. Use it as the `MenuBarExtra` label via `Image(nsImage:)`.

- [ ] **Step 7: Implement `UsagePanel`** (280 pt wide), per the spec's panel section and the approved draft: rows "Current (5h)", "Weekly", model label (only if present), each with percent text, 8 pt bar, reset line ("Resets in 3h 29m" under 5h; "Weekly resets in 4d" once under the last weekly row); divider; footer status line: signed out → "Sign in again" button; else `●` coloured green/red + "Clock 192.168.1.50 · synced 05:21", or "Clock not set up", or "Clock: \(reason)"; if `lastError` → it replaces the synced text in red; if stale → "Updated N min ago". Footer right: ⚙︎ button opening the settings window (Task 8) and a "Quit" item. Call `model.panelOpened()` in `.onAppear`.

- [ ] **Step 8: Verify** — build/run with `sendToClock` off (`defaults write com.alexpoliukh.geekclockbar sendToClock -bool false` before launch). Expected: bars match claude.ai; panel numbers and countdowns correct; after `defaults write … usageState` is edited to set `lastSuccess` 20 min back and relaunch with network off, icon is dimmed and panel says "Updated 20 min ago".

- [ ] **Step 9: Commit** — `feat: app model, menu bar icon and usage panel`.

---

### Task 8: Settings window

**Files:**
- Create: `Sources/GeekClockBar/SettingsView.swift`
- Modify: `Sources/GeekClockBar/GeekClockBarApp.swift` (add `Window("GeekClock Bar Settings", id: "settings")` scene; panel's ⚙︎ uses `openWindow(id: "settings")` + `NSApp.activate`)

**Interfaces:**
- Consumes: `AppModel` (Task 7).

- [ ] **Step 1: Implement `SettingsView`** (Form, ~360 pt wide): "GeekMagic IP" text field bound to `clockIP` + "Test" button (shows spinner, then "✓ Clock updated" or the `ClockStatus.failed` reason); "Send to clock" toggle; "Open at login" toggle; "Signed in as \(label ?? "Claude account")" + "Sign out" button (or "Sign in" when signed out).

- [ ] **Step 2: Verify** — run the app, open settings. Expected: typing an invalid IP and Test shows an error without hanging; toggles persist across relaunch (`defaults read com.alexpoliukh.geekclockbar`). Do **not** enter the real clock IP yet (old job still running; Task 9).

- [ ] **Step 3: Commit** — `feat: settings window`.

---

### Task 9: End-to-end on the real clock and cutover

**Files:** none new.

- [ ] **Step 1: Ask the user** for permission to stop the old job. Only after a yes: `launchctl bootout gui/$(id -u)/com.geekclock.claude`; verify `launchctl list | grep geekclock` prints nothing. Leave the plist and script on disk.

- [ ] **Step 2: Enter `192.168.1.50`** in settings, press Test. Expected: "✓ Clock updated"; `curl -s http://192.168.1.50/app.json` → `{"theme":3}`; the clock shows face B with the same numbers as the panel.

- [ ] **Step 3: Watch two minutes.** Expected: the clock's header time advances each minute; panel shows "synced HH:MM" updating.

- [ ] **Step 4: Sign-out check.** Settings → Sign out. Expected within a minute: menu bar bars grey, panel shows "Sign in again", the clock shows "Sign in on your Mac". Sign back in; numbers return.

- [ ] **Step 5: Login item check.** `sfltool dumpbtm 2>/dev/null | grep -i geekclockbar` (or System Settings → General → Login Items) shows GeekClock Bar enabled.

- [ ] **Step 6: Commit** — `chore: verified end-to-end on SmallTV-Ultra` (empty commit allowed if nothing changed: `git commit --allow-empty`).
