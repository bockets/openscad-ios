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
        cameraNode.position = PreviewLighting.cameraDirection
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        PreviewLighting.rig().forEach(scene.rootNode.addChildNode)

        return scene
    }
}
