// swift-tools-version:6.3
import PackageDescription
import Foundation

// MARK: - Conveniences

let localDev = ProcessInfo.processInfo.environment["LIBS_DEVELOPMENT"] == "1"
let devDir = "../"

struct Dep {
    let package: PackageDescription.Package.Dependency
    let targets: [Target.Dependency]
}

extension Array where Element == Dep {
    mutating func appendLocal(_ path: String, targets: Target.Dependency...) {
        append(.init(package: .package(path: "\(devDir)\(path)"), targets: targets))
    }

    mutating func append(_ url: String, from: Version, targets: Target.Dependency...) {
        append(.init(package: .package(url: url, from: from), targets: targets))
    }
}

// MARK: - Dependencies

var deps: [Dep] = []

deps.append("https://github.com/vapor/postgres-nio.git", from: "1.0.0", targets: .product(name: "PostgresNIO", package: "postgres-nio"))

if localDev {
    deps.appendLocal("Bridges", targets: "Bridges")
    deps.appendLocal("SQL", targets: "SQL")
} else {
    deps.append("https://github.com/tierracero/Bridges.git", from: "2.0.0", targets: .product(name: "Bridges", package: "Bridges"))
    deps.append("https://github.com/swiftstream/SQL.git", from: "2.2.0", targets: .product(name: "SQL", package: "SQL"))
}

// MARK: - Package

let package = Package(
    name: "PostgresBridge",
    platforms: [
       .macOS(.v10_15)
    ],
    products: [
        .library(name: "PostgresBridge", targets: ["PostgresBridge"]),
    ],
    dependencies: deps.map { $0.package },
    targets: [
        .target(name: "PostgresBridge", dependencies: deps.flatMap { $0.targets }),
        .testTarget(name: "PostgresBridgeTests", dependencies: [
            .target(name: "PostgresBridge")
        ]),
    ],
    swiftLanguageModes: [.v6]
)
