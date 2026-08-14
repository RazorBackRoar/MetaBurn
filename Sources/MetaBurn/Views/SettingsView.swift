import SwiftUI
import MetaBurnCore

struct SettingsView: View {
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"
    @AppStorage(OutputPreference.storageKey) private var outputDestinationRaw: String = OutputDestination.desktop.rawValue

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
            }

            Section {
                Picker("Save cleaned copies", selection: $outputDestinationRaw) {
                    Text("Pictures/MetaBurn").tag(OutputDestination.desktop.rawValue)
                    Text("Next to originals").tag(OutputDestination.adjacent.rawValue)
                }
                .pickerStyle(.radioGroup)

                Text(outputHelpText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Output")
            } footer: {
                Text("Originals are never overwritten. Drag and drop remains the only way to import files (including from iCloud Drive).")
                    .font(.system(size: 11))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 320)
        .onAppear { ThemePreference.applyAppAppearance(for: themeSource) }
    }

    private var outputHelpText: String {
        switch OutputDestination(rawValue: outputDestinationRaw) ?? .desktop {
        case .desktop:
            return "Cleaned Photos, Videos, and Skippable folders are created under Pictures/MetaBurn only when needed. The Desktop is never used as an output folder."
        case .adjacent:
            return "For each source file, cleaned copies go to a MetaBurn folder beside that file (MetaBurn/Photos, Videos, Skippable). Files dropped from the Desktop go to Pictures/MetaBurn instead of creating a Desktop folder."
        }
    }
}
