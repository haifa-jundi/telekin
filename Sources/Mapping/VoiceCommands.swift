import Foundation

/// Things you can say. Each one is a short, distinct phrase so ordinary talk rarely triggers it.
enum VoiceCommand: CaseIterable, Equatable {
    case click, doubleClick, rightClick, drag, drop, scrollUp, scrollDown, pause, resume

    /// What to say, as shown in the window.
    var phrase: String {
        switch self {
        case .click: return "click"
        case .doubleClick: return "double click"
        case .rightClick: return "right click"
        case .drag: return "drag"
        case .drop: return "drop"
        case .scrollUp: return "scroll up"
        case .scrollDown: return "scroll down"
        case .pause: return "pause"
        case .resume: return "resume"
        }
    }

    /// Every word sequence that means this command (the recogniser sometimes hears a near miss).
    fileprivate var spoken: [[String]] {
        switch self {
        case .drop: return [["drop"], ["release"]]
        default: return [phrase.split(separator: " ").map(String.init)]
        }
    }

    /// Hints for the recogniser, so it favours these words.
    static var allPhrases: [String] { allCases.map(\.phrase) + ["release"] }
}

/// Turns one utterance (what you said between pauses) into commands. It only acts when the whole
/// utterance is commands, so a sentence that merely contains "click" ("please click the button",
/// a video, a call) never clicks.
enum VoiceCommandParser {
    /// Longer utterances are conversation, not commands.
    static let maxCommandsPerUtterance = 3

    /// Words the recogniser commonly writes instead of a command word.
    private static let soundsLike = ["clique": "click", "klick": "click", "clic": "click", "write": "right",
                                     "doubleclick": "double click", "rightclick": "right click"]

    private static let phrases: [(words: [String], command: VoiceCommand)] =
        VoiceCommand.allCases.flatMap { command in command.spoken.map { ($0, command) } }
            .sorted { $0.words.count > $1.words.count } // longest first: "double click" before "click"

    /// The commands making up `utterance`, or none if any word in it is not part of a command.
    static func commands(inUtterance utterance: String) -> [VoiceCommand] {
        let words = words(in: utterance)
        var found: [VoiceCommand] = []
        var index = 0
        while index < words.count {
            guard let match = phrases.first(where: { words[index...].starts(with: $0.words) }) else { return [] }
            found.append(match.command)
            index += match.words.count
        }
        return found.count <= maxCommandsPerUtterance ? found : []
    }

    /// Whether the recogniser has heard anything worth waiting on.
    static func isEmpty(_ utterance: String) -> Bool { words(in: utterance).isEmpty }

    static func words(in transcript: String) -> [String] {
        transcript.lowercased()
            .split { !$0.isLetter }
            .flatMap { word in (soundsLike[String(word)] ?? String(word)).split(separator: " ").map(String.init) }
    }
}
