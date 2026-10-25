import GeekClockCore
import SwiftUI

/// The menu bar item, fed from the model.
struct MenuBarIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        MenuBarLabel(style: model.menuBarStyle,
                     fiveHour: model.isSignedIn ? model.usage.display(.fiveHour, now: model.now) : .unknown,
                     weekly: model.isSignedIn ? model.usage.display(.sevenDay, now: model.now) : .unknown,
                     dimmed: model.isSignedIn && model.usage.isStale(now: model.now))
    }
}
