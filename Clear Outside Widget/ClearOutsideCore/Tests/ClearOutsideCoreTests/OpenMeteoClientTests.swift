import XCTest
@testable import ClearOutsideCore

final class OpenMeteoClientTests: XCTestCase {
    private func loadFixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample_openmeteo", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDecodesTopLevelFields() throws {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: loadFixture())

        XCTAssertEqual(response.latitude, 48.0)
        XCTAssertEqual(response.longitude, 7.86, accuracy: 0.01)
        XCTAssertEqual(response.timezone, "Europe/Berlin")
    }

    func testHourlyArraysAreDecodedAndAligned() throws {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: loadFixture())
        let hourly = response.hourly

        XCTAssertFalse(hourly.time.isEmpty)
        // All parallel arrays must have exactly as many entries as `time`.
        let count = hourly.time.count
        XCTAssertEqual(hourly.cloudcover.count, count)
        XCTAssertEqual(hourly.cloudcoverLow.count, count)
        XCTAssertEqual(hourly.cloudcoverMid.count, count)
        XCTAssertEqual(hourly.cloudcoverHigh.count, count)
        XCTAssertEqual(hourly.temperature2m.count, count)
        XCTAssertEqual(hourly.precipitation.count, count)
        XCTAssertEqual(hourly.windspeed10m.count, count)
        XCTAssertEqual(hourly.relativehumidity2m.count, count)
        XCTAssertEqual(hourly.pressureMsl.count, count)
        XCTAssertEqual(hourly.visibility.count, count)
    }

    func testFirstHourMatchesKnownFixtureValues() throws {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: loadFixture())
        let hourly = response.hourly

        XCTAssertEqual(hourly.time.first, "2026-07-31T00:00")
        XCTAssertEqual(hourly.cloudcover.first, 0)
    }

    func testCloudCoverValuesArePercentages() throws {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: loadFixture())
        for value in response.hourly.cloudcover {
            XCTAssertTrue((0...100).contains(value), "cloudcover out of range: \(value)")
        }
    }
}
