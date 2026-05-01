import AppKit
import SwiftUI

@main
enum AgentConsoleMain {
    static func main() {
        UserDefaults.standard.register(defaults: [
            "AppleDockIconEnabled": true,
        ])
        AgentConsoleApp.main()
    }
}

struct AgentConsoleApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 680)
                .onAppear {
                    MenuBarController.shared.configure(appState: appState)
                }
                .task {
                    await appState.loadIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appState.handleAppDidBecomeActive()
                }
        }
        .defaultSize(width: 1100, height: 709)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 900, height: 680)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconProvider.shared.configureApplicationIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup handled by deinit
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: { $0.title == "Agent Console" }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
