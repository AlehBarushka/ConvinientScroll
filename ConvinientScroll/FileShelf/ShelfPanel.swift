import AppKit
import SwiftUI

/// A borderless, non-activating window above the menu bar, on every Space and over
/// full-screen apps. It never takes focus away from the app you are working in.
final class ShelfPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI shelf and handles what SwiftUI does not cover well in a
/// background panel: file drops, hover tracking and first-click buttons.
final class ShelfHostingView: NSHostingView<ShelfRootView> {
    weak var controller: ShelfPanelController?
    private var hoverArea: NSTrackingArea?

    required init(rootView: ShelfRootView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverArea = area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea == hoverArea { controller?.pointerEntered() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea == hoverArea { controller?.pointerExited() }
    }

    // MARK: Drop destination

    private func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    private func accepts(_ info: NSDraggingInfo) -> Bool {
        // A card dragged out of the shelf comes from this app; dropping it back does nothing.
        info.draggingSource == nil && info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        controller?.fileDragEntered()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.fileDragExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        accepts(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        controller?.filesDropped(urls)
        return true
    }
}

/// One display's shelf: decides its state, sizes the window to it, and reacts to
/// hover, drops and drags. Timers here are one-shot and exist only around interaction.
@MainActor
final class ShelfPanelController {
    let model: ShelfPanelModel
    private let panel: ShelfPanel
    private let hostingView: ShelfHostingView
    private let store: ShelfStore
    private unowned let owner: ShelfController

    private var isPointerInside = false
    private var isPinned = false
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var releaseWork: DispatchWorkItem?

    private static let hoverDelay: TimeInterval = 0.3
    private static let collapseDelay: TimeInterval = 0.4
    private static let shrinkDelay: TimeInterval = 0.5
    private static let releaseDelay: TimeInterval = 2

    var geometry: ShelfGeometry { model.geometry }
    var isExpanded: Bool { model.mode == .expanded }

    init(screen: NSScreen, store: ShelfStore, owner: ShelfController, actions: ShelfActions) {
        self.store = store
        self.owner = owner
        model = ShelfPanelModel(geometry: ShelfGeometry(screen: screen))
        model.mode = Self.restingMode(for: store)

        hostingView = ShelfHostingView(rootView: ShelfRootView(model: model, store: store, actions: actions))
        hostingView.sizingOptions = []
        panel = ShelfPanel(frame: model.geometry.panelFrame(for: model.mode))
        panel.contentView = hostingView
        hostingView.controller = self
        panel.orderFrontRegardless()
    }

    func close() {
        [expandWork, collapseWork, shrinkWork, releaseWork].forEach { $0?.cancel() }
        hostingView.controller = nil
        panel.orderOut(nil)
        panel.close()
    }

    private static func restingMode(for store: ShelfStore) -> ShelfGeometry.Mode {
        store.items.isEmpty ? .hidden : .indicator
    }

    private var restingMode: ShelfGeometry.Mode { Self.restingMode(for: store) }

    /// The shelf gained or lost its last file.
    func itemsChanged() {
        switch model.mode {
        case .hidden, .indicator: apply(restingMode)
        case .peek, .expanded: break
        }
    }

    // MARK: Expanding and collapsing

    func expand(pinned: Bool = false) {
        expandWork?.cancel()
        collapseWork?.cancel()
        if pinned { isPinned = true }
        apply(.expanded)
    }

    func collapse() {
        isPinned = false
        expandWork?.cancel()
        collapseWork?.cancel()
        apply(restingMode)
    }

    /// Collapses once nothing holds the shelf open any more.
    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapseIfIdle() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
    }

    private func collapseIfIdle() {
        guard isExpanded else { return }
        let pointerInside = panel.frame.contains(NSEvent.mouseLocation)
        if isPinned || pointerInside || model.isDropTargeted || owner.isDraggingOut { return }
        collapse()
    }

    /// The pointer left after an interaction that did not track it (a drop, a drag out).
    func interactionEnded() {
        if !panel.frame.contains(NSEvent.mouseLocation) { scheduleCollapse() }
    }

    func clickedElsewhere() {
        guard isPinned else { return }
        isPinned = false
        scheduleCollapse()
    }

    private func apply(_ mode: ShelfGeometry.Mode) {
        guard mode != model.mode else { return }
        let target = geometry.panelFrame(for: mode)
        let current = panel.frame
        shrinkWork?.cancel()

        // Grow the window first so the shape can animate inside it; shrink only after
        // the animation, so the window never clips it.
        if target.width >= current.width, target.height >= current.height {
            panel.setFrame(target, display: false)
            // Re-centre the current shape in the larger window before the state changes;
            // otherwise both land in one animated update and the shape grows out of the
            // window's old corner instead of from the centre.
            hostingView.layoutSubtreeIfNeeded()
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.model.mode == mode else { return }
                self.panel.setFrame(self.geometry.panelFrame(for: mode), display: false)
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
        }

        if mode == .expanded {
            releaseWork?.cancel()
            model.showsContent = true
            store.refreshAvailability()
        } else if model.mode == .expanded {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isExpanded else { return }
                self.model.showsContent = false
                self.owner.panelReleasedContent()
            }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay, execute: work)
        }
        model.mode = mode
    }

    // MARK: Hover

    func pointerEntered() {
        isPointerInside = true
        collapseWork?.cancel()
        guard !isExpanded, !store.items.isEmpty else { return }
        expandWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPointerInside else { return }
            self.apply(.expanded)
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
    }

    func pointerExited() {
        isPointerInside = false
        expandWork?.cancel()
        // Leaving a shelf opened from the menu unpins it.
        isPinned = false
        if isExpanded { scheduleCollapse() }
    }

    // MARK: Files dragged toward the shelf

    /// While a file is being dragged anywhere, every display shows where it can be
    /// dropped; the target grows as the file gets closer.
    func fileDragMoved(closeness: Double) {
        guard !isExpanded else { return }
        // Coarse steps keep the shape from re-rendering on every mouse event.
        let step = (closeness * 20).rounded() / 20
        apply(.peek(step))
    }

    func fileDragFinished() {
        if case .peek = model.mode { apply(restingMode) }
    }

    func fileDragEntered() {
        collapseWork?.cancel()
        expandWork?.cancel()
        if !isExpanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        model.isDropTargeted = true
        apply(.expanded)
    }

    func fileDragExited() {
        model.isDropTargeted = false
        scheduleCollapse()
    }

    func filesDropped(_ urls: [URL]) {
        model.isDropTargeted = false
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        Task {
            await store.add(urls)
            interactionEnded()
        }
    }
}
