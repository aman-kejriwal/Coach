// swift-tools-version:5.10
// Tools 5.10 = Swift 5 language mode by default (keeps SwiftUI + AppKit glue free of strict-concurrency friction).
import PackageDescription

let package = Package(
    name: "Coach",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Coach", targets: ["Coach"]),
    ],
    targets: [
        // Pure logic: frontmatter editing, scheduling, vault scanning. No UI, fully testable.
        .target(name: "CoachCore"),
        // The SwiftUI app (main window + menu bar).
        .executableTarget(name: "Coach", dependencies: ["CoachCore"]),
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore"]),
    ]
)
