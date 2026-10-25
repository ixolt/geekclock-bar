import GeekClockCore
import SwiftUI

/// The Test button's progress and result. An ObservableObject rather than
/// @State: the Command Line Tools ship without the SwiftUI macro plugin.
@MainActor
final class ClockTest: ObservableObject {
    @Published var running = false
    @Published var result: ClockStatus?

    func run(_ model: AppModel) {
        running = true
        result = nil
        Task {
            result = await model.testClock()
            running = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var test = ClockTest()

    var body: some View {
        Form {
            Section("GeekMagic clock") {
                HStack {
                    TextField("IP address", text: $model.clockIP, prompt: Text("192.168.1.100"))
                    Button("Test") { test.run(model) }
                        .disabled(test.running || model.clockIP.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if test.running {
                    ProgressView().controlSize(.small)
                } else if let testResult = test.result {
                    testResultText(testResult)
                }
                Toggle("Send to clock", isOn: $model.sendToClock)
            }
            Section("Appearance") {
                Picker("Menu bar", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Clock face", selection: $model.clockFaceStyle) {
                    ForEach(ClockFaceStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                HStack {
                    Spacer()
                    clockPreview
                    Spacer()
                }
            }
            Section("General") {
                Toggle("Open at login", isOn: $model.openAtLogin)
            }
            Section("Claude account") {
                if model.isSignedIn {
                    HStack {
                        Text("Signed in as \(model.accountLabel ?? "Claude account")")
                        Spacer()
                        Button("Sign out") { Task { await model.signOut() } }
                    }
                } else {
                    HStack {
                        Text("Not signed in")
                        Spacer()
                        Button("Sign in") { model.signIn() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 360)
    }

    /// The clock face as it will look on the clock, at two-thirds size; animated faces play.
    private var clockPreview: some View {
        AnimatedImageView(data: renderClockImage(model.currentClockFace(), style: model.clockFaceStyle,
                                                activity: model.monsterActivity)?.data)
            .frame(width: 160, height: 160)
            .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func testResultText(_ status: ClockStatus) -> some View {
        switch status {
        case .ok: Text("✓ Clock updated").foregroundStyle(.green)
        case .failed(let reason): Text(reason).foregroundStyle(.red)
        case .disabled: Text("Turn on “Send to clock” to test").foregroundStyle(.secondary)
        case .notConfigured: Text("Enter the clock’s IP address").foregroundStyle(.secondary)
        }
    }
}

/// Shows an image, playing it if it is an animated GIF (SwiftUI's Image would not).
struct AnimatedImageView: NSViewRepresentable {
    let data: Data?

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard context.coordinator.data != data else { return }
        context.coordinator.data = data
        view.image = data.flatMap(NSImage.init(data:))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var data: Data?
    }
}
