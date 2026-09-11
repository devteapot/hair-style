import SceneKit
import UIKit
import HairCore

/// Shared conversion from canonical linear RGB into SceneKit's UIColor input.
enum HairSceneMaterials {
    static func make(_ source: HairMaterial) -> SCNMaterial {
        let encoded = source.linearRGB.map { value in
            value <= 0.0031308 ? 12.92*value : 1.055*pow(value, 1/2.4)-0.055
        }
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: encoded[0], green: encoded[1], blue: encoded[2], alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = source.roughness
        return material
    }
}
