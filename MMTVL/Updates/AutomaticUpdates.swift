/// M15 L5, L7: how MMTVL installs the updates Sparkle finds (`settings.json` `automaticUpdates`; Settings → System →
/// Software Update → Automatic Updates). Unknown values read as `off`.
nonisolated enum AutomaticUpdates: String, CaseIterable, Codable, Sendable {
    case off, whenIdle, atNight

    var title: String {
        switch self {
        case .off: "Off"
        case .whenIdle: "When Idle"
        case .atNight: "At Night"
        }
    }

    var description: String {
        switch self {
        case .off: "Shows a notice when there's an update. You install it here."
        case .whenIdle: "Downloads updates and installs them when Power has turned the TV off, or while the screen saver is on."
        case .atNight: "Downloads updates and installs them at about 4 a.m. when nothing is playing."
        }
    }
}
