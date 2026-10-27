// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CookFlowCore", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "CookFlowCore", targets: ["CookFlowCore"])], targets: [.target(name: "CookFlowCore", path: "CookFlow/Core"), .testTarget(name: "CookFlowCoreTests", dependencies: ["CookFlowCore"], path: "Tests/CookFlowCoreTests", exclude: ["Fixtures"])])
