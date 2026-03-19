// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Voxa",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Voxa",
            dependencies: [
                .product(name: "HotKey", package: "HotKey")
            ],
            path: "Voxa",
            exclude: ["Info.plist", "Voxa.entitlements"]
        )
    ]
)
