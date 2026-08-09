import SwiftUI
import SceneKit
import UIKit

/// A SceneKit-backed 3D preview with built-in orbit / pinch-to-zoom / pan.
/// Swap the displayed `node` and the camera keeps its position.
struct ScenePreviewView: UIViewRepresentable {
    /// The mesh to display. Replacing it updates the model node in place.
    var node: SCNNode

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene(with: node)
        view.allowsCameraControl = true
        // We supply our own lights (see `previewLights`) so faces shade by their
        // angle to the light; the default flat headlight would wash that out.
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        context.coordinator.modelNode = node
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        // Only swap when it's actually a new mesh. Unrelated re-renders (e.g.
        // dragging the floating preview) re-invoke this every frame; tearing the
        // node down and re-adding it each time stutters the SceneKit view.
        guard context.coordinator.modelNode !== node else { return }
        // Replace only the model node so the user's camera framing is preserved.
        context.coordinator.modelNode?.removeFromParentNode()
        scene.rootNode.addChildNode(node)
        context.coordinator.modelNode = node
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var modelNode: SCNNode?
    }

    private func makeScene(with node: SCNNode) -> SCNScene {
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 10_000
        // Screen-space ambient occlusion darkens creases and inside corners —
        // the strongest depth cue for the hard-surface parts this renders.
        camera.screenSpaceAmbientOcclusionIntensity = 1.6
        camera.screenSpaceAmbientOcclusionRadius = 8
        camera.screenSpaceAmbientOcclusionBias = 0.1
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(60, 45, 90)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        previewLights().forEach(scene.rootNode.addChildNode)

        return scene
    }

    /// A three-light rig — ambient fill plus a bright key and a softer opposing
    /// fill — so faces shade by their angle to the light and the model reads as
    /// a solid form rather than a flat normal map. The ambient term keeps faces
    /// turned away from the key from going fully black.
    private func previewLights() -> [SCNNode] {
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
}
