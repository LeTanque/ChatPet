// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DesktopPet", targets: ["DesktopPet"]),
        .library(name: "PetCore", targets: ["PetCore"])
    ],
    targets: [
        .target(name: "PetCore"),
        .executableTarget(name: "DesktopPet", dependencies: ["PetCore"], resources: [.copy("Assets")]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
        .testTarget(name: "DesktopPetTests", dependencies: ["DesktopPet", "PetCore"])
    ]
)
