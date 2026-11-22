import AppKit

@MainActor
protocol MenuBarModule: AnyObject {
    var segment: MenuBarSegment? { get }
    var menuItems: [NSMenuItem] { get }
    var onChange: (() -> Void)? { get set }
    func menuWillOpen()
    func menuDidClose()
}
