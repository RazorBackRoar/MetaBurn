import AppKit
import MetaBurnCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var runner = TaskRunner()
    @StateObject private var workspace = WorkspaceStore()
    @AppStorage(ThemePreference.storageKey) private var themeSource: String = "system"
    @State private var removeAudio = true
    @State private var isDragging = false
    @State private var dropFlash = false
    @State private var dropNotice: String?
    @State private var showWorkspace = false
    @State private var fire = FireStageController()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var processing: Bool {
        runner.state == .scanning || runner.state == .downloading || runner.state == .cleaning
    }

    private var hasResults: Bool {
        !runner.log.isEmpty
            || (runner.state == .done && runner.counters.skipped > 0
                && runner.counters.supported == 0)
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
            FireStageView(
                controller: fire,
                isLight: colorScheme == .light,
                reduceMotion: reduceMotion
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            chromeColumn
        }
        .frame(minWidth: 900, minHeight: 720)
        .onDrop(
            of: [.fileURL],
            delegate: FileDropDelegate(
                processing: processing,
                isDragging: $isDragging,
                fire: fire,
                onDrop: { paths, location in
                    handleDrop(paths: paths, location: location)
                }
            )
        )
        .onChange(of: runner.log.count) { _, _ in
            workspace.refresh()
        }
        .onChange(of: isDragging) { _, _ in
            refreshFireMood()
        }
        .onChange(of: runner.state) { _, newState in
            refreshFireMood()
            if newState == .done {
                fire.celebrate()
            }
        }
        .onAppear {
            refreshFireMood()
        }
    }

    @ViewBuilder
    private var chromeColumn: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { mainColumn }
        } else {
            mainColumn
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 24) {
            HeaderView(typeCounts: runner.typeCounts, processing: processing)

            if let notice = dropNotice {
                noticeBanner(notice)
            } else if let message = runner.message,
                runner.state == .done || runner.state == .failed || runner.state == .cancelled
            {
                noticeBanner(message)
            }

            DropZoneView(
                highlighted: isDragging || dropFlash,
                processing: processing,
                compact: showWorkspace,
                primary: dropPrimaryLabel,
                secondary: dropSecondaryLabel
            )
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: showWorkspace ? 66 : (hasResults ? 140 : 240),
                maxHeight: showWorkspace ? 76 : (hasResults ? 200 : .infinity)
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
                    inFlightCount: runner.inFlightCount,
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
        .padding(32)
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
                    let name = URL(fileURLWithPath: current).lastPathComponent
                    if runner.inFlightCount > 1 {
                        return
                            "Cleaning \(runner.inFlightCount) files at once — \(runner.currentFileNumber) of \(runner.counters.supported): \(name)"
                    }
                    return
                        "Cleaning \(runner.currentFileNumber) of \(runner.counters.supported): \(name)"
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
        .metaBurnGlass(cornerRadius: 8, tint: Color.orange.opacity(0.28))
    }

    private func refreshFireMood() {
        if processing {
            fire.setMood(.burning)
        } else if isDragging {
            fire.setMood(.dragging)
        } else {
            fire.setMood(.idle)
        }
    }

    private func handleDrop(paths: [String], location: CGPoint) {
        dropFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            dropFlash = false
        }
        if paths.isEmpty {
            dropNotice = "No files detected. Drop photos, videos, or a folder."
            fire.burst(at: location, count: 1)
            return
        }
        dropNotice = nil
        fire.burst(at: location, count: paths.count)
        runner.start(droppedPaths: paths, muteAudio: removeAudio)
    }
}

private struct FileDropDelegate: DropDelegate {
    let processing: Bool
    @Binding var isDragging: Bool
    let fire: FireStageController
    let onDrop: ([String], CGPoint) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !processing && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        guard !processing else { return }
        isDragging = true
        fire.setMood(.dragging)
    }

    func dropExited(info: DropInfo) {
        isDragging = false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard !processing else { return false }
        isDragging = false
        let providers = info.itemProviders(for: [.fileURL])
        let location = info.location
        let group = DispatchGroup()
        let lock = NSLock()
        var paths: [String] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, _ in
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
            onDrop(paths, location)
        }
        return true
    }
}

// MARK: - Header

