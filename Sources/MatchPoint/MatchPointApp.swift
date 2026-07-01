import AppKit
import SwiftUI

@main
struct MatchPointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openMatchPointSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
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
}
