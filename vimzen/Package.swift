// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vimzen",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Vimzen", targets: ["Vimzen"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Vimzen",
            dependencies: [],
            path: "Sources/Vimzen"
        )
    ]
)
