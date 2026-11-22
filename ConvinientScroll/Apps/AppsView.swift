import AppKit
import SwiftUI

struct AppsView: View {
    @ObservedObject var model: AppsModel
    let controller: AppsController
    @State private var lastConfirmation: [LeftoverItem] = []

    var body: some View {
        NavigationSplitView {
            AppsSidebar(model: model, controller: controller)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } content: {
            AppsListColumn(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            AppsDetail(model: model, controller: controller)
        }
        .searchable(text: $model.query, placement: .toolbar)
        .task(id: model.section) {
            if model.selectedID == nil, let first = model.rows.first?.id {
                await model.select(first)
            }
            await model.loadSizes()
        }
        .onChange(of: model.pendingRemoval) { _, items in
            if let items { lastConfirmation = items }
        }
        .alert(confirmationTitle(model.pendingRemoval ?? lastConfirmation), isPresented: isConfirming, presenting: model.pendingRemoval) { items in
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task {
                    model.pendingRemoval = items
                    await model.confirmRemoval()
                }
            }
        } message: { items in
            Text(confirmationMessage(items))
        }
        .frame(minWidth: 820, minHeight: 480)
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { model.pendingRemoval != nil },
            set: { if !$0 { model.pendingRemoval = nil } })
    }

    private func confirmationTitle(_ items: [LeftoverItem]) -> String {
        if model.section == .installed {
            let name = controller.app(in: .installed, id: model.selectedID)?.name ?? ""
            return "Clean caches and logs of \(name)?"
        }
        return "Move \(counted(items.count, "item")) (\(formatted(totalSize(items)))) to the Trash?"
    }

    private func confirmationMessage(_ items: [LeftoverItem]) -> String {
        let paths = items.map { ($0.entry.url.path as NSString).abbreviatingWithTildeInPath }
        var notes: [String] = []
        let admin = items.filter(\.needsAdmin).count
        if admin > 0 {
            notes.append(admin == 1 ? "1 item needs an administrator password" : "\(admin) items need an administrator password")
        }
        let services = items.filter { $0.kind == .service }.count
        if services > 0 {
            notes.append(services == 1
                ? "1 background service will be stopped first"
                : "\(services) background services will be stopped first")
        }
        notes.append("You can put items back from the Trash.")
        return paths.joined(separator: "\n") + "\n\n" + notes.joined(separator: "\n")
    }
}

private struct AppsSidebar: View {
    @ObservedObject var model: AppsModel
    let controller: AppsController

    var body: some View {
        List(selection: Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })) {
            Label("Installed", systemImage: "square.grid.2x2")
                .badge(controller.installed.count)
                .tag(AppsSection.installed)
            Label("Removed", systemImage: "trash")
                .badge(controller.removed.count)
                .tag(AppsSection.removed)
            Label("Orphans", systemImage: "questionmark.folder")
                .badge(model.orphans?.count ?? 0)
                .tag(AppsSection.orphans)
        }
    }
}

private struct AppsListColumn: View {
    @ObservedObject var model: AppsModel

