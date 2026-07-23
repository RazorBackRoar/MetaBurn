import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MetaBurnCore

struct ContentView: View {
    @StateObject private var runner = TaskRunner()
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"
    @State private var exiftoolReady: Bool? = nil
    @State private var canInstallExiftool = false
    @State private var installingExiftool = false
    @State private var muteAudio = true
    @State private var isDragging = false
    @State private var dropNotice: String? = nil
    @State private var selectedEntry: LogEntry? = nil
    @AppStorage("lastBrowseDirectory") private var lastBrowseDirectory: String = ""

    private var processing: Bool {
        runner.state == .scanning || runner.state == .cleaning
    }

    private var hasResults: Bool {
        !runner.log.isEmpty || (runner.state == .done && runner.counters.skipped > 0 && runner.counters.supported == 0)
    }

    private var sortedLog: [LogEntry] {
        runner.log.sorted { lhs, rhs in
            let lhsUnmodified = (lhs.status == .skipped || lhs.status == .failed)
            let rhsUnmodified = (rhs.status == .skipped || rhs.status == .failed)
            if lhsUnmodified != rhsUnmodified {
                return !lhsUnmodified
            }
            return false
        }
    }

    private var preferredScheme: ColorScheme? {
        ThemePreference.colorScheme(for: themeSource)
    }

    var body: some View {
        Group {
            if exiftoolReady == false {
                missingExiftoolView
            } else {
                mainView
            }
        }
        .preferredColorScheme(preferredScheme)
        .onAppear {
            ThemePreference.applyAppAppearance(for: themeSource)
            Task { await checkExiftool() }
        }
        .onChange(of: themeSource) { _, newValue in
            ThemePreference.applyAppAppearance(for: newValue)
        }
    }

    // MARK: - Missing ExifTool

