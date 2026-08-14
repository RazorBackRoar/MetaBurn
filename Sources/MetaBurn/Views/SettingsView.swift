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
            } header: {
                Text("Appearance")
            } footer: {
                Text("Cleaned copies are saved next to the originals. MetaBurn never writes to Pictures/MetaBurn or Desktop/MetaBurn. Originals are never overwritten. Drag and drop remains the only way to import files (including from iCloud Drive).")
                    .font(.system(size: 11))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 220)
        .onAppear { ThemePreference.applyAppAppearance(for: themeSource) }
    }
}
