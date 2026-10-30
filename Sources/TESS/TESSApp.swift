import AppKit
import SwiftUI

@main
struct TESSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.assistant)
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.assistant.meter)
        } label: {
            MenuBarIcon(assistant: appDelegate.assistant)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let assistant: Assistant

    override init() {
        let settings = AppSettings()
        self.settings = settings
        self.assistant = Assistant(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await assistant.start() }
        Updater.shared.start()

        // First run without a key for the chosen brain: open settings so setup is obvious.
        let needsKey: Bool
        switch settings.provider {
        case .anthropic: needsKey = settings.anthropicKey.trimmed.isEmpty
        case .openai: needsKey = settings.openAIKey.trimmed.isEmpty
        case .ollama: needsKey = false
        }
        if needsKey {
            SettingsWindow.shared.show(settings: settings, assistant: assistant)
        }
    }
}