    private var missingExiftoolView: some View {
        VStack(spacing: 20) {
            Image(systemName: "flame.fill")
                .font(.system(size: 45))
                .foregroundStyle(MetaBurnTheme.accent)
            Text("ExifTool is required")
                .font(.system(size: 23, weight: .semibold))
            Text("MetaBurn uses ExifTool to strip metadata locally.\nInstall it with Homebrew, then re-check.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                if canInstallExiftool {
                    Button(installingExiftool ? "Installing…" : "Install ExifTool") {
                        Task { await installExiftool() }
                    }
                    .buttonStyle(MetaBurnPrimaryButtonStyle())
                    .disabled(installingExiftool)
                }
                Button("Re-check") {
                    Task { await checkExiftool() }
                }
                .buttonStyle(MetaBurnSecondaryButtonStyle())
                .disabled(installingExiftool)
            }
            Text("brew install exiftool")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MetaBurnTheme.background)
    }

    // MARK: - Main

    private var mainView: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(MetaBurnTheme.divider)
            if hasResults {
                resultsLayout
            } else {
                emptyLayout
            }
        }
        .background(MetaBurnTheme.background)
        .frame(minWidth: 720, minHeight: 640)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: runner.log.count) { _, _ in
            if selectedEntry == nil {
                selectedEntry = sortedLog.first
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MetaBurnTheme.accent)
            Text("MetaBurn")
                .font(.system(size: 16, weight: .semibold))
                .onTapGesture(count: 2) { showAbout() }
                .contextMenu {
                    Button("Check for Updates…") { checkForUpdates() }
                    Button("About MetaBurn") { showAbout() }
                }

            if runner.typeCounts.hasAny {
                typeCountBubbles
            }

            Spacer(minLength: 8)

            statusCapsule

            if processing {
                Button("Cancel") { runner.cancel() }
                    .buttonStyle(MetaBurnSecondaryButtonStyle())
            } else if hasResults {
                Button("Clear") { clearLog() }
                    .buttonStyle(MetaBurnSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var typeCountBubbles: some View {
        HStack(spacing: 6) {
            if runner.typeCounts.images > 0 {
                typeBubble(
                    label: "Photos",
                    done: runner.typeCounts.imagesDone,
                    total: runner.typeCounts.images
                )
            }
            if runner.typeCounts.videos > 0 {
                typeBubble(
                    label: "Videos",
                    done: runner.typeCounts.videosDone,
                    total: runner.typeCounts.videos
                )
            }
            if runner.typeCounts.other > 0 {
                typeBubble(
                    label: "Other",
                    done: runner.typeCounts.otherDone,
                    total: runner.typeCounts.other
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(typeCountsAccessibilityLabel)
    }

    private func typeBubble(label: String, done: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(typeCountText(done: done, total: total))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MetaBurnTheme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MetaBurnTheme.divider, lineWidth: 1)
        )
    }

    private func typeCountText(done: Int, total: Int) -> String {
        if processing || done < total {
            return "\(done)/\(total)"
        }
        return "\(total)"
    }

    private var typeCountsAccessibilityLabel: String {
        var parts: [String] = []
        let counts = runner.typeCounts
        if counts.images > 0 {
            parts.append("Photos \(typeCountText(done: counts.imagesDone, total: counts.images))")
        }
        if counts.videos > 0 {
            parts.append("Videos \(typeCountText(done: counts.videosDone, total: counts.videos))")
        }
        if counts.other > 0 {
            parts.append("Other \(typeCountText(done: counts.otherDone, total: counts.other))")
        }
        return parts.joined(separator: ", ")
    }

    private var statusCapsule: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(stateLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(MetaBurnTheme.surface)
        .clipShape(Capsule())
    }

    private var emptyLayout: some View {
        VStack(spacing: 12) {
            dropZone
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let notice = dropNotice {
                noticeBanner(notice)
            } else if let message = runner.message,
                      runner.state == .done || runner.state == .failed || runner.state == .cancelled {
                noticeBanner(message)
            }

            HStack {
                Spacer(minLength: 0)
                muteFooterToggle
            }
            .padding(.top, 4)

            Text("Cleaned copies go to Desktop/MetaBurn only when needed (Photos, Videos, or Skippable). Originals stay untouched.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Text("We strip hidden metadata (and can mute video sound). We don’t change what’s visible in the picture or video.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsLayout: some View {
        VStack(spacing: 0) {
            if let notice = dropNotice {
                noticeBanner(notice)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            summaryStrip
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider().overlay(MetaBurnTheme.divider)

            HStack(spacing: 0) {
                fileSidebar
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
                Divider().overlay(MetaBurnTheme.divider)
                detailPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(MetaBurnTheme.divider)
            footerBar
        }
    }

    /// Counters + outcome in one compact strip (avoids stacked banner gap).
    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                counterPill("Found", runner.counters.supported, .secondary)
                counterPill("Cleaned", runner.counters.cleaned, .green)
                counterPill("Skipped", runner.counters.skipped, .secondary)
                counterPill("Leftovers", runner.counters.partial, .orange)
                counterPill("Failed", runner.counters.failed, .red)
                Spacer(minLength: 0)
                if processing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let currentFile = runner.currentFile {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cleaning \(runner.currentFileNumber) of \(runner.counters.supported):")
                        .font(.system(size: 12, weight: .semibold))
                    Text(URL(fileURLWithPath: currentFile).lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
            }

            if runner.state == .done || runner.state == .failed || runner.state == .cancelled {
                HStack(spacing: 6) {
                    Image(systemName: outcomeIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(bannerColor)
                    Text(outcomeTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(outcomeSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(bannerColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var dropZone: some View {
        Button {
            browseFiles()
        } label: {
            VStack(spacing: 10) {
                if processing {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(.bottom, 2)
                } else {
                    Image(systemName: isDragging ? "arrow.down.doc.fill" : "square.and.arrow.down")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(isDragging ? MetaBurnTheme.accent : .secondary)
                }
                Text(processing ? "Processing…" : "Drop photos, videos, or folders")
                    .font(.system(size: 17, weight: .semibold))
                Text(processing ? "Saving cleaned copies…" : "Click to browse · cleaned copies → Desktop/MetaBurn when needed")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDragging ? MetaBurnTheme.accent.opacity(0.12) : MetaBurnTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDragging ? MetaBurnTheme.accent : MetaBurnTheme.divider,
                        style: StrokeStyle(lineWidth: isDragging ? 2 : 1.5, dash: isDragging ? [] : [8, 6])
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(processing || exiftoolReady != true)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    private func counterPill(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(MetaBurnTheme.surface)
        .clipShape(Capsule())
    }

    private var fileSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(processing ? "\(sortedLog.count)/\(runner.counters.supported)" : "\(sortedLog.count)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider().overlay(MetaBurnTheme.divider)

            List(selection: Binding(
                get: { selectedEntry?.id },
                set: { id in selectedEntry = sortedLog.first { $0.id == id } }
            )) {
                if let currentFile = runner.currentFile {
                    ProcessingFileRow(path: currentFile)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                }
                ForEach(sortedLog) { entry in
                    FileRow(entry: entry)
                        .tag(entry.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(MetaBurnTheme.background)
        }
        .background(MetaBurnTheme.background)
    }

    private var detailPane: some View {
        Group {
            if let entry = selectedEntry ?? sortedLog.first {
                MetadataReport(entry: entry)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 29))
                        .foregroundStyle(.secondary)
                    Text("Select a file to inspect before-and-after metadata.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MetaBurnTheme.background)
    }

    private var footerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                browseFiles()
            } label: {
                Label("Add more…", systemImage: "plus")
            }
            .buttonStyle(MetaBurnSecondaryButtonStyle())
            .disabled(processing)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var muteFooterToggle: some View {
        Toggle(isOn: $muteAudio) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muteAudio ? MetaBurnTheme.accent : .secondary)
                Text("Mute video audio")
                    .font(.system(size: 13))
            }
        }
        .toggleStyle(RedSwitchToggleStyle())
        .disabled(processing)
    }

    // MARK: - Status helpers

    private var statusColor: Color {
        switch runner.state {
        case .waiting, .cancelled: .secondary
        case .scanning, .cleaning: .blue
        case .done: .green
        case .failed, .exiftoolMissing: .red
        }
    }

    private var stateLabel: String {
        switch runner.state {
        case .waiting: "Waiting"
        case .scanning: "Scanning"
        case .cleaning: "Cleaning"
        case .done: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .exiftoolMissing: "ExifTool missing"
        }
    }

    private var bannerColor: Color {
        switch runner.state {
        case .done: .green
        case .failed: .red
        case .cancelled: .secondary
        default: .secondary
        }
    }

    private var outcomeIcon: String {
        switch runner.state {
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "slash.circle.fill"
        default: "info.circle.fill"
        }
    }

    private var outcomeTitle: String {
        switch runner.state {
        case .done:
            if runner.counters.supported == 0 {
                return "No supported media found"
            }
            if runner.counters.failed > 0 || runner.counters.partial > 0 {
                return "Finished with issues"
            }
            return "Metadata removed"
        case .failed: return runner.message ?? "Processing failed"
        case .cancelled: return "Cancelled"
        default: return runner.state.rawValue.capitalized
        }
    }

    private var outcomeSubtitle: String {
        if runner.state == .done, runner.counters.supported == 0 {
            return runner.message
                ?? "Drop photos, videos, or a folder that contains them."
        }
        var parts: [String] = []
        if runner.counters.cleaned > 0 {
            parts.append("\(runner.counters.cleaned) saved to Desktop/MetaBurn")
        }
        if runner.counters.skipped > 0 {
            parts.append(
                "\(runner.counters.skipped) skipped → Desktop/MetaBurn/\(OutputNaming.skippableFolderName)"
            )
        }
        if runner.counters.partial > 0 {
            parts.append("\(runner.counters.partial) with leftovers")
        }
        if runner.counters.failed > 0 {
            parts.append("\(runner.counters.failed) failed")
        }
        if parts.isEmpty {
            return "No supported files were processed."
        }
        return parts.joined(separator: " · ")
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Actions

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard exiftoolReady == true, !processing else { return false }
        let group = DispatchGroup()
        var paths: [String] = []
        var loaded = 0
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    paths.append(url.path)
                    loaded += 1
                } else if let url = item as? URL {
                    paths.append(url.path)
                    loaded += 1
                }
            }
        }
        group.notify(queue: .main) {
            if paths.isEmpty {
                dropNotice = loaded > 0
                    ? "Couldn't read those items' file paths. Click the drop area to browse instead."
                    : "No files detected. Drop photos, videos, or a folder — or click to browse."
            } else {
                dropNotice = nil
                startJob(paths: paths)
            }
        }
        return true
    }

    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .movie, .data]
        if !lastBrowseDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: lastBrowseDirectory)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        }
        if panel.runModal() == .OK {
            if let firstURL = panel.urls.first {
                lastBrowseDirectory = firstURL.deletingLastPathComponent().path
            }
            dropNotice = nil
            startJob(paths: panel.urls.map(\.path))
        }
    }

    private func startJob(paths: [String]) {
        selectedEntry = nil
        runner.start(droppedPaths: paths, muteAudio: muteAudio)
    }

    private func clearLog() {
        selectedEntry = nil
        dropNotice = nil
        runner.reset()
    }

    private func checkExiftool() async {
        if await MetadataCleaner.resolveExiftool() != nil {
            exiftoolReady = true
            canInstallExiftool = false
        } else {
            exiftoolReady = false
            canInstallExiftool = await MetadataCleaner.resolveBrew() != nil
        }
    }

    private func installExiftool() async {
        installingExiftool = true
        let result = await MetadataCleaner.installExiftool()
        if result.success { await checkExiftool() }
        installingExiftool = false
    }

    private func showAbout() {
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
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func checkForUpdates() {
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
}

// MARK: - File row

private struct ProcessingFileRow: View {
    let path: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Cleaning")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }
}

private struct FileRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: entry.path).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.status.rawValue.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                if let reason = entry.reason, entry.status != .cleaned {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch entry.status {
        case .cleaned: .green
        case .partial: .orange
        case .skipped: .secondary
        case .failed: .red
        }
    }
}

// MARK: - Theme / buttons

enum MetaBurnTheme {
    static let accent = Color(red: 0.90, green: 0.22, blue: 0.22)

    static var background: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            }
            return NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        })
    }

    static var surface: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white.withAlphaComponent(0.06)
            }
            return NSColor.black.withAlphaComponent(0.05)
        })
    }

    static var divider: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white.withAlphaComponent(0.10)
            }
            return NSColor.black.withAlphaComponent(0.12)
        })
    }
}

struct MetaBurnPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(MetaBurnTheme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct MetaBurnSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MetaBurnTheme.surface.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(MetaBurnTheme.divider, lineWidth: 1)
            )
    }
}

struct RedSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    configuration.isOn.toggle()
                }
            } label: {
                Capsule()
                    .fill(configuration.isOn ? MetaBurnTheme.accent : Color(red: 0.55, green: 0.15, blue: 0.15))
                    .frame(width: 40, height: 22)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1)
                            .padding(2.5),
                        alignment: configuration.isOn ? .trailing : .leading
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
