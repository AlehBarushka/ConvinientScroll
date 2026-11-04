import AppKit
import Foundation
import Testing
@testable import MacToolkit

@Suite("ShelfSelection")
struct ShelfSelectionTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    var order: [UUID] { [a, b, c, d] }

    private func selecting(_ ids: UUID..., modifier: ShelfSelection.Modifier = .toggle) -> ShelfSelection {
        var selection = ShelfSelection()
        for id in ids { selection.click(id, modifier: modifier, order: order) }
        return selection
    }

    @Test func plainClickSelectsOnlyThatCard() {
        var selection = selecting(a, b)
        selection.click(c, modifier: .plain, order: order)
        #expect(selection.ids == [c])
    }

    @Test func plainClickOnOneOfSeveralSelectedLeavesOnlyIt() {
        var selection = selecting(a, b)
        selection.click(a, modifier: .plain, order: order)
        #expect(selection.ids == [a])
    }

    @Test func commandClickAddsAndRemoves() {
        var selection = selecting(a)
        selection.click(c, modifier: .toggle, order: order)
        #expect(selection.ids == [a, c])
        selection.click(a, modifier: .toggle, order: order)
        #expect(selection.ids == [c])
    }

    @Test func shiftClickSelectsTheRangeFromTheLastClickInEitherDirection() {
        var selection = selecting(b, modifier: .plain)
        selection.click(d, modifier: .range, order: order)
        #expect(selection.ids == [b, c, d])
        selection.click(a, modifier: .range, order: order)
        #expect(selection.ids == [a, b])
    }

    @Test func shiftClickReplacesEarlierSelection() {
        var selection = selecting(a, d)
        selection.click(c, modifier: .range, order: order)
        #expect(selection.ids == [c, d])
    }

    @Test func shiftClickWithoutAnEarlierClickActsAsAPlainClick() {
        var selection = ShelfSelection()
        selection.click(c, modifier: .range, order: order)
        #expect(selection.ids == [c])
    }

    @Test func rangeSkipsCardsMissingFromTheOrder() {
        var selection = ShelfSelection()
        selection.click(a, modifier: .plain, order: [a, c, d])
        selection.click(d, modifier: .range, order: [a, c, d])
        #expect(selection.ids == [a, c, d])
    }

    @Test func draggingASelectedCardTakesTheWholeSelectionInShelfOrder() {
        var selection = selecting(d, b, a)
        #expect(selection.beginDrag(from: b, order: order) == [a, b, d])
        #expect(selection.ids == [a, b, d])
    }

    @Test func draggingAnUnselectedCardTakesOnlyItAndClearsTheSelection() {
        var selection = selecting(a, b)
        #expect(selection.beginDrag(from: d, order: order) == [d])
        #expect(selection.ids.isEmpty)
    }

    @Test func clearForgetsTheRangeStart() {
        var selection = selecting(a)
        selection.clear()
        #expect(selection.ids.isEmpty)
        selection.click(c, modifier: .range, order: order)
        #expect(selection.ids == [c])
    }

    @Test func retainDropsCardsThatAreNoLongerSelectable() {
        var selection = selecting(a, b)
        selection.retain([b, c, d])
        #expect(selection.ids == [b])
    }

    @Test func retainForgetsARangeStartThatWasDropped() {
        var selection = selecting(b, a)
        selection.retain([b, c, d])
        selection.click(d, modifier: .range, order: [b, c, d])
        #expect(selection.ids == [d])
    }

    @Test(arguments: [
        (NSEvent.ModifierFlags(), ShelfSelection.Modifier.plain),
        (NSEvent.ModifierFlags.command, .toggle),
        (NSEvent.ModifierFlags.shift, .range),
        (NSEvent.ModifierFlags([.command, .shift]), .toggle),
        (NSEvent.ModifierFlags.option, .plain),
    ])
    func modifierFollowsTheKeysHeld(flags: NSEvent.ModifierFlags, expected: ShelfSelection.Modifier) {
        #expect(ShelfSelection.Modifier(flags: flags) == expected)
    }
}
