import AppKit

/// Where the shelf sits on one display and how big its shape is in each state.
/// All rectangles are in global screen coordinates (origin bottom-left).
struct ShelfGeometry: Equatable {
    enum Mode: Equatable {
        /// Empty shelf: an invisible drop zone over the notch or the top centre.
        case hidden
        /// Files on the shelf: a small black badge with the count.
        case indicator
        /// A file is being dragged nearby; 0…1, grows toward 1 as it gets closer.
        case peek(Double)
        /// The shelf with its cards.
        case expanded

        /// An empty shelf is invisible, so it must not take clicks from the app below;
        /// it becomes a drop target once a file drag starts and the mode changes to `peek`.
        var passesClicksThrough: Bool { self == .hidden }
    }

    struct Shape: Equatable {
        var width: CGFloat
        var height: CGFloat
        var earRadius: CGFloat
        var bottomRadius: CGFloat

        /// Width including the concave "ears" at the top corners.
        var outerWidth: CGFloat { width + earRadius * 2 }
    }

    let screenFrame: CGRect
    /// Size of the camera housing, or nil on displays without one.
    let notch: CGSize?
    let menuBarHeight: CGFloat

    static let wingWidth: CGFloat = 30
    static let peekReach: CGFloat = 120
    static let expandedShadowMargin: CGFloat = 24

    init(screenFrame: CGRect, notch: CGSize?, menuBarHeight: CGFloat) {
        self.screenFrame = screenFrame
        self.notch = notch
        self.menuBarHeight = menuBarHeight
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            notch = nil
        }
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        menuBarHeight = reserved > 0 ? reserved : NSStatusBar.system.thickness
    }

    var hasNotch: Bool { notch != nil }

    /// Height of the band the system menu bar occupies; the expanded header sits there.
    var topBand: CGFloat { notch?.height ?? menuBarHeight }

    func shape(for mode: Mode) -> Shape {
        let base = notch ?? CGSize(width: 200, height: menuBarHeight)
        switch mode {
        case .hidden:
            return Shape(width: base.width, height: base.height, earRadius: 0, bottomRadius: hasNotch ? 10 : 8)
        case .indicator:
            if let notch {
                return Shape(width: notch.width + Self.wingWidth * 2, height: notch.height, earRadius: 6, bottomRadius: 10)
            }
            return Shape(width: 76, height: menuBarHeight, earRadius: 6, bottomRadius: 10)
        case .peek(let closeness):
            let start = shape(for: .indicator)
            let c = CGFloat(min(max(closeness, 0), 1))
            return Shape(
                width: start.width + 70 * c,
                height: start.height + 26 * c,
                earRadius: 6 + 2 * c,
                bottomRadius: 10 + 6 * c
            )
        case .expanded:
            let width = max(520, (notch?.width ?? 0) + 330)
            return Shape(width: width, height: topBand + 134, earRadius: 12, bottomRadius: 26)
        }
    }

    /// The window frame for a mode: the shape, plus room for the shadow when expanded.
    func panelFrame(for mode: Mode) -> CGRect {
        let shape = shape(for: mode)
        let margin = mode == .expanded ? Self.expandedShadowMargin : 0
        let width = shape.outerWidth + margin * 2
        let height = shape.height + margin
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// The area that reacts to a file being dragged closer.
    var attractionTarget: CGRect {
        let shape = shape(for: .indicator)
        return CGRect(x: screenFrame.midX - shape.outerWidth / 2, y: screenFrame.maxY - shape.height,
                      width: shape.outerWidth, height: shape.height)
    }

    /// 0 when farther than `peekReach`, 1 at the edge of the zone.
    func closeness(of point: CGPoint) -> Double {
        let zone = attractionTarget
        guard screenFrame.contains(point) || zone.contains(point) else { return 0 }
        let dx = max(zone.minX - point.x, 0, point.x - zone.maxX)
        let dy = max(zone.minY - point.y, 0, point.y - zone.maxY)
        let distance = (dx * dx + dy * dy).squareRoot()
        return Double(max(0, 1 - distance / Self.peekReach))
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
