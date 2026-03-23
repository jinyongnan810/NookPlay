import Foundation
import RealityKit
import SwiftUI
import UIKit

/// Bundle for the RealityKitContent project
public let realityKitContentBundle = Bundle.module

/// Creates a dark environment for immersive playback.
@MainActor
public func makeEvironment() async -> Entity {
    let root = Entity()
    if let scene = try? await Entity(named: "Scene", in: realityKitContentBundle) {
        print("added scene")
        root.addChild(scene)
    }
    return root
}

@MainActor
private func makeReflectiveFloorMaterial(named textureName: String, tint: CGFloat = 1) async -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    if let texture = try? await TextureResource(named: textureName, in: realityKitContentBundle) {
        let textureMap = MaterialParameters.Texture(texture)
        material.baseColor = .init(
            tint: UIColor(red: 0.22 * tint, green: 0.23 * tint, blue: 0.25 * tint, alpha: 1),
            texture: textureMap
        )
    } else {
        material.baseColor.tint = UIColor(red: 0.12 * tint, green: 0.125 * tint, blue: 0.14 * tint, alpha: 1)
    }
    material.metallic = .init(floatLiteral: 0.02)
    material.roughness = .init(floatLiteral: 0.2)
    material.specular = .init(floatLiteral: 0.82)
    material.clearcoat = .init(floatLiteral: 0.55)
    material.clearcoatRoughness = .init(floatLiteral: 0.14)
    return material
}

private func makeCeilingMaterial() -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = UIColor(red: 0.06, green: 0.065, blue: 0.072, alpha: 1)
    material.metallic = .init(floatLiteral: 0)
    material.roughness = .init(floatLiteral: 0.97)
    return material
}

private func makeWallMaterial() -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = UIColor(red: 0.05, green: 0.055, blue: 0.06, alpha: 1)
    material.metallic = .init(floatLiteral: 0)
    material.roughness = .init(floatLiteral: 0.94)
    return material
}

private func makeSideWallMaterial() -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = UIColor(red: 0.055, green: 0.06, blue: 0.068, alpha: 1)
    material.metallic = .init(floatLiteral: 0)
    material.roughness = .init(floatLiteral: 0.9)
    return material
}

private func makeFrontHeaderMaterial() -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = UIColor(red: 0.1, green: 0.105, blue: 0.115, alpha: 1)
    material.metallic = .init(floatLiteral: 0.08)
    material.roughness = .init(floatLiteral: 0.48)
    return material
}
