import SwiftUI
import AppKit
import GTransCore

@main
struct GTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    appState.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    init() {
        AppDiagnostics.installCrashHandler()
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        AppDelegate.onDidFinishLaunching = {
            Task { @MainActor in
                state.start()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onDidFinishLaunching: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.onDidFinishLaunching?()
    }
}
