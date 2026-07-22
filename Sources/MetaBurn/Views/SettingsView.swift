import SwiftUI

struct SettingsView: View {
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"

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
            .onChange(of: themeSource) { _, newValue in
                ThemePreference.applyAppAppearance(for: newValue)
            }
            Spacer()
        }
        .padding()
        .frame(width: 480, height: 240)
        .onAppear { ThemePreference.applyAppAppearance(for: themeSource) }
    }
}
