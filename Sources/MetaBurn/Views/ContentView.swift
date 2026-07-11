import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var runner = TaskRunner()
    @State private var exiftoolReady: Bool? = nil
    @State private var canInstallExiftool = false
    @State private var installingExiftool = false
    @State private var ffmpegReady: Bool? = nil
    @State private var canInstallFfmpeg = false
    @State private var installingFfmpeg = false
    @State private var muteAudio = false
    @State private var isDragging = false
    @State private var dropNotice: String? = nil
    @State private var selectedEntry: LogEntry? = nil

    private var processing: Bool {
        runner.state == .scanning || runner.state == .cleaning
    }

    private var hasResults: Bool {
        !runner.log.isEmpty
    }

    var body: some View {
        Group {
            if exiftoolReady == false {
                missingExiftoolView
            } else {
                mainView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await checkExiftool() }
        }
    }

    // MARK: - Missing ExifTool

    private var missingExiftoolView: some View {
        VStack(spacing: 20) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44))
                .foregroundStyle(MetaBurnTheme.accent)
            Text("ExifTool is required")
                .font(.system(size: 22, weight: .semibold))
            Text("MetaBurn uses ExifTool to strip metadata locally.\nInstall it with Homebrew, then re-check.")
                .font(.system(size: 13))
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
                .font(.system(size: 12, design: .monospaced))
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
        .frame(minWidth: 640, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onAppear { Task { await checkFfmpeg() } }
        .onChange(of: runner.log.count) { _, _ in
            if selectedEntry == nil {
                selectedEntry = runner.log.first
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MetaBurnTheme.accent)
            Text("MetaBurn")
                .font(.system(size: 15, weight: .semibold))
                .onTapGesture(count: 2) { showAbout() }
                .contextMenu {
                    Button("Check for Updates…") { checkForUpdates() }
                    Button("About MetaBurn") { showAbout() }
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

    private var statusCapsule: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(stateLabel)
                .font(.system(size: 12, weight: .medium))
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
            }

            muteRow

            if muteAudio, ffmpegReady == false {
                ffmpegNotice
            }

            Text("Files are cleaned in place — originals are modified, no copies are created.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(16)
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
                counterPill("Partial", runner.counters.partial, .orange)
                counterPill("Failed", runner.counters.failed, .red)
                Spacer(minLength: 0)
                if processing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if runner.state == .done || runner.state == .failed || runner.state == .cancelled {
                HStack(spacing: 6) {
                    Image(systemName: outcomeIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(bannerColor)
                    Text(outcomeTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(outcomeSubtitle)
                        .font(.system(size: 11))
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
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(isDragging ? MetaBurnTheme.accent : .secondary)
                }
                Text(processing ? "Processing…" : "Drop photos, videos, or folders")
                    .font(.system(size: 16, weight: .semibold))
                Text(processing ? "Cleaning metadata in place…" : "Click to browse · originals are modified in place")
                    .font(.system(size: 12))
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
                        isDragging ? MetaBurnTheme.accent : Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: isDragging ? 2 : 1.5, dash: isDragging ? [] : [8, 6])
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(processing || exiftoolReady != true)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    private var muteRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mute video audio")
                    .font(.system(size: 13, weight: .semibold))
                Text("Remove audio tracks before cleaning metadata.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $muteAudio)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(processing)
                .onChange(of: muteAudio) { _, _ in
                    Task { await checkFfmpeg() }
                }
        }
        .padding(12)
        .background(MetaBurnTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var ffmpegNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("ffmpeg is required to mute audio.")
                .font(.system(size: 12))
            Spacer()
            if canInstallFfmpeg {
                Button(installingFfmpeg ? "Installing…" : "Install") {
                    Task { await installFfmpeg() }
                }
                .buttonStyle(MetaBurnSecondaryButtonStyle())
                .disabled(installingFfmpeg)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func counterPill(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(runner.log.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider().overlay(MetaBurnTheme.divider)

            List(selection: Binding(
                get: { selectedEntry?.id },
                set: { id in selectedEntry = runner.log.first { $0.id == id } }
            )) {
                ForEach(runner.log) { entry in
                    FileRow(entry: entry)
                        .tag(entry.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(MetaBurnTheme.background)
        }
        .background(MetaBurnTheme.background)
    }

    private var detailPane: some View {
        Group {
            if let entry = selectedEntry ?? runner.log.first {
                MetadataReport(entry: entry)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Select a file to inspect before-and-after metadata.")
                        .font(.system(size: 13))
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

            muteCompact

            Spacer(minLength: 8)

            Text("In-place · no copies")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var muteCompact: some View {
        Toggle(isOn: $muteAudio) {
            Text("Mute audio")
                .font(.system(size: 12))
        }
        .toggleStyle(.checkbox)
        .disabled(processing)
        .onChange(of: muteAudio) { _, _ in
            Task { await checkFfmpeg() }
        }
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
        var parts: [String] = []
        if runner.counters.cleaned > 0 {
            parts.append("\(runner.counters.cleaned) cleaned in place")
        }
        if runner.counters.skipped > 0 {
            parts.append("\(runner.counters.skipped) skipped / rejected")
        }
        if runner.counters.partial > 0 {
            parts.append("\(runner.counters.partial) partial")
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
                .font(.system(size: 12))
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
        if panel.runModal() == .OK {
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

    private func checkFfmpeg() async {
        if await MetadataCleaner.resolveFfmpeg() != nil {
            ffmpegReady = true
            canInstallFfmpeg = false
        } else {
            ffmpegReady = false
            canInstallFfmpeg = await MetadataCleaner.resolveBrew() != nil
        }
    }

    private func installExiftool() async {
        installingExiftool = true
        let result = await MetadataCleaner.installExiftool()
        if result.success { await checkExiftool() }
        installingExiftool = false
    }

    private func installFfmpeg() async {
        installingFfmpeg = true
        let result = await MetadataCleaner.installFfmpeg()
        if result.success { await checkFfmpeg() }
        installingFfmpeg = false
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

private struct FileRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: entry.path).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.status.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                if let reason = entry.reason, entry.status != .cleaned {
                    Text(reason)
                        .font(.system(size: 10))
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
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let surface = Color.white.opacity(0.06)
    static let divider = Color.white.opacity(0.10)
    static let accent = Color(red: 0.90, green: 0.22, blue: 0.22)
}

struct MetaBurnPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
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
            .font(.system(size: 11, weight: .medium))
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