    var body: some View {
        let rows = model.rows
        VStack(spacing: 0) {
            HStack {
                Text(counted(rows.count, model.section == .installed ? "app" : "item"))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.section == .orphans, model.orphans != nil {
                    Button("Rescan") { scanOrphans(model) }
                        .disabled(model.isScanning)
                }
                Picker("Sort", selection: $model.sort) {
                    Text("Name").tag(AppsSort.name)
                    Text("Size").tag(AppsSort.size)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            List(rows, selection: Binding(get: { model.selectedID }, set: { id in Task { await model.select(id) } })) { row in
                AppsRowView(row: row, section: model.section)
            }
            .overlay {
                if rows.isEmpty {
                    Text(model.section == .orphans && model.orphans == nil ? "Not scanned yet." : "Empty")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AppsRowView: View {
    let row: AppsRow
    let section: AppsSection

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(path: section == .installed ? row.id : nil, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).lineLimit(1)
                if row.subtitle != row.title {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(row.size.map(formatted) ?? "…")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppIcon: View {
    let path: String?
    let size: CGFloat

    var body: some View {
        if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "questionmark.app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

private struct AppsDetail: View {
    @ObservedObject var model: AppsModel
    let controller: AppsController

    var body: some View {
        VStack(spacing: 0) {
            if model.section == .orphans, model.orphans == nil {
                scanPrompt
            } else if let id = model.selectedID, hasEntry(id) {
                header(id)
                AppsBanners(model: model)
                AppsFileList(model: model, appPath: model.section == .installed ? id : nil)
                reportLine
                Divider()
                AppsBottomBar(model: model, app: controller.app(in: model.section, id: id), controller: controller)
            } else {
                emptyState
                reportLine
            }
        }
    }

    private func hasEntry(_ id: String) -> Bool {
        switch model.section {
        case .installed, .removed: controller.app(in: model.section, id: id) != nil
        case .orphans: model.orphans?.contains { $0.id == id } ?? false
        }
    }

    @ViewBuilder
    private func header(_ id: String) -> some View {
        switch model.section {
        case .installed:
            if let app = controller.app(in: .installed, id: id) {
                let details = [app.bundleID, app.version.map { "Version \($0)" }, app.folder,
                               controller.isRunning(app) ? "Running" : nil].compactMap { $0 }
                AppsHeader(iconPath: app.path, title: app.name, details: details)
            }
        case .removed:
            if let entry = controller.removed.first(where: { $0.id == id }) {
                let when = RelativeDateTimeFormatter().localizedString(for: entry.removedAt, relativeTo: Date())
                AppsHeader(iconPath: nil, title: entry.app.name, details: [entry.id, "Removed \(when) from \(entry.app.folder)"])
            }
        case .orphans:
            AppsHeader(iconPath: nil, title: id, details: ["No installed app uses this bundle id"])
        }
    }

    @ViewBuilder
    private var scanPrompt: some View {
        if model.isScanning {
            ContentUnavailableView {
                Text("Scanning Library…")
            } description: {
                Text(verbatim: "Comparing bundle ids in ~/Library and /Library with installed apps and their helpers.")
            } actions: {
                ProgressView().controlSize(.small)
            }
        } else {
            ContentUnavailableView {
                Text("Find leftovers of old apps")
            } description: {
                Text(verbatim: "Looks for files in ~/Library and /Library whose bundle id belongs to no installed app. Apple files and helpers of installed apps are skipped.")
            } actions: {
                Button("Scan") { scanOrphans(model) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.section == .removed, controller.removed.isEmpty {
            ContentUnavailableView {
                Text("No leftovers from removed apps")
            } description: {
                Text("When you move an app from Applications to the Trash, Mac Toolkit checks what it left behind and lists it here.")
            }
        } else if model.section == .orphans, model.orphans?.isEmpty == true {
            ContentUnavailableView {
                Text("Nothing left to clean")
            } description: {
                Text("No files without an installed app were found.")
            } actions: {
                Button("Scan Again") { scanOrphans(model) }
                    .disabled(model.isScanning)
            }
        } else {
            ContentUnavailableView { Text("Select an app") }
        }
    }

    @ViewBuilder
    private var reportLine: some View {
        if let report = model.lastReport {
            Text(reportText(report))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private func reportText(_ report: RemovalReport) -> String {
        let moved = counted(report.removed.count, "item")
        return report.adminCancelled
            ? "Moved \(moved) to the Trash. Items in /Library were left in place."
            : "Moved \(moved) (\(formatted(report.bytes))) to the Trash"
    }
}

private struct AppsHeader: View {
    let iconPath: String?
    let title: String
    let details: [String]

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(path: iconPath, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold)).lineLimit(1)
                Text(details.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct AppsBanners: View {
    @ObservedObject var model: AppsModel

    var body: some View {
        if model.items.contains(where: { !$0.isAccessible }) {
            GroupBox {
                HStack {
                    Label("Containers of other apps are protected. Allow Full Disk Access to see and remove them.", systemImage: "lock")
                    Spacer()
                    Button("Open System Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        if model.section != .installed, model.items.contains(where: { $0.match == .name }) {
            GroupBox {
                Label("Items matched by name are not selected. Check them before moving to the Trash.", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

private struct AppsFileList: View {
    @ObservedObject var model: AppsModel
    let appPath: String?

    var body: some View {
        List {
            if let appPath {
                Section("Application") {
                    FileRow(name: (appPath as NSString).lastPathComponent,
                            folder: (appPath as NSString).deletingLastPathComponent,
                            url: URL(filePath: appPath), tags: [], showsLock: false, size: nil, isAccessible: true, checked: nil)
                }
            }
            ForEach([LibraryDomain.user, .system], id: \.self) { domain in
                let group = model.items.filter { $0.entry.domain == domain }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { item in row(item) }
                    } header: {
                        HStack {
                            Text(verbatim: domain == .user ? "Your Library · ~/Library" : "System Library · /Library")
                            Spacer()
                            Text(formatted(totalSize(group))).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: LeftoverItem) -> FileRow {
        let tags = (item.needsAdmin ? ["Admin"] : []) + [item.kind.title, item.match.title]
        let size = item.size.map(formatted) ?? (item.isAccessible ? "…" : "No access")
        let checked = model.section == .installed ? nil : Binding(
            get: { model.checked.contains(item.id) },
            set: { isOn in
                if isOn { model.checked.insert(item.id) } else { model.checked.remove(item.id) }
            })
        return FileRow(
            name: item.entry.name, folder: item.entry.url.deletingLastPathComponent().path,
            url: item.entry.url, tags: tags, showsLock: item.needsAdmin, size: size,
            isAccessible: item.isAccessible, checked: checked)
    }
}

private struct FileRow: View {
    let name: String
    let folder: String
    let url: URL
    let tags: [String]
    let showsLock: Bool
    let size: String?
    let isAccessible: Bool
    let checked: Binding<Bool>?

    var body: some View {
        HStack(spacing: 8) {
            if let checked {
                Toggle("Select", isOn: checked)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!isAccessible)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1).truncationMode(.middle)
                Text((folder as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !tags.isEmpty {
                HStack(spacing: 3) {
                    if showsLock { Image(systemName: "lock.fill") }
                    Text(tags.joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let size {
                Text(size)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show in Finder", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .foregroundStyle(isAccessible ? .primary : .secondary)
    }
}

private struct AppsBottomBar: View {
    @ObservedObject var model: AppsModel
    let app: InstalledApp?
    let controller: AppsController

    var body: some View {
        HStack(spacing: 10) {
            if model.section == .installed {
                installedBar
            } else {
                leftoversBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var installedBar: some View {
        let cleanable = model.cleanableItems()
        let isRunning = app.map(controller.isRunning) ?? false
        Text("Files outside the app: \(formatted(totalSize(model.items))). Settings and data of installed apps are view-only.")
            .foregroundStyle(.secondary)
        Spacer()
        if isRunning, let app {
            Text("Quit \(app.name) to clean its caches").foregroundStyle(.secondary)
        }
        Button(isRunning || cleanable.isEmpty
               ? "Clean Caches & Logs"
               : "Clean Caches & Logs (\(formatted(totalSize(cleanable))))") {
            model.askToClean()
        }
        .disabled(!model.canClean || model.isRemoving)
    }

    @ViewBuilder
    private var leftoversBar: some View {
        let chosen = model.items.filter { model.checked.contains($0.id) && $0.isAccessible }
        Text("\(chosen.count) of \(model.items.count) selected · \(formatted(totalSize(chosen)))")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        Spacer()
        if model.section == .removed {
            Button("Keep Files") { model.keepSelected() }
                .disabled(model.isRemoving)
        } else {
            Button("Hide Forever") { model.hideSelected() }
                .disabled(model.isRemoving)
        }
        Button("Move to Trash") { model.askToTrashChecked() }
            .disabled(chosen.isEmpty || model.isRemoving)
    }
}

private func scanOrphans(_ model: AppsModel) {
    Task {
        await model.scanOrphans()
        guard model.section == .orphans else { return }
        let rows = model.rows
        let kept = rows.first { $0.id == model.selectedID }?.id
        await model.select(kept ?? rows.first?.id)
        await model.loadSizes()
    }
}

private func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func totalSize(_ items: [LeftoverItem]) -> Int64 {
    items.compactMap(\.size).reduce(0, +)
}

private func counted(_ count: Int, _ noun: String) -> String {
    count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
}

private extension AppsController {
    func app(in section: AppsSection, id: String?) -> InstalledApp? {
        guard let id else { return nil }
        switch section {
        case .installed: return installed.first { $0.path == id }
        case .removed: return removed.first { $0.id == id }?.app
        case .orphans: return nil
        }
    }
}

private extension LeftoverKind {
    var title: String {
        switch self {
        case .settings: "Settings"
        case .cache: "Cache"
        case .log: "Log"
        case .windowState: "Window state"
        case .service: "Background service"
        case .data: "Data"
        }
    }
}

private extension MatchKind {
    var title: String {
        switch self {
        case .bundleID: "Bundle ID"
        case .teamID: "Team ID"
        case .name: "By name"
        }
    }
}
