import Metal
import RealityKit
import RealityKitContent
import SwiftUI
import simd

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

struct FractalTreeView: View {
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

        // Add components for gesture support
        rootEntity.components.set(modelComponent)

        // Enable world sensing
        // content.enableWorldSensing([.hands])

        // Adjust collision box size to match actual content










        // Move entity closer to user
        rootEntity.position = SIMD3<Float>(0, 0, -1)  // Adjust these values
        content.add(rootEntity)
        self.mesh = mesh
      }
    }
  }

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    var unlitMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.5, blue: 0.5, alpha: 0.8))
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 10
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  func createMesh() throws -> LowLevelMesh {

    let v0 = SIMD3<Float>(0, 4, 0)
    let v1 = SIMD3<Float>(0, 0, 1)
    var allVertexes: [SIMD3<Float>] = []
    func write(p0: SIMD3<Float>, p1: SIMD3<Float>) {
      allVertexes.append(p0 - v0)
      allVertexes.append(p1 - v0)
    }

    buildUmbrella(
      p0: SIMD3<Float>(0, 0, 0), v0: v0, relative: v1, parts: 7, elevation: 0.32 * Float.pi,
      decay: 0.46,
      step: 7,
      write: write, middle: true)

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
