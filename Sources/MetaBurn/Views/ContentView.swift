import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MetaBurnCore

private enum MetaBurnView {
    case files
    case details(LogEntry)
}

struct ContentView: View {
    @StateObject private var runner = TaskRunner()
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"
    @State private var muteAudio = true
    @State private var isDragging = false
    @State private var dropNotice: String? = nil
    @State private var pane: MetaBurnView = .files

    private var processing: Bool {
        runner.state == .scanning || runner.state == .downloading || runner.state == .cleaning
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

    private var dropHighlighted: Bool {
        isDragging
    }

    var body: some View {
        mainView
            .preferredColorScheme(preferredScheme)
            .navigationTitle("MetaBurn")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
            .onAppear {
                ThemePreference.applyAppAppearance(for: themeSource)
            }
            .onChange(of: themeSource) { _, newValue in
                ThemePreference.applyAppAppearance(for: newValue)
            }
    }

    private var mainView: some View {
        ZStack {
            MetaBurnTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HeaderView(typeCounts: runner.typeCounts, processing: processing)

                if let notice = dropNotice {
                    noticeBanner(notice)
                } else if let message = runner.message,
                          runner.state == .done || runner.state == .failed || runner.state == .cancelled {
                    noticeBanner(message)
                }

                DropZoneView(
                    highlighted: dropHighlighted,
                    processing: processing,
                    primary: dropPrimaryLabel,
                    secondary: dropSecondaryLabel
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: hasResults ? 140 : 240, maxHeight: hasResults ? 200 : .infinity)

                if hasResults {
                    resultsSplit
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                FooterBar(
                    processing: processing,
                    hasResults: hasResults,
                    count: runner.counters.cleaned,
                    currentFile: runner.currentFile,
                    currentFileNumber: runner.currentFileNumber,
                    supported: runner.counters.supported,
                    state: runner.state,
                    muteAudio: $muteAudio,
                    onCancel: { runner.cancel() }
                )
            }
            .padding(32)
        }
        .frame(minWidth: 900, minHeight: 720)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: runner.log.count) { _, _ in
            autoSelectFirstResultIfNeeded()
        }
    }

    private var selectedFileID: UUID? {
        if case .details(let file) = pane { return file.id }
        return nil
    }

    private var resultsSplit: some View {
        Group {
            if case .details(let file) = pane {
                HSplitView {
                    cleanedFilesList
                        .frame(minWidth: 280, idealWidth: 380, maxWidth: .infinity)
                    FileDetailsView(
                        file: sortedLog.first(where: { $0.id == file.id }) ?? file,
                        onBack: { pane = .files },
                        embedded: true
                    )
                    .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity)
                }
            } else {
                cleanedFilesList
            }
        }
        .background(MetaBurnTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
        )
    }

    private var cleanedFilesList: some View {
        CleanedFilesPanel(
            files: sortedLog,
            currentFile: runner.currentFile,
            selectedID: selectedFileID,
            canReveal: revealableURLs.isEmpty == false,
            onReveal: revealInFinder,
            onSelect: { pane = .details($0) }
        )
    }

    private func autoSelectFirstResultIfNeeded() {
        guard case .files = pane, let first = sortedLog.first else { return }
        pane = .details(first)
    }

    private var dropPrimaryLabel: String {
        if processing {
            return processingPrimaryLabel
        }
        return dropHighlighted ? "Drop to clean" : "Drop photos or videos"
    }

    private var dropSecondaryLabel: String {
        if processing {
            return processingSecondaryLabel
        }
        return "Files are cleaned locally. Nothing is uploaded."
    }

    private var processingPrimaryLabel: String {
        switch runner.state {
        case .downloading: return "Downloading from iCloud…"
        case .scanning: return "Scanning…"
        default: return "Processing…"
        }
    }

    private var processingSecondaryLabel: String {
        switch runner.state {
        case .downloading: return "Waiting for iCloud Drive to finish downloading"
        case .scanning: return "Looking for photos and videos…"
        default:
            if let current = runner.currentFile {
                return "Cleaning \(runner.currentFileNumber) of \(runner.counters.supported): \(URL(fileURLWithPath: current).lastPathComponent)"
            }
            return "Saving cleaned copies locally"
        }
    }

    private var revealableURLs: [URL] {
        sortedLog.compactMap { entry in
            guard entry.status == .cleaned || entry.status == .partial else { return nil }
            let url = URL(fileURLWithPath: entry.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private func revealInFinder() {
        let urls = revealableURLs
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !processing else { return false }
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
                    ? "Couldn't read those items' file paths. Try dropping again."
                    : "No files detected. Drop photos, videos, or a folder."
            } else {
                dropNotice = nil
                pane = .files
                runner.start(droppedPaths: paths, muteAudio: muteAudio)
            }
        }
        return true
    }
}

