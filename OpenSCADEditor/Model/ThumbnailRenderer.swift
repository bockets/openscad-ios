import Foundation
import SceneKit
import UIKit

/// The three-light rig shared by the live preview and the offscreen thumbnail:
/// ambient fill plus a bright key and a softer opposing fill, so faces shade by
/// their angle to the light and the model reads as a solid form. The ambient
/// term keeps faces turned away from the key from going fully black.
enum PreviewLighting {
    static func rig() -> [SCNNode] {
        func directional(intensity: CGFloat, euler: SCNVector3) -> SCNNode {
            let light = SCNLight()
            light.type = .directional
            light.intensity = intensity
            light.color = UIColor.white
            let node = SCNNode()
            node.light = light
            node.eulerAngles = euler
            return node
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 220
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient

        let key = directional(intensity: 850, euler: SCNVector3(-Float.pi / 4, Float.pi / 6, 0))
        let fill = directional(intensity: 260, euler: SCNVector3(Float.pi / 5, -Float.pi / 3, 0))

        return [ambientNode, key, fill]
    }

    /// The direction the live preview's camera looks from; the thumbnail frames
    /// the model from the same angle so the list icon matches what you last saw.
    static let cameraDirection = SCNVector3(60, 45, 90)
}

/// Renders a small square preview image of a mesh, off screen, for the projects
/// list. Uses the same light rig as the live preview and auto-frames the camera
/// to the model's bounding sphere so both tiny and large models fill the tile.
enum ThumbnailRenderer {
    static let pixelSize = CGSize(width: 240, height: 240)

    @MainActor
    static func pngData(of sourceNode: SCNNode) -> Data? {
        // Clone so we can drop the mesh into a throwaway scene without detaching
        // it from the live preview (`clone()` shares the geometry, copies the
        // node's transform/pivot — which is what centers the model at origin).
        let model = sourceNode.clone()

        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.12, alpha: 1)
        scene.rootNode.addChildNode(model)
        PreviewLighting.rig().forEach(scene.rootNode.addChildNode)

        let cameraNode = framedCamera(for: model)
        scene.rootNode.addChildNode(cameraNode)

        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode

        let image = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        return image.pngData()
    }

    /// A camera placed along the preview's viewing direction, pulled back far
    /// enough that the model's bounding sphere fits within the field of view.
    private static func framedCamera(for node: SCNNode) -> SCNNode {
        let (minB, maxB) = node.boundingBox
        let extent = SCNVector3(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        let radius = 0.5 * sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 100_000
        camera.screenSpaceAmbientOcclusionIntensity = 1.6
        camera.screenSpaceAmbientOcclusionRadius = 8
        camera.screenSpaceAmbientOcclusionBias = 0.1

        let fovRadians = Float(camera.fieldOfView) * .pi / 180
        // 1.25 leaves a little margin so the model doesn't touch the edges.
        let safeRadius = max(radius, 0.001)
        let distance = safeRadius / tan(fovRadians / 2) * 1.25

        let dir = PreviewLighting.cameraDirection
        let length = max(sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z), 0.001)
        let unit = SCNVector3(dir.x / length, dir.y / length, dir.z / length)

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(unit.x * distance, unit.y * distance, unit.z * distance)
        cameraNode.look(at: SCNVector3Zero)
        return cameraNode
    }
}
