import XCTest
@testable import ClearOutsideCore

final class RatingHeuristicTests: XCTestCase {
    func testUnknownWhenCloudDataMissing() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: nil, precipitationMm: nil, seeingRaw: nil, transparencyRaw: nil),
            .unknown
        )
    }

    func testBadWhenCloudyRegardlessOfAstro() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 80, precipitationMm: 0, seeingRaw: 1, transparencyRaw: 1),
            .bad
        )
    }

    func testBadWhenRaining() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 10, precipitationMm: 0.5, seeingRaw: 1, transparencyRaw: 1),
            .bad
        )
    }

    func testBadWhenAstroIsPoorEvenWithClearSky() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 5, precipitationMm: 0, seeingRaw: 8, transparencyRaw: 1),
            .bad
        )
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 5, precipitationMm: 0, seeingRaw: 1, transparencyRaw: 8),
            .bad
        )
    }

    func testGoodWhenClearAndAstroIsGood() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 10, precipitationMm: 0, seeingRaw: 2, transparencyRaw: 3),
            .good
        )
    }

    func testGoodWithoutAstroDataFallsBackToCloudOnly() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 5, precipitationMm: 0, seeingRaw: nil, transparencyRaw: nil),
            .good
        )
    }

    func testOkInBetween() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 40, precipitationMm: 0, seeingRaw: 5, transparencyRaw: 5),
            .ok
        )
    }

    func testOkWhenClearButAstroIsMediocre() {
        XCTAssertEqual(
            RatingHeuristic.rate(cloudPercent: 10, precipitationMm: 0, seeingRaw: 5, transparencyRaw: 2),
            .ok
        )
    }
}
