import AppKit
import SwiftUI

struct ShelfDragFile {
    let url: URL
    let image: NSImage?
}

/// Lets a card (or the "drag all" handle) be dragged out of the shelf as file URLs.
/// AppKit is used instead of `onDrag` so that several files can travel in one drag.
struct ShelfDragSource: NSViewRepresentable {
    /// Asked when a drag starts, because the selection decides what travels.
    let files: () -> [ShelfDragFile]
    var onBegin: () -> Void = {}
    /// Reports whether a destination took the files.
    var onEnd: (Bool) -> Void = { _ in }
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onOpen: (() -> Void)?

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: DragSourceView) {
        view.files = files
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.onClick = onClick
        view.onOpen = onOpen
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var files: () -> [ShelfDragFile] = { [] }
        var onBegin: () -> Void = {}
        var onEnd: (Bool) -> Void = { _ in }
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onOpen: (() -> Void)?
        private var mouseDownEvent: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            if event.clickCount == 2 { onOpen?() }
        }

        // A click acts on release: acting on press would reduce a group to one card
        // before it could be dragged.
        override func mouseUp(with event: NSEvent) {
            guard let down = mouseDownEvent else { return }
            mouseDownEvent = nil
            onClick?(down.modifierFlags)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy > 9 else { return }
            mouseDownEvent = nil

            let files = files()
            guard !files.isEmpty else { return }
            let side = min(bounds.width, bounds.height, 64)
            let items = files.enumerated().map { index, file -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: file.url as NSURL)
                // Stack several files slightly so the drag shows how many there are.
                let offset = CGFloat(min(index, 3)) * 4
                let frame = CGRect(x: (bounds.width - side) / 2 + offset, y: (bounds.height - side) / 2 - offset,
                                   width: side, height: side)
                let icon = index < 4 ? file.image ?? NSWorkspace.shared.icon(forFile: file.url.path) : nil
                item.setDraggingFrame(frame, contents: icon)
                return item
            }
            onBegin()
            let session = beginDraggingSession(with: items, event: down, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            session.draggingFormation = .pile
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Out of the app the files are copied; inside it (onto the shelf) nothing happens.
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            onEnd(operation != [])
        }
    }
}

/// Sits behind the cards, so it only receives clicks that land between them.
struct ShelfEmptySpaceClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ClickView {
        ClickView()
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
    }

    final class ClickView: NSView {
        var action: () -> Void = {}

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            action()
        }
    }
}
