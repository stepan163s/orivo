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
        .target(
            name: "Cmpv",
            path: "Sources/Cmpv",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Orivo",
            dependencies: ["Cmpv"],
            path: "Sources/Orivo",
            resources: [
                .copy("Resources/Lampa")
            ],
            linkerSettings: [
                .unsafeFlags(["-L/Applications/IINA.app/Contents/Frameworks", "-lmpv.2"])
            ]
        )
    ]
)
