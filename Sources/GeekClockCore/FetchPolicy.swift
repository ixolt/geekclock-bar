import Foundation

/// claude.ai is polled every 5 minutes, and sooner when the user opens the
/// panel and the numbers are more than a minute old.
public func shouldFetch(now: Date, lastAttempt: Date?, panelOpened: Bool) -> Bool {
    guard let lastAttempt else { return true }
    let age = now.timeIntervalSince(lastAttempt)
    return age >= 300 || (panelOpened && age > 60)
}

/// The first whole minute strictly after `date`, when the once-a-minute loop should fire.
public func nextMinute(after date: Date) -> Date {
    Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60)
}
