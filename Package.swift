// swift-tools-version:6.0
//
//  Nodogram — package manifest
//
//  Target dependencies here are how the layering rule from
//  Documentation/ARCHITECTURE.md §2 is ENFORCED rather than merely documented:
//
//    NodogramDomain depends on nothing. It therefore CANNOT import TDLibKit or
//    GRDB, so a TDLib upgrade can never reach the domain model. If someone adds
//    such an import, the build fails — which is the point.
//
//  Minimum deployment target is macOS 14, per Documentation/DECISIONS.md D2.

import PackageDescription

let package = Package(
    name: "Nodogram",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "NodogramDomain", targets: ["NodogramDomain"]),
        .library(name: "NodogramCore", targets: ["NodogramCore"]),
        .library(name: "NodogramTelegram", targets: ["NodogramTelegram"]),
        .executable(name: "NodogramApp", targets: ["NodogramApp"]),
    ],
    dependencies: [
        // Exact pin is mandatory: TDLibKit's tags are SemVer prereleases, so
        // version ranges do not resolve. See Documentation/UPSTREAM.md §2.
        .package(
            url: "https://github.com/Swiftgram/TDLibKit",
            exact: "1.5.2-tdlib-1.8.67-0efabf93"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "7.11.0"
        ),
    ],
    targets: [
        // ── Domain ───────────────────────────────────────────────────────────
        // No dependencies, by design. This is the layering guarantee.
        .target(
            name: "NodogramDomain",
            path: "Nodogram/Domain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Core ─────────────────────────────────────────────────────────────
        .target(
            name: "NodogramCore",
            dependencies: [
                "NodogramDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Nodogram/Core",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Telegram ─────────────────────────────────────────────────────────
        // The ONLY target permitted to depend on TDLibKit.
        .target(
            name: "NodogramTelegram",
            dependencies: [
                "NodogramDomain",
                .product(name: "TDLibKit", package: "TDLibKit"),
            ],
            path: "Nodogram/Telegram",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── UI ───────────────────────────────────────────────────────────────
        .target(
            name: "NodogramUI",
            dependencies: ["NodogramDomain"],
            path: "Nodogram/UI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Platform (macOS integration) ─────────────────────────────────────
        .target(
            name: "NodogramPlatform",
            dependencies: ["NodogramDomain"],
            path: "Nodogram/Platform",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Features ─────────────────────────────────────────────────────────
        .target(
            name: "NodogramFeatures",
            dependencies: [
                "NodogramDomain",
                "NodogramCore",
                "NodogramTelegram",
                "NodogramUI",
                "NodogramPlatform",
            ],
            path: "Nodogram/Features",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── App (executable) ─────────────────────────────────────────────────
        .executableTarget(
            name: "NodogramApp",
            dependencies: ["NodogramFeatures", "NodogramUI", "NodogramCore", "NodogramTelegram", "NodogramDomain"],
            path: "Nodogram/App",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Tests ────────────────────────────────────────────────────────────
        .testTarget(
            name: "NodogramDomainTests",
            dependencies: ["NodogramDomain", "NodogramPlatform"],
            path: "Tests/Unit/Domain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NodogramFeaturesTests",
            dependencies: ["NodogramFeatures", "NodogramDomain", "NodogramUI"],
            path: "Tests/Unit/Features",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NodogramCoreTests",
            dependencies: ["NodogramCore", "NodogramDomain"],
            path: "Tests/Unit/Core",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NodogramTelegramTests",
            dependencies: ["NodogramTelegram", "NodogramDomain"],
            path: "Tests/Unit/Telegram",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NodogramIntegrationTests",
            dependencies: ["NodogramTelegram", "NodogramCore", "NodogramDomain"],
            path: "Tests/Integration",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
