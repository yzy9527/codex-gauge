// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "CodexGauge",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "CodexGauge", targets: ["CodexGaugeApp"]),
    .library(name: "CodexGaugeCore", targets: ["CodexGaugeCore"]),
  ],
  targets: [
    .target(
      name: "CodexGaugeCore",
      path: "Sources/CodexGaugeCore"
    ),
    .executableTarget(
      name: "CodexGaugeApp",
      dependencies: ["CodexGaugeCore"],
      path: "Sources/CodexGaugeApp",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "CodexGaugeCoreTests",
      dependencies: ["CodexGaugeCore", "CodexGaugeApp"],
      path: "Tests/CodexGaugeCoreTests"
    ),
  ]
)
