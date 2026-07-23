import SwiftUI
import AppKit

@main
struct MetaBurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("MetaBurn", id: "main") {
            ContentView()
        }
        .defaultSize(width: 720, height: 640)
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
        NSApp?.setActivationPolicy(.regular)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp?.mainMenu = buildMenu()
        ThemePreference.applyAppAppearance()

        if let iconURL = Resources.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            NSApp?.applicationIconImage = image
        }

        for window in NSApp?.windows ?? [] {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.minSize = NSSize(width: 640, height: 560)
        }
    }

    private func buildMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "MetaBurn")

        let appMenu = NSMenu(title: "MetaBurn")
        appMenu.addItem(withTitle: "About MetaBurn", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide MetaBurn", action: #selector(NSApp?.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit MetaBurn", action: #selector(NSApp?.terminate(_:)), keyEquivalent: "q")

        let appMenuItem = NSMenuItem(title: "MetaBurn", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        return mainMenu
    }

    @objc func showAbout() {
        let info = AppInfoProvider.current()
        let alert = NSAlert()
        alert.messageText = info.name
        alert.informativeText = [
            "Version \(info.version)",
            info.license,
            info.organization,
            info.architecture,
            info.copyright
        ].joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func checkForUpdates() {
        Task {
            let info = AppInfoProvider.current()
            let result = await Updates.checkForUpdates(currentVersion: info.version)
            let alert = NSAlert()
            alert.alertStyle = result.error != nil ? .warning : .informational
            if let error = result.error {
                alert.messageText = "Update check failed"
                alert.informativeText = error
            } else if result.updateAvailable {
                alert.messageText = "Update available: \(result.latestVersion)"
                alert.informativeText = "You have \(result.currentVersion).\(result.downloadURL.map { "\n\n\($0)" } ?? "")"
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "Current version: \(result.currentVersion)"
            }
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func showSettings() {
        NSApp?.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
