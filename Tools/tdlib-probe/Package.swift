// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "tdlib-probe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Swiftgram/TDLibKit", exact: "1.5.2-tdlib-1.8.67-0efabf93")
    ],
    targets: [
        .executableTarget(name: "tdlib-probe", dependencies: ["TDLibKit"])
    ]
)
