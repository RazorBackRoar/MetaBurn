import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MetaBurnCore

struct ContentView: View {
    @StateObject private var runner = TaskRunner()
    @StateObject private var workspace = WorkspaceStore()
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"
    @State private var removeAudio = true
    @State private var isDragging = false
    @State private var dropNotice: String?
    @State private var showWorkspace = false

    private var processing: Bool {
        runner.state == .scanning || runner.state == .downloading || runner.state == .cleaning
    }

    private var hasResults: Bool {
        !runner.log.isEmpty || (runner.state == .done && runner.counters.skipped > 0 && runner.counters.supported == 0)
    }

    private var sortedLog: [LogEntry] {
        runner.log.sorted { lhs, rhs in
            let lhsUnmodified = lhs.status == .skipped || lhs.status == .failed
            let rhsUnmodified = rhs.status == .skipped || rhs.status == .failed
            if lhsUnmodified != rhsUnmodified {
                return !lhsUnmodified
            }
            return lhs.finishedAt < rhs.finishedAt
        }
    }

    private var preferredScheme: ColorScheme? {
        ThemePreference.colorScheme(for: themeSource)
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
                workspace.refresh()
            }
            .onChange(of: themeSource) { _, newValue in
                ThemePreference.applyAppAppearance(for: newValue)
            }
    }

    private var mainView: some View {
        ZStack {
            MetaBurnTheme.background
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HeaderView(typeCounts: runner.typeCounts, processing: processing)

                if let notice = dropNotice {
                    noticeBanner(notice)
                } else if let message = runner.message,
                          runner.state == .done || runner.state == .failed || runner.state == .cancelled {
                    noticeBanner(message)
                }

                DropZoneView(
                    highlighted: isDragging,
                    processing: processing,
                    compact: showWorkspace,
                    primary: dropPrimaryLabel,
                    secondary: dropSecondaryLabel
                )
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: showWorkspace ? 66 : (hasResults ? 190 : 250),
                    maxHeight: showWorkspace ? 76 : (hasResults ? 230 : .infinity)
                )

                if showWorkspace {
                    WorkspaceView(store: workspace) {
                        showWorkspace = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
                } else if hasResults {
                    CleanedFilesPanel(
                        files: sortedLog,
                        currentFile: runner.currentFile,
                        canReveal: !revealableURLs.isEmpty,
                        onReveal: revealInFinder
                    )
                    .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
                }

                FooterBar(
                    processing: processing,
                    hasResults: hasResults,
                    count: runner.counters.cleaned,
                    currentFile: runner.currentFile,
                    currentFileNumber: runner.currentFileNumber,
                    supported: runner.counters.supported,
                    state: runner.state,
                    removeAudio: $removeAudio,
                    onCancel: { runner.cancel() },
                    onOpenFiles: {
                        workspace.refresh()
                        showWorkspace = true
                    }
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(minWidth: 780, minHeight: 620)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: runner.log.count) { _, _ in
            workspace.refresh()
        }
    }

    private var dropPrimaryLabel: String {
        if processing {
            switch runner.state {
            case .downloading: return "Downloading from iCloud…"
            case .scanning: return "Scanning…"
            default: return "Processing…"
            }
        }
        return isDragging ? "Drop to clean" : "Drop photos or videos"
    }

    private var dropSecondaryLabel: String {
        if processing {
            switch runner.state {
            case .downloading:
                return "Waiting for iCloud Drive to finish downloading"
            case .scanning:
                return "Copying supported media into MetaBurn's private workspace"
            default:
                if let current = runner.currentFile {
                    return "Cleaning \(runner.currentFileNumber) of \(runner.counters.supported): \(URL(fileURLWithPath: current).lastPathComponent)"
                }
                return "Cleaning and verifying private copies"
            }
        }
        return "Files are copied and cleaned locally. Originals stay untouched."
    }

    private var revealableURLs: [URL] {
        sortedLog.compactMap { entry in
            guard entry.status == .cleaned || entry.status == .partial else { return nil }
            let url = URL(fileURLWithPath: entry.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private func revealInFinder() {
        guard !revealableURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(revealableURLs)
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
        .padding(9)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !processing else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var paths: [String] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    lock.lock()
                    paths.append(url.path)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            if paths.isEmpty {
                dropNotice = "No files detected. Drop photos, videos, or a folder."
            } else {
                dropNotice = nil
                runner.start(droppedPaths: paths, muteAudio: removeAudio)
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
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MetaBurnTheme.surface)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    MetaBurnFireImage()
                        .padding(8)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    (Text("Meta").foregroundColor(.primary) + Text("Burn").foregroundColor(MetaBurnTheme.accent))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .onTapGesture(count: 2) { showAbout() }
                        .contextMenu {
                            Button("Check for Updates…") { checkForUpdates() }
                            Button("About MetaBurn") { showAbout() }
                        }
                    Text("Privacy protection for your photos and videos.")
                        .font(.system(size: 13))
                        .foregroundColor(MetaBurnTheme.secondaryText)
                }
            }

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
    }

    private func typeBubble(label: String, done: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MetaBurnTheme.secondaryText)
            Text(typeCountText(done: done, total: total))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(MetaBurnTheme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(MetaBurnTheme.hairline, lineWidth: 1))
    }

    private func typeCountText(done: Int, total: Int) -> String {
        processing || done < total ? "\(done)/\(total)" : "\(total)"
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
    let compact: Bool
    let primary: String
    let secondary: String

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 12) {
                    dropGlyph
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primary)
                            .font(.system(size: 14, weight: .semibold))
                        Text(secondary)
                            .font(.system(size: 11))
                            .foregroundColor(MetaBurnTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 11) {
                    dropGlyph
                    Text(primary)
                        .font(.system(size: 18, weight: .semibold))
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundColor(MetaBurnTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .fill(highlighted ? MetaBurnTheme.accent.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .strokeBorder(
                    MetaBurnTheme.accent.opacity(highlighted ? 0.95 : 0.75),
                    style: StrokeStyle(lineWidth: highlighted ? 2 : 1.4, dash: highlighted ? [] : [6, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: highlighted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop zone")
        .accessibilityHint("Drop photos, videos, or folders to copy and clean metadata")
    }

    @ViewBuilder
    private var dropGlyph: some View {
        if processing {
            ProgressView()
                .controlSize(compact ? .small : .regular)
                .tint(MetaBurnTheme.accent)
        } else {
            Image(systemName: highlighted ? "photo.stack.fill" : "photo.stack")
                .font(.system(size: compact ? 21 : 42))
                .foregroundStyle(MetaBurnTheme.accent)
        }
    }
}

// MARK: - Cleaned files

private struct CleanedFilesPanel: View {
    let files: [LogEntry]
    let currentFile: String?
    let canReveal: Bool
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cleaned Files")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Show in Finder", systemImage: "folder") { onReveal() }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(!canReveal)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().overlay(MetaBurnTheme.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let currentFile {
                        fileRow(
                            path: currentFile,
                            statusText: "Processing",
                            statusColor: .blue,
                            timestamp: nil,
                            showsProgress: true
                        )
                        Divider().overlay(MetaBurnTheme.hairline)
                    }

                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        fileRow(
                            path: file.path,
                            statusText: statusLabel(file.status),
                            statusColor: statusColor(file.status),
                            timestamp: FileTimestamp.display(file.finishedAt)
                        )
                        if index < files.count - 1 {
                            Divider().overlay(MetaBurnTheme.hairline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MetaBurnTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
        )
    }

    private func fileRow(
        path: String,
        statusText: String,
        statusColor: Color,
        timestamp: String?,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            FileTypeIcon(path: path)
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .foregroundColor(MetaBurnTheme.secondaryText)
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusColor)
            Spacer(minLength: 8)
            if let timestamp {
                Text(timestamp)
                    .font(.system(size: 11))
                    .foregroundColor(MetaBurnTheme.secondaryText)
            }
            if showsProgress {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func statusLabel(_ status: CleanStatus) -> String {
        switch status {
        case .cleaned: "Metadata Cleared"
        case .partial: "Unable to Fully Clear"
        case .skipped: "Error"
        case .failed: "Error"
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
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 28, height: 28)
            Image(systemName: SupportedTypes.isVideo(filePath: path) ? "play.fill" : "photo.fill")
                .font(.system(size: 11, weight: .medium))
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
    @Binding var removeAudio: Bool
    let onCancel: () -> Void
    let onOpenFiles: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: shieldIcon)
                    .font(.system(size: 21))
                    .foregroundStyle(MetaBurnTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(MetaBurnTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if processing {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(GhostButtonStyle())
                }
                Button("Open Files") { onOpenFiles() }
                    .buttonStyle(PrimaryButtonStyle())
                    .help("Open MetaBurn's private Photos and Videos workspace")
            }
            .frame(maxWidth: .infinity)

            Toggle(isOn: $removeAudio) {
                HStack(spacing: 6) {
                    Image(systemName: removeAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(removeAudio ? MetaBurnTheme.accent : MetaBurnTheme.secondaryText)
                    Text("Remove audio")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .toggleStyle(RedSwitchToggleStyle())
            .disabled(processing)
            .help("Permanently omit audio tracks from cleaned video copies")
            .accessibilityHint("When enabled, cleaned videos contain no audio tracks")
            .frame(maxWidth: .infinity, alignment: .trailing)
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
            return supported > 0 ? "Processing \(max(currentFileNumber, 1)) of \(supported)" : "Processing files…"
        }
        if hasResults {
            return count == 1 ? "1 file cleaned" : "\(count) files cleaned"
        }
        return "Ready to clean"
    }

    private var subtitle: String {
        if processing {
            return currentFile.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? "Copying, cleaning, and verifying locally."
        }
        if hasResults {
            return "Verified copies are ready in Open Files."
        }
        return "Original files are never modified."
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
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
        HStack(spacing: 7) {
            configuration.label
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    configuration.isOn.toggle()
                }
            } label: {
                Capsule()
                    .fill(configuration.isOn ? MetaBurnTheme.accent : Color(red: 0.48, green: 0.12, blue: 0.12))
                    .frame(width: 34, height: 19)
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
