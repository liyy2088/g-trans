import XCTest
@testable import GTransCore

final class SelectionServiceTests: XCTestCase {
    func markerTextIsPreferred() {
        let selected = SelectionService.preferredAccessibilitySelection(
            markerText: "You have a new rate limit reset available\nYou were granted a rate limit reset.",
            rangeText: "range text",
            selectedText: "selected text"
        )

        XCTAssertEqual(
            selected,
            "You have a new rate limit reset available\nYou were granted a rate limit reset."
        )
    }

    func rangeTextIsPreferredWhenMarkerTextIsEmpty() {
        let selected = SelectionService.preferredAccessibilitySelection(
            markerText: "  \n",
            rangeText: "range text",
            selectedText: "selected text"
        )

        XCTAssertEqual(selected, "range text")
    }

    func selectedTextIsUsedWhenMarkerAndRangeTextAreEmpty() {
        let selected = SelectionService.preferredAccessibilitySelection(
            markerText: nil,
            rangeText: "",
            selectedText: "selected text"
        )

        XCTAssertEqual(selected, "selected text")
    }

    func emptyCandidatesReturnNil() {
        let selected = SelectionService.preferredAccessibilitySelection(
            markerText: nil,
            rangeText: " ",
            selectedText: "\n"
        )

        XCTAssertNil(selected)
    }
}
