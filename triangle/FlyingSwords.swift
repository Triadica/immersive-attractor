import Metal
import RealityKit
import SwiftUI
import simd

private struct FlyingSwordsParams {
  var time: Float
  var dt: Float
}

private struct VertexData {
  var position: SIMD3<Float> = .zero
  var color: SIMD3<Float> = .init(0.2, 1.0, 0.4) // Default emerald green

  @MainActor static var vertexAttributes: [LowLevelMesh.Attribute] = [
    .init(
      semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
    .init(
      semantic: .color, format: .float3, offset: MemoryLayout<Self>.offset(of: \.color)!)
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

/// Placement of a sword
private struct SwordBase {
  var angle: Float  // Current angle in the circle (radians)
  var radius: Float  // Distance from center
  var height: Float  // Height in Y axis
  var tiltAngle: Float  // Tilt angle for the sword
  var layer: Int32  // Which layer (0, 1, 2)
  var speed: Float  // Rotation speed multiplier
}

struct FlyingSwordsView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let fps: Double = 120

  @State var timer: Timer?
  @State private var updateTrigger = false
  @State private var time: Float = 0

  // MARK: - Controller for gamepad input
  let controllerHelper = ControllerHelper()

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let vertexPipeline: MTLComputePipelineState

  @State var swordBuffer: MTLBuffer?
  @State var vertexBuffer: MTLBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateSwordVertexes = library.makeFunction(name: "updateSwordVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateSwordVertexes)
  }

  var body: some View {
    GeometryReader3D { proxy in
      RealityView { content in
        guard let mesh = try? createMesh(),
          let modelComponent = try? getModelComponent(mesh: mesh)
        else {
          print("failed to create mesh or model component")
          return
        }
        rootEntity.components.set(modelComponent)

        // Center point: at z=-8 plane, centered at eye level
        rootEntity.position.y = 1.0
        rootEntity.position.z = -8.0
        content.add(rootEntity)
        self.mesh = mesh

      }
      .onAppear {
        startTimer()
      }
      .onDisappear {
        stopTimer()
      }

    }
  }

  func startTimer() {
    self.mesh = try! createMesh()
    controllerHelper.reset()
    self.swordBuffer = createSwordBuffer()
    self.time = 0

    self.vertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * vertexCapacity, options: .storageModeShared)

    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in

      DispatchQueue.main.async {
        if let vertexBuffer = self.vertexBuffer {
          self.time += Float(1 / self.fps)
          self.updateMesh(vertexBuffer: vertexBuffer)

          // Record frame if recording is active
          recordMeshIfActive(mesh: self.mesh, topology: .triangles)
        } else {
          print("[ERR] vertex buffer is not initialized")
        }
        // Update controller input
        self.controllerHelper.updateEntityTransform(self.rootEntity)
        self.updateTrigger.toggle()
      }
    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
    swordBuffer = nil
    mesh = nil
    self.vertexBuffer = nil
  }

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    // Use vertex colors for the material
    var material = UnlitMaterial()
    material.color = .init(tint: .white)  // White tint to show vertex colors
    material.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [material])
  }

  func getBounds() -> BoundingBox {
    let radius: Float = 4
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  // 72 swords: 4 layers with varying counts (fewer inside, more outside)
  // Layer 0: 12, Layer 1: 16, Layer 2: 20, Layer 3: 24 = 72 total
  let swordCount: Int = 72
  let swordsPerLayer: [Int] = [12, 16, 20, 24]

  // Each sword now has 40 vertices for fully closed geometry (no holes)
  let verticesPerSword: Int = 40

  var vertexCapacity: Int {
    return swordCount * verticesPerSword
  }

  // Triangles for detailed sword with fully closed surfaces
  // Vertices layout:
  //   0 = tip
  //   1-4 = near-tip quad (top-left, top-right, bottom-left, bottom-right)
  //   5-8 = mid-blade quad
  //   9-14 = blade base (with ridges: top-left, top-ridge, top-right, bot-left, bot-ridge, bot-right)
  //   15-22 = guard (8 vertices forming closed box)
  //   23-30 = handle (8 vertices forming closed tapered box)
  //   31-39 = pommel (9 vertices: 8 octagonal + 1 center)
  var swordTriangles: [Int] = [
    // === BLADE ===
    // Tip to near-tip section
    0, 1, 2,  // top face
    0, 4, 3,  // bottom face
    0, 2, 4,  // right edge
    0, 3, 1,  // left edge

    // Near-tip quad to mid-blade quad (top face)
    1, 5, 6,
    1, 6, 2,
    // Near-tip quad to mid-blade quad (bottom face)
    3, 8, 7,
    3, 4, 8,
    // Near-tip to mid (left edge)
    1, 3, 5,
    3, 7, 5,
    // Near-tip to mid (right edge)
    2, 6, 4,
    4, 6, 8,

    // Mid-blade to base (top face with ridge)
    5, 9, 10,
    5, 10, 6,
    6, 10, 11,
    // Mid-blade to base (bottom face with ridge)
    7, 13, 12,
    7, 8, 13,
    8, 14, 13,
    // Mid to base (left edge)
    5, 7, 9,
    7, 12, 9,
    // Mid to base (right edge)
    6, 11, 8,
    8, 11, 14,

    // Blade base end cap (connecting ridges)
    9, 12, 10,
    10, 12, 13,
    10, 13, 11,
    11, 13, 14,

    // === GUARD (closed box) ===
    // Guard vertices: 15-18 front face (TL, TR, BL, BR), 19-22 back face (TL, TR, BL, BR)
    // Front face
    15, 17, 16,
    16, 17, 18,
    // Back face
    19, 20, 21,
    20, 22, 21,
    // Top face
    15, 16, 19,
    16, 20, 19,
    // Bottom face
    17, 21, 18,
    18, 21, 22,
    // Left face
    15, 19, 17,
    17, 19, 21,
    // Right face
    16, 18, 20,
    18, 22, 20,
    // Connect blade base to guard front
    9, 15, 10,
    10, 15, 16,
    10, 16, 11,
    12, 17, 9,
    9, 17, 15,
    12, 13, 17,
    13, 18, 17,
    11, 16, 14,
    14, 16, 18,
    13, 14, 18,

    // === HANDLE (closed tapered box) ===
    // Handle vertices: 23-26 front (connected to guard back), 27-30 back
    // Connect guard back to handle front
    19, 23, 20,
    20, 23, 24,
    21, 25, 19,
    19, 25, 23,
    22, 26, 21,
    21, 26, 25,
    20, 24, 22,
    22, 24, 26,
    // Handle body - front to back
    // Top face
    23, 27, 24,
    24, 27, 28,
    // Bottom face
    25, 26, 29,
    26, 30, 29,
    // Left face
    23, 25, 27,
    25, 29, 27,
    // Right face
    24, 28, 26,
    26, 28, 30,

    // === POMMEL (octagonal end cap) ===
    // Pommel vertices: 31-38 octagonal ring, 39 center
    // Connect handle back to pommel ring (4 corners to 8 octagon vertices)
    27, 31, 32,  // handle TL to pommel top
    27, 32, 28,
    28, 32, 33,  // handle TR to pommel right-top
    28, 33, 34,
    28, 34, 30,  // handle BR to pommel right-bottom
    30, 34, 35,
    30, 35, 36,
    30, 36, 29,  // handle BL to pommel bottom
    29, 36, 37,
    29, 37, 38,
    29, 38, 27,  // handle TL to pommel left
    27, 38, 31,
    // Octagonal end cap (center at 39, triangles from center to each edge)
    31, 32, 39,
    32, 33, 39,
    33, 34, 39,
    34, 35, 39,
    35, 36, 39,
    36, 37, 39,
    37, 38, 39,
    38, 31, 39,
  ]

  var indicesPerSword: Int {
    return swordTriangles.count
  }

  var indexCount: Int {
    return swordCount * indicesPerSword
  }

  func createSwordBuffer() -> MTLBuffer {
    let bufferSize = MemoryLayout<SwordBase>.stride * swordCount
    let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)!

    let contents = buffer.contents()
    let swords = contents.bindMemory(to: SwordBase.self, capacity: swordCount)

    // Layer radii (distance from center in XY plane) - 4 concentric rings
    // Inner circle starts at 2m radius
    let layerRadii: [Float] = [2.0, 2.8, 3.6, 4.4]

    // All swords move at the same linear speed (0.15 m/s)
    // Angular speed = linear speed / radius
    let linearSpeed: Float = 0.15
    // Alternate direction for each layer
    let directions: [Float] = [1.0, -1.0, 1.0, -1.0]

    var idx = 0
    for layer in 0..<4 {
      let count = swordsPerLayer[layer]
      let angularSpeed = linearSpeed / layerRadii[layer] * directions[layer]

      for i in 0..<count {
        let baseAngle = Float(i) * (2.0 * Float.pi / Float(count))
        // Add offset for each layer so swords don't align
        let layerOffset = Float(layer) * (Float.pi / 8.0)

        swords[idx] = SwordBase(
          angle: baseAngle + layerOffset,
          radius: layerRadii[layer],
          height: 0.0,  // All on same z plane
          tiltAngle: 0.0,  // Will be calculated in shader to point to target
          layer: Int32(layer),
          speed: angularSpeed
        )
        idx += 1
      }
    }

    return buffer
  }

  func createMesh() throws -> LowLevelMesh {
    var desc = VertexData.descriptor
    desc.vertexCapacity = vertexCapacity
    desc.indexCapacity = indexCount

    let mesh = try LowLevelMesh(descriptor: desc)

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<swordCount {
        for j in 0..<indicesPerSword {
          indices[i * indicesPerSword + j] =
            UInt32(swordTriangles[j]) + UInt32(i * verticesPerSword)
        }
      }
    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])

    return mesh
  }

  private func getParams() -> FlyingSwordsParams {
    return FlyingSwordsParams(time: time, dt: Float(1 / fps))
  }

  func updateMesh(vertexBuffer: MTLBuffer) {
    guard let mesh = mesh,
      let swordBuffer = swordBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateMesh: failed to get mesh or swordBuffer or commandBuffer or computeEncoder")
      return
    }

    // Copy data from mesh to vertexBuffer
    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      vertexBuffer.contents().copyMemory(
        from: rawBytes.baseAddress!, byteCount: rawBytes.count)
    }

    computeEncoder.setComputePipelineState(vertexPipeline)

    // idx 0: swordBuffer
    computeEncoder.setBuffer(swordBuffer, offset: 0, index: 0)

    // idx 1: vertexBuffer
    computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 1)

    var params = getParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<FlyingSwordsParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: vertexCapacity, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
    computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    computeEncoder.endEncoding()

    // Copy data from vertexBuffer to mesh
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.copy(
      from: vertexBuffer, sourceOffset: 0,
      to: mesh.replace(bufferIndex: 0, using: commandBuffer), destinationOffset: 0,
      size: vertexBuffer.length)
    blitEncoder.endEncoding()

    commandBuffer.commit()

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])
  }
}
