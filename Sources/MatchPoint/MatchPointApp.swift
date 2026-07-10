import AppKit
import SwiftUI

@main
struct MatchPointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Matcher") {
                    NotificationCenter.default.post(name: .selectMatchPointMode, object: MatchPointMode.matches.rawValue)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Spelare") {
                    NotificationCenter.default.post(name: .selectMatchPointMode, object: MatchPointMode.players.rawValue)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Jämför") {
                    NotificationCenter.default.post(name: .selectMatchPointMode, object: MatchPointMode.compare.rawValue)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Favoriter") {
                    NotificationCenter.default.post(name: .selectMatchPointMode, object: MatchPointMode.favorites.rawValue)
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button("Livepoäng") {
                    openWindow(id: "scoreboard")
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Inställningar...") {
                    NotificationCenter.default.post(name: .openMatchPointSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        WindowGroup("Livepoäng", id: "scoreboard") {
            ScoreboardWindow()
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let openMatchPointSettings = Notification.Name("openMatchPointSettings")
    static let selectMatchPointMode = Notification.Name("selectMatchPointMode")
}
