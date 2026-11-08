import SwiftUI

struct AboutView: View {
    static let repository = URL(string: "https://github.com/haifa-jundi/telekin")
    static let mousePods = URL(string: "https://github.com/starman-tech/mousepods")

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Page(title: "About", subtitle: "Telekin \(version)") {
            Card {
                HStack(spacing: 16) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Telekin").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("Move your Mac cursor with your AirPods.").foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Card("How it works") {
                Text("macOS shares AirPods head motion with apps that play spatial audio. Telekin plays an inaudible spatial tone, reads your head's turn and nod about 50 times a second, and turns that into smooth cursor motion with acceleration.")
                    .foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
            Card("Thanks") {
                Text("Inspired by MousePods by Matteo Gaudioso (starman-tech), which first showed AirPods 3 can drive a cursor on Linux.")
                    .foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                if let link = Self.mousePods { Link("MousePods on GitHub", destination: link) }
            }
            Card {
                if let link = Self.repository { Link("Source code and issues", destination: link) }
                Text("MIT License. Not affiliated with Apple. AirPods is a trademark of Apple Inc.")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
