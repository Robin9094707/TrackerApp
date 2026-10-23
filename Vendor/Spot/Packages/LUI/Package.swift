// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LUI", defaultLocalization: "en", platforms: [.iOS("18.1")],
    products: [.library(name: "LUI", targets: ["LUI"])],
    dependencies: [.package(url: "https://github.com/siteline/swiftui-introspect", revision: "807f73ce09a9b9723f12385e592b4e0aaebd3336")],
    targets: [.target(name: "LUI", dependencies: [.product(name: "SwiftUIIntrospect", package: "swiftui-introspect")],
                      resources: [.process("Resources"), .process("Assets.xcassets")])]
)
