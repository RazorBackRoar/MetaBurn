import AppKit
import SwiftUI

@main
struct MetaBurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("MetaBurn", id: "main") {
            ContentView()
        }
        .defaultSize(width: 960, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }

    init() {
        AppInfoProvider.printStartupInfo()
        Log.shared.setup()
        Paths.ensureDirectory(Paths.applicationSupportDirectory())
        Paths.ensureLogsDirectory()
        Paths.ensureCacheDirectory()
        Paths.ensureWorkspaceDirectories()
        // Sweep legacy Desktop orphans + abandoned cache work files from prior crashes/cancels.
        let removed = Paths.cleanupOrphanWorkFiles()
        if !removed.isEmpty {
            Log.shared.info("Removed \(removed.count) orphan work file(s) on launch", scope: "app")
        }
        NSApp?.setActivationPolicy(.regular)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsAccessories: [NSTitlebarAccessoryViewController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemePreference.applyAppAppearance()

        if let iconURL = Resources.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: iconURL)
        {
            NSApp?.applicationIconImage = image
        }

        for window in NSApp?.windows ?? [] {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(red: 0.08, green: 0.025, blue: 0.028, alpha: 1)
            window.isOpaque = true
            window.minSize = NSSize(width: 900, height: 720)
            installSettingsAccessory(on: window)
            window.center()
        }
    }

    private func installSettingsAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right

        let baseImage =
            NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            ?? NSImage()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [NSColor(MetaBurnTheme.accent)]))
        let image = baseImage.withSymbolConfiguration(symbolConfig) ?? baseImage
        let button = NSButton(image: image, target: self, action: #selector(showSettings))
        button.bezelStyle = .texturedRounded
        button.contentTintColor = NSColor(MetaBurnTheme.accent)
        button.controlSize = .regular
        button.imagePosition = .imageOnly
        button.toolTip = "Settings"
        button.setAccessibilityLabel("Settings")
        button.frame = NSRect(x: 6, y: 1, width: 34, height: 28)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 46, height: 30))
        container.addSubview(button)
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
        settingsAccessories.append(accessory)
    }

    @objc func showSettings() {
        NSApp?.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
