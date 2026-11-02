import CoreGraphics
import Testing
@testable import MacToolkit

@Suite("ShelfGeometry")
struct ShelfGeometryTests {
    let notched = ShelfGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notch: CGSize(width: 185, height: 32),
        menuBarHeight: 32
    )
    let plain = ShelfGeometry(
        screenFrame: CGRect(x: -1920, y: 360, width: 1920, height: 1080),
        notch: nil,
        menuBarHeight: 24
    )

    @Test func hiddenZoneCoversTheNotch() {
        let frame = notched.panelFrame(for: .hidden)
        #expect(frame == CGRect(x: 663.5, y: 950, width: 185, height: 32))
    }

    @Test func hiddenZoneSitsAtTheTopCentreOfOtherDisplays() {
        let frame = plain.panelFrame(for: .hidden)
        #expect(frame.midX == plain.screenFrame.midX)
        #expect(frame.maxY == plain.screenFrame.maxY)
        #expect(frame.height == 24)
    }

    @Test func indicatorAddsWingsBesideTheNotch() {
        let shape = notched.shape(for: .indicator)
        #expect(shape.width == 185 + ShelfGeometry.wingWidth * 2)
        #expect(shape.height == 32)
    }

    @Test func peekGrowsAsTheFileGetsCloser() {
        let far = notched.shape(for: .peek(0.2))
        let near = notched.shape(for: .peek(0.9))
        #expect(near.width > far.width)
        #expect(near.height > far.height)
        #expect(notched.shape(for: .peek(0)) == notched.shape(for: .indicator))
    }

    @Test func expandedFrameLeavesRoomForTheShadow() {
        let shape = notched.shape(for: .expanded)
        let frame = notched.panelFrame(for: .expanded)
        #expect(frame.width == shape.outerWidth + ShelfGeometry.expandedShadowMargin * 2)
        #expect(frame.maxY == notched.screenFrame.maxY)
        #expect(frame.midX == notched.screenFrame.midX)
    }

    @Test func onlyTheEmptyShelfPassesClicksThrough() {
        #expect(ShelfGeometry.Mode.hidden.passesClicksThrough)
        #expect(!ShelfGeometry.Mode.indicator.passesClicksThrough)
        #expect(!ShelfGeometry.Mode.peek(0).passesClicksThrough)
        #expect(!ShelfGeometry.Mode.expanded.passesClicksThrough)
    }

    @Test func closenessFallsOffWithDistance() {
        let zone = notched.attractionTarget
        #expect(notched.closeness(of: CGPoint(x: zone.midX, y: zone.minY)) == 1)
        #expect(notched.closeness(of: CGPoint(x: zone.midX, y: zone.minY - 60)) == 0.5)
        #expect(notched.closeness(of: CGPoint(x: zone.midX, y: zone.minY - 200)) == 0)
        // A point on another display never attracts this shelf.
        #expect(notched.closeness(of: CGPoint(x: -100, y: 900)) == 0)
    }
}
