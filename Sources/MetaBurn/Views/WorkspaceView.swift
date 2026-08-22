import AppKit
import MetaBurnCore
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var photos: [URL] = []
    @Published private(set) var videos: [URL] = []

    init() {
        refresh()
    }

    func refresh() {
        Paths.ensureWorkspaceDirectories()
        photos = files(in: Paths.workspacePhotosDirectory())
        videos = files(in: Paths.workspaceVideosDirectory())
    }

    private func files(in directory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

enum WorkspaceCategory: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case videos = "Videos"

    var id: String { rawValue }
    var icon: String { self == .photos ? "photo.on.rectangle.angled" : "film.stack" }
}

struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    let onClose: () -> Void
    @State private var category: WorkspaceCategory?
    @State private var selection: Set<URL> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MetaBurnTheme.hairline)
            if let category {
                fileBrowser(category)
            } else {
                folderBrowser
            }
        }
        .background(MetaBurnTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
        )
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if category != nil {
                Button {
                    category = nil
                    selection.removeAll()
                } label: {
                    Label("Open Files", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
            } else {
                Text("Open Files")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(MetaBurnTheme.secondaryText)
            }
            Button("Back to Results") { onClose() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var folderBrowser: some View {
        HStack(spacing: 18) {
            folderCard(.photos, count: store.photos.count)
            folderCard(.videos, count: store.videos.count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func folderCard(_ folder: WorkspaceCategory, count: Int) -> some View {
        Button {
            category = folder
            selection.removeAll()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: folder.icon)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(MetaBurnTheme.accent)
                Text(folder.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                Text("\(count) \(count == 1 ? "file" : "files")")
                    .font(.system(size: 12))
                    .foregroundStyle(MetaBurnTheme.secondaryText)
            }
            .frame(width: 210, height: 130)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.rawValue), \(count) files")
        .accessibilityHint("Open the cleaned \(folder.rawValue.lowercased()) workspace")
    }

    private func fileBrowser(_ folder: WorkspaceCategory) -> some View {
        let urls = folder == .photos ? store.photos : store.videos
        return Group {
            if urls.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: folder.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(MetaBurnTheme.secondaryText)
                    Text("No cleaned \(folder.rawValue.lowercased()) yet")
                        .font(.system(size: 14, weight: .medium))
                    Text("Drop files into MetaBurn to add verified clean copies.")
                        .font(.system(size: 12))
                        .foregroundStyle(MetaBurnTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WorkspaceFileTable(urls: urls, selection: $selection)
                    .accessibilityLabel("Cleaned \(folder.rawValue.lowercased())")
            }
        }
    }
}

private struct WorkspaceFileTable: NSViewRepresentable {
    let urls: [URL]
    @Binding var selection: Set<URL>

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = WorkspaceTableView()
        table.headerView = nil
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.backgroundColor = .clear
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = .separatorColor
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openSelection(_:))
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let table = scrollView.documentView as? WorkspaceTableView else { return }
        context.coordinator.urls = urls
        table.fileURLs = urls
        table.reloadData()
        let indexes = IndexSet(urls.indices.filter { selection.contains(urls[$0]) })
        table.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var urls: [URL] = []
        weak var table: NSTableView?
        private var selection: Binding<Set<URL>>

        init(selection: Binding<Set<URL>>) {
            self.selection = selection
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            urls.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("WorkspaceFileCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.imageScaling = .scaleProportionallyDown
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.lineBreakMode = .byTruncatingMiddle
                cell.imageView = icon
                cell.textField = label
                cell.addSubview(icon)
                cell.addSubview(label)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 24),
                    icon.heightAnchor.constraint(equalToConstant: 24),
                    label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            let url = urls[row]
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: url.path)
            cell.textField?.stringValue = url.lastPathComponent
            cell.toolTip = url.path
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table else { return }
            selection.wrappedValue = Set(table.selectedRowIndexes.compactMap { index in
                urls.indices.contains(index) ? urls[index] : nil
            })
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard urls.indices.contains(row), isExportable(urls[row]) else { return nil }
            return urls[row] as NSURL
        }

        private func isExportable(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
                && PathSafety.isPhysicallyInside(url.path, ancestor: Paths.workspaceDirectory().path)
        }

        @objc func openSelection(_ sender: Any?) {
            guard let table else { return }
            let selected = table.selectedRowIndexes.compactMap { index in
                urls.indices.contains(index) && isExportable(urls[index]) ? urls[index] : nil
            }
            if selected.count == 1, let url = selected.first {
                NSWorkspace.shared.open(url)
            } else if !selected.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(selected)
            }
        }
    }
}

private final class WorkspaceTableView: NSTableView {
    var fileURLs: [URL] = []

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "a" {
            selectAll(nil)
            return true
        }
        if key == "c" {
            copySelectedFiles()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func copy(_ sender: Any?) {
        copySelectedFiles()
    }

    private func copySelectedFiles() {
        let urls = selectedRowIndexes.compactMap { index -> URL? in
            guard fileURLs.indices.contains(index) else { return nil }
            let url = fileURLs[index]
            guard FileManager.default.fileExists(atPath: url.path),
                  PathSafety.isPhysicallyInside(url.path, ancestor: Paths.workspaceDirectory().path) else {
                return nil
            }
            return url
        }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }
}
