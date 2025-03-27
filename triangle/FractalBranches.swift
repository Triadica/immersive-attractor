import Metal
import RealityKit
import SwiftUI

private struct VertexData {
  var position: SIMD3<Float> = .zero

  @MainActor static var vertexAttributes: [LowLevelMesh.Attribute] = [
    .init(
      semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!)
  ]

  @MainActor static var vertexLayouts: [LowLevelMesh.Layout] = [
    .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
  ]

  @MainActor static var descriptor: LowLevelMesh.Descriptor {
    var desc = LowLevelMesh.Descriptor()
    desc.vertexAttributes = VertexData.vertexAttributes
    desc.vertexLayouts = VertexData.vertexLayouts
    desc.indexType = .uint32
    return desc
  }
}

struct FractalBranchesView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let device: MTLDevice
  let commandQueue: MTLCommandQueue

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

  }

  var body: some View {
    GeometryReader3D { proxy in
      RealityView { content in
        guard let mesh = try? createMesh(),
          let modelComponent = try? getModelComponent(mesh: mesh)
        else {
          print("Failed to create mesh or model component")
          return
        }
        rootEntity.components.set(modelComponent)
        // rootEntity.scale = SIMD3(repeating: 1.)
        rootEntity.position.y = -0.5
        // rootEntity.position.x = 1.6
        // rootEntity.position.z = 0
        content.add(rootEntity)
        self.mesh = mesh

      }

    }
  }

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    var unlitMaterial = UnlitMaterial(color: .white)
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  func createMesh() throws -> LowLevelMesh {

    let v0 = SIMD3<Float>(0, 2, 0)
    let v1 = SIMD3<Float>(0, 0, 1)
    var allVertexes: [SIMD3<Float>] = []
    func write(p0: SIMD3<Float>, p1: SIMD3<Float>) {
      allVertexes.append(p0)
      allVertexes.append(p1)
    }

    buildUmbrella(
      p0: SIMD3<Float>(0, 0, 0), v0: v0, relative: v1, parts: 8, elevation: Float.pi * 0.5,
      decay: 0.36,
      step: 8,
      write: write)

    let allLength = allVertexes.count

    var desc = VertexData.descriptor
    desc.vertexCapacity = allLength
    desc.indexCapacity = allLength

    let mesh = try LowLevelMesh(descriptor: desc)

    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      let vertexes = rawBytes.bindMemory(to: VertexData.self)

      for i in 0..<allLength {
        vertexes[i].position = allVertexes[i]
      }
    }

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<allLength {
        indices[i] = UInt32(i)
      }
    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: allLength,
        topology: .line,
        bounds: getBounds()
      )
    ])

    return mesh
  }

}
func rotate3D(origin: SIMD3<Float>, axis: SIMD3<Float>, angle: Float, p: SIMD3<Float>) -> SIMD3<
  Float
> {
  let cosD = cos(angle)
  let sinD = sin(angle)
  let pV = p - origin
  let h = dot(axis, pV)
  let hV = h * axis  // Simplified multiplication
  let flatPV = pV - hV
  let flatPVLength = length(flatPV)

  // Avoid unnecessary normalization if flatPV is near zero
  if flatPVLength < 1e-6 {
    return origin + hV
  }

  let rotDirection = cross(flatPV, axis) / flatPVLength  // Combined normalize and cross
  return origin + hV + flatPV * cosD + (rotDirection * flatPVLength) * sinD
}

func buildUmbrella(
  p0: SIMD3<Float>, v0: SIMD3<Float>, relative: SIMD3<Float>, parts: Int,
  elevation: Float, decay: Float, step: Int, write: (SIMD3<Float>, SIMD3<Float>) -> Void
) {
  guard step > 0 else { return }

  let l0 = length(v0)
  let forward = v0 / l0

  // Precompute constants
  let cosElev = cos(elevation)
  let sinElev = sin(elevation)
  let pNext = p0 + v0
  let theta0 = 2 * Float.pi / Float(parts)

  // Cache cross products
  let rightward = normalize(cross(v0, relative))
  let upward = cross(rightward, forward)
  let line0 = (forward * cosElev + upward * sinElev) * (l0 * decay)

  write(p0, pNext)

  // Use stride for better performance
  let origin = SIMD3<Float>.zero
  for idx in stride(from: 0, to: parts, by: 1) {
    let line = rotate3D(origin: origin, axis: forward, angle: theta0 * Float(idx), p: line0)
    buildUmbrella(
      p0: pNext, v0: line, relative: v0, parts: parts, elevation: elevation,
      decay: decay, step: step - 1, write: write)
  }
}
