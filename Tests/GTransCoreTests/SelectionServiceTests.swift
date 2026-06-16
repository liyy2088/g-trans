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

    func selectedTextIsPreferredWhenRangeTextDoesNotMatch() {
        let selected = SelectionService.preferredAccessibilitySelection(
            markerText: "  \n",
            rangeText: "unrelated range text",
            selectedText: "selected text"
        )

        XCTAssertEqual(selected, "selected text")
    }

    func rangeTextIsPreferredWhenItOnlyRestoresDroppedNewline() {
        let selected = SelectionService.preferredAccessibilitySelection(
            markerText: nil,
            rangeText: "You have a new rate limit reset available\nYou were granted a rate limit reset.",
            selectedText: "You have a new rate limit reset availableYou were granted a rate limit reset."
        )

        XCTAssertEqual(
            selected,
            "You have a new rate limit reset available\nYou were granted a rate limit reset."
        )
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
