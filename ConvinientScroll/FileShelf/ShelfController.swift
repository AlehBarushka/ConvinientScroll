import AppKit
import Combine
import OSLog

/// Runs the shelf module: one panel per display, plus a mouse monitor that is active
/// only while a drag is in progress, so files approaching the zone can be noticed.
@MainActor
final class ShelfController {
    let store: ShelfStore
    private var panels: [ShelfPanelController] = []
    private var isEnabled = false
    private(set) var isDraggingOut = false

    private var screenObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var itemsCancellable: AnyCancellable?
    private var cachePurgeWork: DispatchWorkItem?

    /// Drag pasteboard state at the last mouse-down; a file drag changes it.
    private var dragChangeCountAtMouseDown = 0
    private var currentDragIsFile: Bool?

    private static let cacheRetention: TimeInterval = 30

    init(store: ShelfStore) {
        self.store = store
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    /// Opens the shelf on the display under the pointer until the pointer leaves it
    /// or the user clicks elsewhere.
    func showShelf() {
        guard isEnabled else { return }
        let location = NSEvent.mouseLocation
        let panel = panels.first { $0.geometry.screenFrame.contains(location) } ?? panels.first
        panel?.expand(pinned: true)
    }

    // MARK: Lifecycle

    private func start() {
        rebuildPanels()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        }
        itemsCancellable = store.$items
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // `$items` fires before the value is stored.
                DispatchQueue.main.async { self?.panels.forEach { $0.itemsChanged() } }
            }
        // Global monitors see other apps' events only; mouse events need no permission.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobalMouse(event) }
        }
        AppLog.shelf.info("Shelf started on \(self.panels.count) display(s)")
    }

    private func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        itemsCancellable = nil
        panels.forEach { $0.close() }
        panels.removeAll()
        ThumbnailCache.shared.removeAll()
    }

    private func rebuildPanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { screen in
            ShelfPanelController(screen: screen, store: store, owner: self, actions: makeActions())
        }
    }

    private func makeActions() -> ShelfActions {
        let store = store
        return ShelfActions(
            url: { store.url(for: $0) },
            remove: { store.remove($0) },
            clear: { store.removeAll() },
            dragOutBegan: { [weak self] in self?.isDraggingOut = true },
            dragOutEnded: { [weak self] accepted in
                self?.isDraggingOut = false
                self?.panels.forEach { $0.interactionEnded(holdOpen: !accepted) }
            }
        )
    }

    // MARK: Drags from other apps

    private func handleGlobalMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            currentDragIsFile = nil
            panels.forEach { $0.clickedElsewhere() }
        case .leftMouseDragged:
            guard isFileDrag() else { return }
            let location = NSEvent.mouseLocation
            for panel in panels {
                panel.fileDragMoved(closeness: panel.geometry.closeness(of: location))
            }
        case .leftMouseUp:
            if currentDragIsFile == true { panels.forEach { $0.fileDragFinished() } }
            currentDragIsFile = nil
        default:
            break
        }
    }

    /// Decided once per drag: the drag pasteboard changes when a drag session starts,
    /// so an unchanged count means a selection or a window move, not a file.
    private func isFileDrag() -> Bool {
        if let currentDragIsFile { return currentDragIsFile }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCountAtMouseDown else { return false }
        let isFile = pasteboard.types?.contains(.fileURL) == true
        currentDragIsFile = isFile
        if isFile { AppLog.shelf.debug("A file drag started; showing the drop targets") }
        return isFile
    }

    // MARK: Memory

    /// Thumbnails are dropped a while after every shelf has collapsed.
    func panelReleasedContent() {
        cachePurgeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panels.contains(where: \.isExpanded) else { return }
            ThumbnailCache.shared.removeAll()
        }
        cachePurgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cacheRetention, execute: work)
    }
}
