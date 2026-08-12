import AppKit
import SwiftUI

@main
struct PocketMusicSpotlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "pocketmusic" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty {
                Task { await PlayerBridge.play(trackID: id) }
            }
        }
    }
}
