import SwiftUI

struct SettingsView: View {
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $themeSource) {
                    Text("Auto").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: themeSource) { _, newValue in
                    ThemePreference.applyAppAppearance(for: newValue)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 420, height: 180)
        .onAppear { ThemePreference.applyAppAppearance(for: themeSource) }
    }
}
