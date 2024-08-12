// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "current-value-sequence",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16)
    ],
    products: [
        .library(
            name: "CurrentValueSequence",
            targets: ["CurrentValueSequence"]
        )
    ],
    targets: [
        .target(name: "CurrentValueSequence")
    ]
)
