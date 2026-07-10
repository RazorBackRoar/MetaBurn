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

    var body: some View {
        Group {
            if exiftoolReady == false {
                missingExiftoolView
            } else {
                mainView
            }
        }
        .onAppear {
            Task { await checkExiftool() }
        }
    }

    // MARK: - Missing ExifTool

    private var missingExiftoolView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("ExifTool is required")
                .font(.title2)
            Text("Install it with: brew install exiftool")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                if canInstallExiftool {
                    Button(installingExiftool ? "Installing…" : "Install ExifTool") {
                        Task { await installExiftool() }
                    }
                    .disabled(installingExiftool)
                }
                Button("Re-check") {
                    Task { await checkExiftool() }
                }
                .disabled(installingExiftool)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Main View

    private var mainView: some View {
        VStack(spacing: 12) {
            toolbar
            dropZone
            if let notice = dropNotice {
                noticeBanner(notice, color: .orange)
            }
            muteSwitch
            if muteAudio, ffmpegReady == false {
                ffmpegNotice
            }
            statusBar
            if runner.state == .done || runner.state == .failed || runner.state == .cancelled {
                resultBanner
            }
            if runner.log.count > 1 {
                fileChips
            }
            metadataPanel
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(minWidth: 520, minHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            return handleDrop(providers: providers)
        }
        .onAppear { Task { await checkFfmpeg() } }
    }

    private var toolbar: some View {
        HStack {
            Spacer()
            Text("MetaBurn")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.red)
                .onTapGesture(count: 2) { showAbout() }
                .contextMenu {
                    Button("Check for Updates…") { checkForUpdates() }
                }
            Spacer()
            if processing {
                Button("Cancel") { runner.cancel() }
            } else {
                Button("Clear Log") { clearLog() }
                    .disabled(runner.log.isEmpty)
            }
        }
        .padding(.vertical, 10)
    }

    private var dropZone: some View {
        Button {
            browseFiles()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: processing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(processing ? "Processing…" : "Drop photos, videos, or folders here")
                    .font(.system(size: 14, weight: .semibold))
                Text(processing ? "Cleaning metadata in place…" : "or click to browse — removed in place, no copies")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(isDragging ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDragging ? Color.accentColor : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(processing || exiftoolReady != true)
    }

    private var muteSwitch: some View {
        HStack(spacing: 12) {
            Image(systemName: "volume.slash")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mute Video")
                    .font(.system(size: 13, weight: .semibold))
                Text("Permanently remove audio from videos before cleaning.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $muteAudio)
                .toggleStyle(.switch)
                .disabled(processing)
                .onChange(of: muteAudio) { Task { await checkFfmpeg() } }
        }
        .padding(10)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(8)
    }

    private var ffmpegNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text("ffmpeg is required to mute audio.")
                .font(.system(size: 12))
            if canInstallFfmpeg {
                Button(installingFfmpeg ? "Installing…" : "Install ffmpeg") {
                    Task { await installFfmpeg() }
                }
                .disabled(installingFfmpeg)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                statusDot
                Text(stateLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            HStack(spacing: 16) {
                counter("Found", value: runner.counters.supported, color: .secondary)
                counter("Cleaned", value: runner.counters.cleaned, color: .green)
                counter("Skipped", value: runner.counters.skipped, color: .secondary)
                counter("Partial", value: runner.counters.partial, color: .orange)
                counter("Failed", value: runner.counters.failed, color: .red)
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

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
        case .waiting: "Waiting for files"
        case .scanning: "Scanning"
        case .cleaning: "Cleaning"
        case .done: "Done"
        case .failed: runner.message ?? "Failed"
        case .cancelled: "Cancelled"
        case .exiftoolMissing: "ExifTool missing"
        }
    }

    private var resultBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: runner.state == .done ? "checkmark.circle" : runner.state == .failed ? "xmark.circle" : "slash.circle")
            Text("\(runner.state.rawValue.capitalized) — \(summarizeCounters())")
            Spacer()
        }
        .padding(10)
        .background(bannerColor.opacity(0.12))
        .foregroundColor(bannerColor)
        .cornerRadius(8)
    }

    private var bannerColor: Color {
        switch runner.state {
        case .done: .green
        case .failed: .red
        default: .secondary
        }
    }

    private var fileChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(runner.log) { entry in
                    FileChip(entry: entry, isSelected: selectedEntry?.id == entry.id) {
                        selectedEntry = entry
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var metadataPanel: some View {
        ZStack {
            if let entry = selectedEntry ?? runner.log.first {
                MetadataReport(entry: entry)
            } else {
                Text("Drop a photo, video, or folder to see its before-and-after metadata.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func noticeBanner(_ message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.08))
        .foregroundColor(color)
        .cornerRadius(8)
    }

    private func counter(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard exiftoolReady == true, !processing else { return false }
        let group = DispatchGroup()
        var paths: [String] = []
        var loaded = 0
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
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
                dropNotice = loaded > 0 ? "Couldn't read those items' file paths. Click the drop area to browse and pick them instead." : "No files were detected in that drop. Try photos, videos, or a folder — or click to browse."
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
            startJob(paths: panel.urls.map { $0.path })
        }
    }

    private func startJob(paths: [String]) {
        selectedEntry = nil
        runner.start(droppedPaths: paths, muteAudio: muteAudio)
    }

    private func clearLog() {
        runner.cancel()
        selectedEntry = nil
    }

    private func checkExiftool() async {
        if let path = await MetadataCleaner.resolveExiftool() {
            exiftoolReady = true
            canInstallExiftool = false
            _ = path
        } else {
            exiftoolReady = false
            canInstallExiftool = await MetadataCleaner.resolveBrew() != nil
        }
    }

    private func checkFfmpeg() async {
        if let path = await MetadataCleaner.resolveFfmpeg() {
            ffmpegReady = true
            canInstallFfmpeg = false
            _ = path
        } else {
            ffmpegReady = false
            canInstallFfmpeg = await MetadataCleaner.resolveBrew() != nil
        }
    }

    private func installExiftool() async {
        installingExiftool = true
        let result = await MetadataCleaner.installExiftool()
        if result.success {
            await checkExiftool()
        }
        installingExiftool = false
    }

    private func installFfmpeg() async {
        installingFfmpeg = true
        let result = await MetadataCleaner.installFfmpeg()
        if result.success {
            await checkFfmpeg()
        }
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

    private func summarizeCounters() -> String {
        var parts = ["\(runner.counters.cleaned) files cleaned"]
        if runner.counters.skipped > 0 { parts.append("\(runner.counters.skipped) skipped") }
        if runner.counters.partial > 0 { parts.append("\(runner.counters.partial) partial") }
        if runner.counters.failed > 0 { parts.append("\(runner.counters.failed) failed") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - File Chip

struct FileChip: View {
    let entry: LogEntry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(entry.status.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
                Text(URL(fileURLWithPath: entry.path).lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch entry.status {
        case .cleaned: .green
        case .partial: .orange
        case .skipped: .gray
        case .failed: .red
        }
    }
}
