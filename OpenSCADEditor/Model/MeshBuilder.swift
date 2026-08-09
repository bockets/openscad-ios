import Foundation
import SceneKit
import UIKit

/// Builds SceneKit geometry for the preview: a parametric placeholder box in
/// stage 1, and (stage 2) a mesh loaded from OpenSCAD's binary STL output.
enum MeshBuilder {

    // MARK: - Placeholder (stage 1)

    /// A box sized from common dimension parameters, so tweaking width/height/
    /// depth visibly updates the preview before the real engine is wired in.
    static func placeholderNode(from groups: [ScadParameterGroup]) -> SCNNode {
        let numbers = numericValues(in: groups)
        func dim(_ names: [String], default def: Double) -> Double {
            for name in names {
                if let value = numbers[name.lowercased()], value > 0 { return value }
            }
            return def
        }

        let width = dim(["width", "w", "size", "x"], default: 20)
        let height = dim(["height", "h", "z", "thickness"], default: 20)
        let depth = dim(["depth", "length", "d", "l", "y"], default: 20)

        let box = SCNBox(
            width: CGFloat(width),
            height: CGFloat(height),
            length: CGFloat(depth),
            chamferRadius: CGFloat(min(width, height, depth) * 0.03)
        )
        box.materials = [normalMaterial()]

        return SCNNode(geometry: box)
    }

    private static func numericValues(in groups: [ScadParameterGroup]) -> [String: Double] {
        var result: [String: Double] = [:]
        for parameter in groups.flatMap(\.parameters) {
            if case .number(let n) = parameter.value {
                result[parameter.name.lowercased()] = n
            }
        }
        return result
    }

    // MARK: - STL (stage 2)

    /// Parses STL output (binary or ASCII) into a SceneKit node, or nil if the
    /// data isn't a mesh we can read.
    static func node(fromSTL data: Data) -> SCNNode? {
        if let binary = node(fromBinarySTL: data) { return binary }
        return node(fromASCIISTL: data)
    }

    /// Parses OpenSCAD's binary STL output into a SceneKit node, or nil if the
    /// data is not a valid binary STL.
    static func node(fromBinarySTL data: Data) -> SCNNode? {
        // Header (80) + UInt32 triangle count (4) = 84 bytes minimum.
        guard data.count >= 84 else { return nil }

        let triangleCount = data.subdata(in: 80..<84).withUnsafeBytes { $0.load(as: UInt32.self) }
        let expected = 84 + Int(triangleCount) * 50
        guard triangleCount > 0, data.count >= expected else { return nil }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        vertices.reserveCapacity(Int(triangleCount) * 3)
        normals.reserveCapacity(Int(triangleCount) * 3)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 84
            func float(_ at: Int) -> Float { raw.loadUnaligned(fromByteOffset: at, as: Float.self) }
            for _ in 0..<Int(triangleCount) {
                let nx = float(offset), ny = float(offset + 4), nz = float(offset + 8)
                let normal = SCNVector3(nx, ny, nz)
                for corner in 0..<3 {
                    let base = offset + 12 + corner * 12
                    vertices.append(SCNVector3(float(base), float(base + 4), float(base + 8)))
                    normals.append(normal)
                }
                offset += 50
            }
        }

        return geometryNode(vertices: vertices, normals: normals)
    }

    /// Parses an ASCII STL (`solid ... facet normal ... vertex x y z`) into a
    /// SceneKit node, or nil if it isn't ASCII STL.
    static func node(fromASCIISTL data: Data) -> SCNNode? {
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix("solid") || text.contains("facet normal") else { return nil }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var currentNormal = SCNVector3Zero

        for line in text.split(separator: "\n") {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = tokens.first else { continue }

            if keyword == "facet", tokens.count >= 5, tokens[1] == "normal" {
                currentNormal = SCNVector3(
                    Float(tokens[2]) ?? 0,
                    Float(tokens[3]) ?? 0,
                    Float(tokens[4]) ?? 0
                )
            } else if keyword == "vertex", tokens.count >= 4 {
                vertices.append(SCNVector3(
                    Float(tokens[1]) ?? 0,
                    Float(tokens[2]) ?? 0,
                    Float(tokens[3]) ?? 0
                ))
                normals.append(currentNormal)
            }
        }

        guard vertices.count >= 3 else { return nil }
        return geometryNode(vertices: vertices, normals: normals)
    }

    // MARK: - Geometry helpers

    private static func geometryNode(vertices: [SCNVector3], normals: [SCNVector3]) -> SCNNode {
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let indices = (0..<Int32(vertices.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.materials = [normalMaterial()]

        let node = SCNNode(geometry: geometry)
        node.centerAtOrigin()
        return node
    }

    /// A material that colors each face by its orientation (the classic "normal
    /// material": world-space normal mapped to RGB) and then shades that color
    /// with the scene's lights. Feeding the normal color into `_surface.diffuse`
    /// as albedo — rather than forcing `_output.color` and bypassing lighting —
    /// keeps the orientation hues while letting directional lights and ambient
    /// occlusion add form, so parts read with depth instead of looking flat.
    private static func normalMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.0
        material.roughness.contents = 0.65
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: normalShaderModifier]
        return material
    }

    private static let normalShaderModifier = """
    #pragma body
    vec3 worldNormal = normalize((scn_frame.inverseViewTransform * vec4(_surface.normal, 0.0)).xyz);
    _surface.diffuse.rgb = worldNormal * 0.5 + 0.5;
    _surface.diffuse.a = 1.0;
    """
}

private extension SCNNode {
    /// Recenters the node so its bounding box midpoint sits at the origin.
    func centerAtOrigin() {
        let (minB, maxB) = boundingBox
        pivot = SCNMatrix4MakeTranslation(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
    }
}
