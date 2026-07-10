import SwiftUI

struct SettingsView: View {
    @AppStorage("themeSource") private var themeSource: String = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
            Picker("Theme", selection: $themeSource) {
                Text("Auto").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.radioGroup)
            .onChange(of: themeSource) { applyTheme() }
            Spacer()
        }
        .padding()
        .frame(width: 480, height: 240)
        .onAppear { applyTheme() }
    }

    private func applyTheme() {
        let appearance: NSAppearance?
        switch themeSource {
        case "light":
            appearance = NSAppearance(named: .aqua)
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil
        }
        NSApp?.appearance = appearance
    }
}
