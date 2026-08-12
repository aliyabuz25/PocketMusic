import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PocketPaths.ensure()
        NSApp.setActivationPolicy(.accessory)
        MenuBarModel.shared.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainWindowController.shared.present()
            PocketMusicUIState.shared.tab = .search
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.present()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "pocketmusic" {
            MainWindowController.shared.present()
            PocketMusicUIState.shared.tab = .search
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
