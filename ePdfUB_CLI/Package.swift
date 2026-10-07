// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ePdfUB_CLI",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .executable(name: "ePdfUB_CLI", targets: ["ePdfUB_CLI"])
    ],
    targets: [
        .executableTarget(
            name: "ePdfUB_CLI",
            dependencies: [],
            resources: [
                .copy("Models")
            ],
            swiftSettings: [
                .define("CLI_MODE")
            ]
        )
    ]
)
