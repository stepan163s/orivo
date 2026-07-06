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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.2")
    ],
    targets: [
        .target(
            name: "Cmpv",
            path: "Sources/Cmpv",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Orivo",
            dependencies: [
                "Cmpv",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Orivo",
            resources: [
                .copy("Resources/Lampa")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/opt/mpv/lib",
                    "-L/usr/local/opt/mpv/lib",
                    "-L/Applications/IINA.app/Contents/Frameworks",
                    "-lmpv.2"
                ])
            ]
        )
    ]
)
