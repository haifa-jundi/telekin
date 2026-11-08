import Foundation

extension MappingSelfTest {
    private static func hear(_ utterance: String) -> [VoiceCommand] { VoiceCommandParser.commands(inUtterance: utterance) }

    static func runVoiceChecks() {
        check(hear("click") == [.click], "voice: click")
        check(hear("Double-click.") == [.doubleClick], "voice: hyphen and punctuation")
        check(hear("right click") == [.rightClick], "voice: right click")
        check(hear("write click") == [.rightClick], "voice: near miss 'write click'")
        check(hear("click click") == [.click, .click], "voice: repeated command")
        check(hear("scroll down") == [.scrollDown], "voice: scroll down")
        check(hear("Release") == [.drop], "voice: release drops")
        check(hear("Resume") == [.resume], "voice: resume")
        // Ordinary speech that contains a command word must never act.
        check(hear("please click the button") == [], "voice: command inside a sentence does nothing")
        check(hear("click here to subscribe") == [], "voice: command starting a sentence does nothing")
        check(hear("scroll") == [], "voice: half phrase does nothing")
        check(hear("clicking clicked") == [], "voice: other word forms do nothing")
        check(hear("all right") == [], "voice: 'right' alone does nothing")
        check(hear("click click click click") == [], "voice: long runs are not commands")
        check(hear("") == [], "voice: silence does nothing")
    }
}
