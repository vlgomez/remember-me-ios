// swift-tools-version: 6.0
// Paquete de dominio de Remember Me. Solo depende de Foundation: no importa UIKit,
// SwiftUI ni EventKit, para que las reglas se puedan probar sin simulador ni permisos.

import PackageDescription

let package = Package(
    name: "RememberMeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RememberMeCore", targets: ["RememberMeCore"])
    ],
    targets: [
        .target(name: "RememberMeCore"),
        .testTarget(
            name: "RememberMeCoreTests",
            dependencies: ["RememberMeCore"]
        )
    ]
)
