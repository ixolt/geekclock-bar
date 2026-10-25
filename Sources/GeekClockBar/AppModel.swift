import Foundation
import GeekClockCore
import ServiceManagement
import os

private let log = Logger(subsystem: "com.alexpoliukh.geekclockbar", category: "app")

enum AuthState: Equatable {
    case checking
    case signedIn(orgID: String, label: String?)
    case signedOut
}

enum ClockStatus: Equatable {
    case disabled
    case notConfigured
    case ok(Date)
    case failed(String)
}

/// Owns the app's state: sign-in, usage numbers, settings and the
/// once-a-minute loop that refreshes usage and updates the clock.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var auth: AuthState = .checking
    @Published private(set) var usage: UsageState
    @Published private(set) var clockStatus: ClockStatus = .notConfigured
    @Published private(set) var lastError: String?
    @Published private(set) var now = Date()
    /// What the mood monster is doing this minute.
    @Published private(set) var monsterActivity: MonsterActivity = .wave

    @Published var clockIP: String {
        didSet {
            defaults.set(clockIP, forKey: Keys.clockIP)
            scheduleClockSetup()
        }
    }
    @Published var sendToClock: Bool {
        didSet {
            defaults.set(sendToClock, forKey: Keys.sendToClock)
            Task { await pushToClock() }
        }
    }
    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }
    @Published var clockFaceStyle: ClockFaceStyle {
        didSet {
            defaults.set(clockFaceStyle.rawValue, forKey: Keys.clockFaceStyle)
            Task { await pushToClock() }
        }
    }
    @Published var openAtLogin: Bool {
        didSet {
            defaults.set(openAtLogin, forKey: Keys.openAtLogin)
            applyLoginItem()
        }
    }

    private enum Keys {
        static let clockIP = "clockIP"
        static let sendToClock = "sendToClock"
        static let openAtLogin = "openAtLogin"
        static let menuBarStyle = "menuBarStyle"
        static let clockFaceStyle = "clockFaceStyle"
        static let shownClockFile = "shownClockFile"
        static let usageState = "usageState"
    }

    private let defaults = UserDefaults.standard
    private let session = ClaudeSession()
    private lazy var signInWindow = SignInWindowController(session: session) { [weak self] orgID in
        self?.didSignIn(orgID: orgID)
    }
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private var timer: Timer?
    private var lastAttempt: Date?
    private var fetching = false
    private var pushing = false
    private var setupTask: Task<Void, Never>?

    /// The file the clock was last pointed at; before animated faces it was always the JPEG.
    private var shownClockFile: String {
        get { defaults.string(forKey: Keys.shownClockFile) ?? ClockImage.jpeg(Data()).fileName }
        set { defaults.set(newValue, forKey: Keys.shownClockFile) }
    }

    var isSignedIn: Bool {
        if case .signedIn = auth { return true }
        return false
    }

    var accountLabel: String? {
        if case .signedIn(_, let label) = auth { return label }
        return nil
    }

    init() {
        defaults.register(defaults: [Keys.clockIP: "", Keys.sendToClock: true, Keys.openAtLogin: true])
        clockIP = defaults.string(forKey: Keys.clockIP) ?? ""
        sendToClock = defaults.bool(forKey: Keys.sendToClock)
        openAtLogin = defaults.bool(forKey: Keys.openAtLogin)
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .bars
        clockFaceStyle = defaults.string(forKey: Keys.clockFaceStyle).flatMap(ClockFaceStyle.init) ?? .bigNumber
        usage = defaults.data(forKey: Keys.usageState)
            .flatMap { try? JSONDecoder().decode(UsageState.self, from: $0) } ?? .empty
        Task { [weak self] in self?.start() }
    }

    func start() {
        guard timer == nil else { return }
        applyLoginItem()
        // Fire on whole minutes so the time on the clock is never a minute behind.
        let timer = Timer(fire: nextMinute(after: Date()), interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await resolveAuth(showSignIn: true); await tick() }
    }

    func panelOpened() {
        Task { await tick(panelOpened: true) }
    }

    func signIn() {
        signInWindow.show()
    }

    func openSettings() {
        settingsWindow.show()
    }

    func signOut() async {
        await session.signOut()
        markSignedOut()
        await pushToClock()
    }

    /// Uploads the current face and switches the clock to show it.
    @discardableResult
    func testClock() async -> ClockStatus {
        await pushToClock()
        guard case .ok = clockStatus else { return clockStatus }
        do {
            try await GeekMagicClient(host: clockIP, transport: URLSessionTransport()).showImage(named: shownClockFile)
        } catch {
            clockStatus = .failed(describe(error))
        }
        return clockStatus
    }

    // MARK: - Loop

    private func tick(panelOpened: Bool = false) async {
        now = Date()
        if auth == .checking { await resolveAuth(showSignIn: false) }
        if case .signedIn(let orgID, _) = auth,
           shouldFetch(now: now, lastAttempt: lastAttempt, panelOpened: panelOpened) {
            await refresh(orgID: orgID)
        }
        await pushToClock()
    }

    private func resolveAuth(showSignIn: Bool) async {
        switch await session.organizationID() {
        case .success(let orgID):
            didSignIn(orgID: orgID)
        case .failure(.signedOut):
            markSignedOut()
            if showSignIn { signInWindow.show() }
        case .failure(.failed(let message)):
            lastError = message
            log.error("Auth check failed: \(message, privacy: .public)")
        }
    }

    private func didSignIn(orgID: String) {
        guard auth != .signedIn(orgID: orgID, label: accountLabel) else { return }
        auth = .signedIn(orgID: orgID, label: nil)
        lastAttempt = nil
        Task {
            let label = await session.accountLabel()
            if case .signedIn(let current, _) = auth, current == orgID {
                auth = .signedIn(orgID: orgID, label: label)
            }
            await tick()
        }
    }

    private func markSignedOut() {
        auth = .signedOut
        usage = .empty
        lastAttempt = nil
        lastError = nil
        saveUsage()
    }

    private func refresh(orgID: String) async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        lastAttempt = now
        switch await session.usage(orgID: orgID) {
        case .ok(let data):
            guard let fresh = try? parseUsage(data) else {
                lastError = "Unexpected response from claude.ai"
                log.error("Usage response did not parse")
                return
            }
            usage = usage.merging(fresh, at: Date())
            lastError = nil
            saveUsage()
        case .signedOut:
            markSignedOut()
        case .failed(let message):
            lastError = message
            log.error("Usage fetch failed: \(message, privacy: .public)")
        }
    }

    // MARK: - Clock

    func pushToClock() async {
        guard sendToClock else { clockStatus = .disabled; return }
        let host = clockIP.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { clockStatus = .notConfigured; return }
        guard !pushing else { return }
        pushing = true
        defer { pushing = false }

        let face = currentClockFace()
        if clockFaceStyle.isAnimated {
            var fiveHourLevel = UsageLevel.unknown
            if case .usage(let f) = face { fiveHourLevel = f.fiveHour.level }
            var rng = SystemRandomNumberGenerator()
            monsterActivity = pickActivity(level: fiveHourLevel, previous: monsterActivity, using: &rng)
        }
        guard let image = renderClockImage(face, style: clockFaceStyle, activity: monsterActivity) else {
            clockStatus = .failed("Could not draw the clock image")
            return
        }
        do {
            let client = GeekMagicClient(host: host, transport: URLSessionTransport())
            try await client.upload(image)
            // Switching between a still and an animated face changes the file
            // name, so point the clock at the new file.
            if image.fileName != shownClockFile {
                try await client.showImage(named: image.fileName)
                shownClockFile = image.fileName
            }
            clockStatus = .ok(Date())
        } catch {
            clockStatus = .failed(describe(error))
            log.error("Clock upload failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The face the clock should show right now; the settings preview draws it too.
    func currentClockFace() -> ClockFace {
        makeClockFace(state: auth == .signedOut ? nil : usage, now: Date(), timeZone: .current)
    }

    /// After the IP changes, wait for typing to settle, then set up the clock.
    private func scheduleClockSetup() {
        setupTask?.cancel()
        guard !clockIP.trimmingCharacters(in: .whitespaces).isEmpty else {
            clockStatus = sendToClock ? .notConfigured : .disabled
            return
        }
        setupTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await testClock()
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case ClockError.invalidAddress: "Invalid address"
        case ClockError.unreachable(let reason): "Unreachable: \(reason)"
        case ClockError.badReply(let reply): "Unexpected reply: \(reply)"
        default: error.localizedDescription
        }
    }

    // MARK: - Persistence & login item

    private func saveUsage() {
        defaults.set(try? JSONEncoder().encode(usage), forKey: Keys.usageState)
    }

    private func applyLoginItem() {
        let service = SMAppService.mainApp
        do {
            if openAtLogin, service.status != .enabled {
                try service.register()
            } else if !openAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            lastError = "Open at login: \(error.localizedDescription)"
        }
    }
}
