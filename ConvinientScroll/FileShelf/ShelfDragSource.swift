import AppKit
import SwiftUI

/// Lets a card (or the "drag all" handle) be dragged out of the shelf as file URLs.
/// AppKit is used instead of `onDrag` so that several files can travel in one drag.
struct ShelfDragSource: NSViewRepresentable {
    let urls: [URL]
    let image: NSImage?
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
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
        view.urls = urls
        view.image = image
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.onOpen = onOpen
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var image: NSImage?
        var onBegin: () -> Void = {}
        var onEnd: () -> Void = {}
        var onOpen: (() -> Void)?
        private var mouseDownEvent: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            if event.clickCount == 2 { onOpen?() }
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownEvent = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent, !urls.isEmpty else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy > 9 else { return }
            mouseDownEvent = nil

            let icon = image ?? NSWorkspace.shared.icon(forFile: urls[0].path)
            let side = min(bounds.width, bounds.height, 64)
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                // Stack several files slightly so the drag shows how many there are.
                let offset = CGFloat(min(index, 3)) * 4
                let frame = CGRect(x: (bounds.width - side) / 2 + offset, y: (bounds.height - side) / 2 - offset,
                                   width: side, height: side)
                item.setDraggingFrame(frame, contents: index < 4 ? icon : nil)
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
            onEnd()
        }
    }
}
