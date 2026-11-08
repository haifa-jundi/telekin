import Foundation

/// How clicks can be triggered besides the keyboard shortcuts.
struct ClickOptions: Equatable {
    /// Hold still about 1 s to click.
    var dwell = false
    /// Keep holding to about 2 s to also double-click (needs `dwell`).
    var dwellDoubleClick = true
    /// Experimental: AirPods press once to click, twice to double-click.
    var stemPress = false
}

/// Spoken commands ("click", "scroll down"…), recognised on this Mac only.
struct VoiceOptions: Equatable {
    var enabled = false
}

/// Visual extras.
struct EffectOptions: Equatable {
    /// Sparkles that follow the cursor while Telekin moves it, and burst on clicks.
    var spellTrail = true
}

/// Persists the user's choices between launches.
struct SettingsStore {
    private enum Key {
        static let speed = "speed"
        static let deadzone = "deadzone"
        static let acceleration = "acceleration"
        static let dwell = "dwellClick"
        static let dwellDouble = "dwellDoubleClick"
        static let stemPress = "stemPressClick"
        static let invertHorizontal = "invertHorizontal"
        static let invertVertical = "invertVertical"
        static let spellTrail = "spellTrail"
        static let setupSeen = "setupSeen"
        static let tiltScroll = "tiltScroll"
        static let tiltDeadzone = "tiltDeadzone"
        static let scrollSpeed = "scrollSpeed"
        static let scrollReverse = "scrollReverse"
        static let voice = "voiceCommands"
    }

    static let speedRange = 0.3...3.0
    static let deadzoneRange = 0.5...8.0
    static let accelerationRange = 0.0...1.5
    static let tiltDeadzoneRange = 5.0...25.0
    static let scrollSpeedRange = 0.3...3.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    struct Snapshot: Equatable {
        var settings = MouseSettings()
        var clicks = ClickOptions()
        var effects = EffectOptions()
        var scroll = ScrollSettings()
        var voice = VoiceOptions()
    }

    func load() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.settings.speed = number(Key.speed, in: Self.speedRange) ?? snapshot.settings.speed
        snapshot.settings.deadzoneDegreesPerSecond = number(Key.deadzone, in: Self.deadzoneRange) ?? snapshot.settings.deadzoneDegreesPerSecond
        snapshot.settings.acceleration = number(Key.acceleration, in: Self.accelerationRange) ?? snapshot.settings.acceleration
        snapshot.settings.invertHorizontal = defaults.bool(forKey: Key.invertHorizontal)
        snapshot.settings.invertVertical = defaults.bool(forKey: Key.invertVertical)
        snapshot.clicks.dwell = defaults.bool(forKey: Key.dwell)
        snapshot.clicks.dwellDoubleClick = flag(Key.dwellDouble) ?? true
        snapshot.clicks.stemPress = defaults.bool(forKey: Key.stemPress)
        snapshot.effects.spellTrail = flag(Key.spellTrail) ?? true
        snapshot.scroll.tiltScroll = defaults.bool(forKey: Key.tiltScroll)
        snapshot.scroll.tiltDeadzoneDegrees = number(Key.tiltDeadzone, in: Self.tiltDeadzoneRange) ?? snapshot.scroll.tiltDeadzoneDegrees
        snapshot.scroll.speed = number(Key.scrollSpeed, in: Self.scrollSpeedRange) ?? snapshot.scroll.speed
        snapshot.scroll.reverse = defaults.bool(forKey: Key.scrollReverse)
        snapshot.voice.enabled = defaults.bool(forKey: Key.voice)
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        defaults.set(snapshot.settings.speed, forKey: Key.speed)
        defaults.set(snapshot.settings.deadzoneDegreesPerSecond, forKey: Key.deadzone)
        defaults.set(snapshot.settings.acceleration, forKey: Key.acceleration)
        defaults.set(snapshot.settings.invertHorizontal, forKey: Key.invertHorizontal)
        defaults.set(snapshot.settings.invertVertical, forKey: Key.invertVertical)
        defaults.set(snapshot.clicks.dwell, forKey: Key.dwell)
        defaults.set(snapshot.clicks.dwellDoubleClick, forKey: Key.dwellDouble)
        defaults.set(snapshot.clicks.stemPress, forKey: Key.stemPress)
        defaults.set(snapshot.effects.spellTrail, forKey: Key.spellTrail)
        defaults.set(snapshot.scroll.tiltScroll, forKey: Key.tiltScroll)
        defaults.set(snapshot.scroll.tiltDeadzoneDegrees, forKey: Key.tiltDeadzone)
        defaults.set(snapshot.scroll.speed, forKey: Key.scrollSpeed)
        defaults.set(snapshot.scroll.reverse, forKey: Key.scrollReverse)
        defaults.set(snapshot.voice.enabled, forKey: Key.voice)
    }

    var setupSeen: Bool {
        get { defaults.bool(forKey: Key.setupSeen) }
        nonmutating set { defaults.set(newValue, forKey: Key.setupSeen) }
    }

    /// A stored number, only if it is inside the allowed range (bad or missing values fall back to defaults).
    private func number(_ key: String, in range: ClosedRange<Double>) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        return range.contains(value) ? value : nil
    }

    private func flag(_ key: String) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }
}
