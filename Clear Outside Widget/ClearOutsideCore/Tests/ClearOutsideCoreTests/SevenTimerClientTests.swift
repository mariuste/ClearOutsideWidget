import XCTest
@testable import ClearOutsideCore

final class SevenTimerClientTests: XCTestCase {
    private func loadFixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample_7timer_astro", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDecodesTopLevelFields() throws {
        let response = try JSONDecoder().decode(SevenTimerAstroResponse.self, from: loadFixture())

        XCTAssertEqual(response.product, "astro")
        XCTAssertEqual(response.initTimeRaw, "2026073112")
    }

    func testInitDateIsParsedAsUTC() throws {
        let response = try JSONDecoder().decode(SevenTimerAstroResponse.self, from: loadFixture())
        let initDate = try XCTUnwrap(response.initDate)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: initDate)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 12)
    }

    func testDataseriesCoversThreeDaysInThreeHourSteps() throws {
        let response = try JSONDecoder().decode(SevenTimerAstroResponse.self, from: loadFixture())

        XCTAssertEqual(response.dataseries.count, 24)
        XCTAssertEqual(response.dataseries.first?.timepoint, 3)
        XCTAssertEqual(response.dataseries.last?.timepoint, 72)

        for (previous, current) in zip(response.dataseries, response.dataseries.dropFirst()) {
            XCTAssertEqual(current.timepoint - previous.timepoint, 3)
        }
    }

    func testBucketedValuesAreInDocumentedRanges() throws {
        let response = try JSONDecoder().decode(SevenTimerAstroResponse.self, from: loadFixture())

        for point in response.dataseries {
            XCTAssertTrue((1...9).contains(point.cloudcover), "cloudcover out of range: \(point.cloudcover)")
            XCTAssertTrue((1...8).contains(point.seeing), "seeing out of range: \(point.seeing)")
            XCTAssertTrue((1...8).contains(point.transparency), "transparency out of range: \(point.transparency)")
            XCTAssertFalse(point.wind10m.direction.isEmpty)
        }
    }
}
