// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glint",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glint", targets: ["Glint"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", revision: "18c42c19cac3fafd61cab1156d4088664b7424ae")
    ],
    targets: [
        .target(name: "GlintCore", resources: [.process("Resources")]),
        .executableTarget(name: "Glint", dependencies: [
            "GlintCore", .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "SwiftMath", package: "SwiftMath")
        ], resources: [.process("Resources")]),
        .testTarget(name: "GlintCoreTests", dependencies: ["GlintCore", .product(name: "Testing", package: "swift-testing")], exclude: ["stream_server.py"], resources: [.process("Fixtures")]),
        .testTarget(name: "GlintTests", dependencies: ["Glint", .product(name: "Testing", package: "swift-testing")])
    ],
    swiftLanguageModes: [.v5]
)
