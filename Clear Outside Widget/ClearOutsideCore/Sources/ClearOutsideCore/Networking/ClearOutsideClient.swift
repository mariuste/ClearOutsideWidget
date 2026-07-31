import Foundation

public enum ClearOutsideClientError: Error {
    case badStatus(Int)
    case decodingFailed
}

public struct ClearOutsideClient: Sendable {
    public static let forecastURL = URL(string: "https://clearoutside.com/forecast/48.00/7.85?experimental=on")!

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    public func fetchHTML() async throws -> String {
        var request = URLRequest(url: Self.forecastURL)
        // ClearOutside blocks requests without a browser-like User-Agent.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw ClearOutsideClientError.badStatus(httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ClearOutsideClientError.decodingFailed
        }
        return html
    }
}
