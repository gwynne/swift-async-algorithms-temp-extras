// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "swift-async-algorithms-temp-extras",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "MultiProducerSingleConsumerChannel", targets: ["MultiProducerSingleConsumerChannel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MultiProducerSingleConsumerChannel",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
            ]
        ),
        .testTarget(
            name: "MultiProducerSingleConsumerChannelTests",
            dependencies: [
                .target(name: "MultiProducerSingleConsumerChannel"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
