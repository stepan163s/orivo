// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Orivo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Orivo", targets: ["Orivo"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Orivo",
            dependencies: [],
            path: "Sources/Orivo"
        )
    ]
)
