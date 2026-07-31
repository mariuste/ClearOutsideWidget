// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClearOutsideCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ClearOutsideCore", targets: ["ClearOutsideCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "ClearOutsideCore",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]
        ),
        .testTarget(
            name: "ClearOutsideCoreTests",
            dependencies: ["ClearOutsideCore"],
            resources: [.copy("Fixtures/sample_forecast.html")]
        )
    ]
)