private struct HeaderView: View {
    let typeCounts: TypeCounts
    let processing: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    MetaBurnFireImage()
                        .padding(7)
                        .frame(width: 52, height: 52)
                        .metaBurnGlass(
                            cornerRadius: 14,
                            tint: MetaBurnTheme.accent.opacity(0.22),
                            interactive: false
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        (Text("Meta").foregroundColor(.primary)
                            + Text("Burn").foregroundColor(MetaBurnTheme.accent))
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
                }
                Spacer(minLength: 0)
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
        .metaBurnGlassCapsule(tint: MetaBurnTheme.accent.opacity(0.12))
    }

    private func typeCountText(done: Int, total: Int) -> String {
        processing || done < total ? "\(done)/\(total)" : "\(total)"
    }

    private var typeCountsAccessibilityLabel: String {
        var parts: [String] = []
        if typeCounts.images > 0 {
            parts.append(
                "Photos \(typeCountText(done: typeCounts.imagesDone, total: typeCounts.images))")
        }
        if typeCounts.videos > 0 {
            parts.append(
                "Videos \(typeCountText(done: typeCounts.videosDone, total: typeCounts.videos))")
        }
        if typeCounts.other > 0 {
            parts.append(
                "Other \(typeCountText(done: typeCounts.otherDone, total: typeCounts.other))")
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
            info.copyright,
        ].joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func checkForUpdates() {
        Task { await Updates.checkAndPresentUpdateAlert() }
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
                            .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
                        Text(secondary)
                            .font(.system(size: 11))
                            .foregroundColor(MetaBurnTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 14) {
                    dropGlyph
                    Text(primary)
                        .font(.system(size: 20, weight: .semibold))
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 1)
                    Text(secondary)
                        .font(.system(size: 13))
                        .foregroundColor(MetaBurnTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .metaBurnGlass(
            cornerRadius: compact ? 12 : 16,
            tint: MetaBurnTheme.accent.opacity(highlighted ? 0.22 : 0.04),
            interactive: true,
            clear: true
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                .strokeBorder(
                    MetaBurnTheme.accent.opacity(highlighted ? 0.95 : 0.6),
                    style: StrokeStyle(
                        lineWidth: highlighted ? 2 : 1.5, dash: highlighted ? [] : [6, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
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
                .font(.system(size: compact ? 22 : 46))
                .foregroundStyle(MetaBurnTheme.accent)
        }
    }
}

// MARK: - Cleaned files

private struct CleanedFilesPanel: View {
    let files: [LogEntry]
    let currentFile: String?
    let inFlightCount: Int
    let canReveal: Bool
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cleaned Files")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Show in Finder", systemImage: "folder") { onReveal() }
                    .buttonStyle(GlassGhostButtonStyle())
                    .disabled(!canReveal)
            }
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let currentFile {
                        fileRow(
                            path: currentFile,
                            statusText: inFlightCount > 1
                                ? "cleaning ×\(inFlightCount)" : "cleaning",
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
                            note: file.status == .cleaned ? file.reason : nil,
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
            .metaBurnGlass(cornerRadius: 8, tint: MetaBurnTheme.accent.opacity(0.08))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func fileRow(
        path: String,
        statusText: String,
        note: String? = nil,
        statusColor: Color,
        timestamp: String?,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            FileTypeIcon(path: path)
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .foregroundColor(MetaBurnTheme.secondaryText)
            Text(statusText)
                .font(.system(size: 13))
                .foregroundColor(statusColor)
            // Caveat notes on cleaned files stay muted — never the status color, so
            // a note can't be misread as a failure reason.
            if let note {
                Text("· \(note)")
                    .font(.system(size: 13))
                    .foregroundColor(MetaBurnTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let timestamp {
                Text(timestamp)
                    .font(.system(size: 13))
                    .foregroundColor(MetaBurnTheme.secondaryText)
            }
            if showsProgress {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
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
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 32, height: 32)
            Image(systemName: SupportedTypes.isVideo(filePath: path) ? "play.fill" : "photo.fill")
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
    @Binding var removeAudio: Bool
    let onCancel: () -> Void
    let onOpenFiles: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if processing {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(GlassGhostButtonStyle())
                }
                Button("Open Files") { onOpenFiles() }
                    .buttonStyle(PrimaryButtonStyle())
                    .help("Open MetaBurn's private Photos and Videos workspace")
            }
            .frame(maxWidth: .infinity)

            Toggle(isOn: $removeAudio) {
                HStack(spacing: 8) {
                    Image(systemName: removeAudio ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            removeAudio ? MetaBurnTheme.accent : MetaBurnTheme.secondaryText)
                    Text("Remove audio")
                        .font(.system(size: 13))
                }
            }
            .toggleStyle(RedSwitchToggleStyle())
            .disabled(processing)
            .help("Permanently omit audio tracks from cleaned video copies")
            .accessibilityHint("When enabled, cleaned videos contain no audio tracks")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .metaBurnGlass(
            cornerRadius: 16,
            tint: MetaBurnTheme.accent.opacity(0.16),
            interactive: false
        )
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
                ? "Processing \(max(currentFileNumber, 1)) of \(supported)" : "Processing files…"
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

    static var titlebarTint: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(red: 0.08, green: 0.018, blue: 0.02, alpha: 1)
                }
                return NSColor(red: 0.32, green: 0.12, blue: 0.10, alpha: 1)
            })
    }

    static var background: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(red: 0.026, green: 0.010, blue: 0.012, alpha: 1)
                }
                return NSColor(red: 0.94, green: 0.90, blue: 0.85, alpha: 1)
            })
    }

    static var surface: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(red: 0.12, green: 0.04, blue: 0.04, alpha: 0.42)
                }
                return NSColor(red: 1, green: 1, blue: 1, alpha: 0.42)
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
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                toggleTrack(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toggleTrack(isOn: Bool) -> some View {
        let knob = Circle()
            .fill(Color.white)
            .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1)
            .padding(2.5)
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(isOn ? MetaBurnTheme.accent.opacity(0.55) : Color.white.opacity(0.12))
                .frame(width: 40, height: 22)
                .glassEffect(
                    .regular.tint(isOn ? MetaBurnTheme.accent : nil).interactive(),
                    in: Capsule()
                )
                .overlay(knob, alignment: isOn ? .trailing : .leading)
        } else {
            Capsule()
                .fill(isOn ? MetaBurnTheme.accent : Color(red: 0.55, green: 0.15, blue: 0.15))
                .frame(width: 40, height: 22)
                .overlay(knob, alignment: isOn ? .trailing : .leading)
        }
    }
}