// MARK: - Header

private struct HeaderView: View {
    let typeCounts: TypeCounts
    let processing: Bool

    var body: some View {
        VStack(spacing: 10) {
            MetaBurnFireImage()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                (Text("Meta").foregroundColor(.primary) + Text("Burn").foregroundColor(MetaBurnTheme.accent))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .onTapGesture(count: 2) { showAbout() }
                    .contextMenu {
                        Button("Check for Updates…") { checkForUpdates() }
                        Button("About MetaBurn") { showAbout() }
                    }
                Text("Privacy protection for your photos and videos.")
                    .font(.system(size: 14))
                    .foregroundColor(MetaBurnTheme.secondaryText)
            }
            .multilineTextAlignment(.center)

            if typeCounts.hasAny {
                typeCountBubbles
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var typeCountBubbles: some View {
        HStack(spacing: 8) {
            if typeCounts.images > 0 {
                typeBubble(label: "Photos", done: typeCounts.imagesDone, total: typeCounts.images)
            }
            if typeCounts.videos > 0 {
                typeBubble(label: "Videos", done: typeCounts.videosDone, total: typeCounts.videos)
            }
            if typeCounts.other > 0 {
                typeBubble(label: "Other", done: typeCounts.otherDone, total: typeCounts.other)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(typeCountsAccessibilityLabel)
        .padding(.top, 4)
    }

    private func typeBubble(label: String, done: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MetaBurnTheme.secondaryText)
            Text(typeCountText(done: done, total: total))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(MetaBurnTheme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
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
        if typeCounts.images > 0 {
            parts.append("Photos \(typeCountText(done: typeCounts.imagesDone, total: typeCounts.images))")
        }
        if typeCounts.videos > 0 {
            parts.append("Videos \(typeCountText(done: typeCounts.videosDone, total: typeCounts.videos))")
        }
        if typeCounts.other > 0 {
            parts.append("Other \(typeCountText(done: typeCounts.otherDone, total: typeCounts.other))")
        }
        return parts.joined(separator: ", ")
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

// MARK: - Drop zone

private struct DropZoneView: View {
    let highlighted: Bool
    let processing: Bool
    let primary: String
    let secondary: String

    var body: some View {
        VStack(spacing: 14) {
            if processing {
                ProgressView()
                    .controlSize(.regular)
                    .tint(MetaBurnTheme.accent)
            } else {
                Image(systemName: highlighted ? "photo.stack.fill" : "photo.stack")
                    .font(.system(size: 46))
                    .foregroundStyle(MetaBurnTheme.accent)
            }
            Text(primary)
                .font(.system(size: 20, weight: .semibold))
            Text(secondary)
                .font(.system(size: 13))
                .foregroundColor(MetaBurnTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlighted ? MetaBurnTheme.accent.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    MetaBurnTheme.accent.opacity(highlighted ? 0.95 : 0.6),
                    style: StrokeStyle(lineWidth: highlighted ? 2 : 1.5, dash: highlighted ? [] : [6, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: highlighted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop zone")
        .accessibilityHint("Drop photos, videos, or folders to clean metadata")
    }
}

// MARK: - Cleaned files

private struct CleanedFilesPanel: View {
    let files: [LogEntry]
    let currentFile: String?
    let selectedID: UUID?
    let canReveal: Bool
    let onReveal: () -> Void
    let onSelect: (LogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cleaned Files")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Show in Finder", systemImage: "folder") {
                    onReveal()
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(!canReveal)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(MetaBurnTheme.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let currentFile {
                        fileRow(
                            path: currentFile,
                            statusText: "cleaning",
                            statusColor: .blue,
                            timestamp: nil,
                            selected: false,
                            showsProgress: true
                        )
                        Divider().overlay(MetaBurnTheme.hairline)
                    }

                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        fileRow(
                            path: file.path,
                            statusText: statusLabel(file.status),
                            statusColor: statusColor(file.status),
                            timestamp: FileTimestamp.display(file.finishedAt),
                            selected: file.id == selectedID
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(file) }
                        if index < files.count - 1 {
                            Divider().overlay(MetaBurnTheme.hairline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func fileRow(
        path: String,
        statusText: String,
        statusColor: Color,
        timestamp: String?,
        selected: Bool,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            fileNameCell(path: path)
            Image(systemName: "arrow.right")
                .foregroundColor(MetaBurnTheme.secondaryText)
            Text(statusText)
                .foregroundColor(statusColor)
            Spacer(minLength: 8)
            if let timestamp {
                Text(timestamp)
                    .foregroundColor(MetaBurnTheme.secondaryText)
            }
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(selected ? MetaBurnTheme.accent.opacity(0.28) : Color.clear)
    }

    private func fileNameCell(path: String) -> some View {
        HStack(spacing: 10) {
            FileTypeIcon(path: path)
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func statusLabel(_ status: CleanStatus) -> String {
        switch status {
        case .cleaned: "cleaned"
        case .partial: "leftovers"
        case .skipped: "skipped"
        case .failed: "failed"
        }
    }

    private func statusColor(_ status: CleanStatus) -> Color {
        switch status {
        case .cleaned: MetaBurnTheme.accent
        case .partial: .orange
        case .skipped: MetaBurnTheme.secondaryText
        case .failed: .red
        }
    }
}

private struct FileTypeIcon: View {
    let path: String

    var body: some View {
        let video = SupportedTypes.isVideo(filePath: path)
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MetaBurnTheme.surface)
                .frame(width: 32, height: 32)
            Image(systemName: video ? "play.fill" : "photo.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
        }
    }
}

private enum FileTimestamp {
    static func display(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return "Today, \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday, \(time)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let processing: Bool
    let hasResults: Bool
    let count: Int
    let currentFile: String?
    let currentFileNumber: Int
    let supported: Int
    let state: RunState
    @Binding var muteAudio: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: shieldIcon)
                .font(.system(size: 22))
                .foregroundStyle(MetaBurnTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(MetaBurnTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            muteToggle
            if processing {
                Button("Cancel") { onCancel() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var shieldIcon: String {
        switch state {
        case .failed: "xmark.shield.fill"
        case .cancelled: "slash.circle.fill"
        default: "checkmark.shield.fill"
        }
    }

    private var title: String {
        if processing {
            return supported > 0
                ? "Cleaning \(max(currentFileNumber, 1)) of \(supported)"
                : "Cleaning files…"
        }
        if hasResults {
            if count == 1 { return "1 file cleaned" }
            return "\(count) files cleaned"
        }
        return "Ready to clean"
    }

    private var subtitle: String {
        if processing {
            if let currentFile {
                return URL(fileURLWithPath: currentFile).lastPathComponent
            }
            return "Metadata is stripped on this Mac only."
        }
        if hasResults {
            return "Metadata removed and files saved locally."
        }
        return "Mute permanently omits audio tracks from cleaned videos."
    }

    private var muteToggle: some View {
        Toggle(isOn: $muteAudio) {
            HStack(spacing: 8) {
                Image(systemName: muteAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muteAudio ? MetaBurnTheme.accent : MetaBurnTheme.secondaryText)
                Text("Mute video audio")
                    .font(.system(size: 13))
            }
        }
        .toggleStyle(RedSwitchToggleStyle())
        .disabled(processing)
        .help("When on, cleaned videos have audio tracks omitted so they cannot be recovered.")
    }
}

// MARK: - Theme / buttons

enum MetaBurnTheme {
    static let accent = Color(red: 0.90, green: 0.12, blue: 0.10)
    static let secondaryText = Color.primary.opacity(0.55)
    static let hairline = Color.primary.opacity(0.10)

    static var background: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.055, green: 0.06, blue: 0.065, alpha: 1)
            }
            return NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        })
    }

    static var surface: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.075, green: 0.08, blue: 0.085, alpha: 1)
            }
            return NSColor.black.withAlphaComponent(0.05)
        })
    }

    static var divider: Color { hairline }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MetaBurnTheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

struct MetaBurnPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

struct MetaBurnSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButtonStyle().makeBody(configuration: configuration)
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
