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
  var height: Float  // Height in Y axis (unused)
  var tiltAngle: Float  // Tilt angle for the sword (unused)
  var layer: Int32  // Which layer (0, 1, 2, 3)
  var speed: Float  // Rotation speed multiplier
  
  // Launch state
  var launchDelay: Float = 0.0     // Random delay before launching (0~0.4s)
  var launchSpeed: Float = 3.0     // Speed toward target (2~4 m/s)
  var launchTime: Float = -1.0     // Time when launch was triggered (-1 = not launched)
  var launchStartPos: SIMD3<Float> = .zero  // Position when launch started
}

struct FlyingSwordsView: View {
  let rootEntity: Entity = Entity()
  let bladeEntity: Entity = Entity()
  let hiltEntity: Entity = Entity()
  
  @State var bladeMesh: LowLevelMesh?
  @State var hiltMesh: LowLevelMesh?

  let fps: Double = 120

  @State var timer: Timer?
  @State private var updateTrigger = false
  @State private var time: Float = 0

  // MARK: - Launch state
  @State private var isLaunched: Bool = false
  @State private var lastCrossPressed: Bool = false  // X button (cross) state
  @State private var lastSquarePressed: Bool = false // Square button state

  // MARK: - Controller for gamepad input
  let controllerHelper = ControllerHelper()

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let bladePipeline: MTLComputePipelineState
  let hiltPipeline: MTLComputePipelineState

  @State var swordBuffer: MTLBuffer?
  @State var bladeVertexBuffer: MTLBuffer?
  @State var hiltVertexBuffer: MTLBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateBladeVertexes = library.makeFunction(name: "updateBladeVertexes")!
    let updateHiltVertexes = library.makeFunction(name: "updateHiltVertexes")!
    self.bladePipeline = try! device.makeComputePipelineState(function: updateBladeVertexes)
    self.hiltPipeline = try! device.makeComputePipelineState(function: updateHiltVertexes)
  }

  var body: some View {
    GeometryReader3D { proxy in
      RealityView { content in
        // Create blade mesh and entity
        guard let bladeMesh = try? createBladeMesh(),
          let bladeModelComponent = try? getBladeModelComponent(mesh: bladeMesh)
        else {
          print("failed to create blade mesh or model component")
          return
        }
        bladeEntity.components.set(bladeModelComponent)
        rootEntity.addChild(bladeEntity)
        self.bladeMesh = bladeMesh
        
        // Create hilt mesh and entity
        guard let hiltMesh = try? createHiltMesh(),
          let hiltModelComponent = try? getHiltModelComponent(mesh: hiltMesh)
        else {
          print("failed to create hilt mesh or model component")
          return
        }
        hiltEntity.components.set(hiltModelComponent)
        rootEntity.addChild(hiltEntity)
        self.hiltMesh = hiltMesh

        // Center point: at z=-8 plane, centered at eye level
        rootEntity.position.y = 1.0
        rootEntity.position.z = -8.0
        content.add(rootEntity)

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
    self.bladeMesh = try! createBladeMesh()
    self.hiltMesh = try! createHiltMesh()
    controllerHelper.reset()
    self.swordBuffer = createSwordBuffer()
    self.time = 0

    self.bladeVertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * bladeVertexCapacity, options: .storageModeShared)
    self.hiltVertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * hiltVertexCapacity, options: .storageModeShared)

    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in

      DispatchQueue.main.async {
        if let bladeVertexBuffer = self.bladeVertexBuffer,
           let hiltVertexBuffer = self.hiltVertexBuffer {
          self.time += Float(1 / self.fps)
          
          // Check controller buttons for launch/reset
          self.checkControllerButtons()
          
          self.updateBladeMesh(vertexBuffer: bladeVertexBuffer)
          self.updateHiltMesh(vertexBuffer: hiltVertexBuffer)

          // Record frame if recording is active
          // TODO: Need to combine both meshes for recording
          // recordMeshIfActive(mesh: self.bladeMesh, topology: .triangles)
        } else {
          print("[ERR] vertex buffer is not initialized")
        }
        // Update controller input
        self.controllerHelper.updateEntityTransform(self.rootEntity)
        self.updateTrigger.toggle()
      }
    }
  }
  
  /// Check controller buttons and trigger launch/reset
  func checkControllerButtons() {
    let input = controllerHelper.gameManager.getTetrisInput()
    
    // X button (cross) - Launch swords
    if input.buttonCross && !lastCrossPressed && !isLaunched {
      launchSwords()
    }
    lastCrossPressed = input.buttonCross
    
    // Square button - Reset swords
    if input.buttonSquare && !lastSquarePressed {
      resetSwords()
    }
    lastSquarePressed = input.buttonSquare
  }
  
  /// Launch all swords toward target with random delays
  func launchSwords() {
    guard let buffer = swordBuffer else { return }
    
    print("[FlyingSwords] Launching swords!")
    isLaunched = true
    
    let contents = buffer.contents()
    let swords = contents.bindMemory(to: SwordBase.self, capacity: swordCount)
    
    for i in 0..<swordCount {
      // Random delay between 0 and 0.4 seconds
      swords[i].launchDelay = Float.random(in: 0.0...0.4)
      
      // Random speed between 6 and 12 m/s (3x original speed)
      swords[i].launchSpeed = Float.random(in: 6.0...12.0)
      
      // Record launch time
      swords[i].launchTime = time
      
      // Calculate current position as launch start position
      let currentAngle = swords[i].angle + time * swords[i].speed
      let radius = swords[i].radius
      swords[i].launchStartPos = SIMD3<Float>(
        cos(currentAngle) * radius,
        sin(currentAngle) * radius,
        0.0
      )
    }
  }
  
  /// Reset all swords to circling formation
  func resetSwords() {
    guard let buffer = swordBuffer else { return }
    
    print("[FlyingSwords] Resetting swords to formation")
    isLaunched = false
    
    let contents = buffer.contents()
    let swords = contents.bindMemory(to: SwordBase.self, capacity: swordCount)
    
    for i in 0..<swordCount {
      // Reset launch state
      swords[i].launchTime = -1.0
      swords[i].launchDelay = 0.0
      swords[i].launchStartPos = .zero
    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
    swordBuffer = nil
    bladeMesh = nil
    hiltMesh = nil
    self.bladeVertexBuffer = nil
    self.hiltVertexBuffer = nil
  }

  func getBladeModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    // Emerald green with slight gold tint for blade (to suggest golden mesh pattern)
    var unlitMaterial = UnlitMaterial(color: UIColor(red: 0.25, green: 0.9, blue: 0.45, alpha: 1.0))
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }
  
  func getHiltModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    // Deep teal/jade green for hilt - darker green with blue undertones
    var unlitMaterial = UnlitMaterial(color: UIColor(red: 0.08, green: 0.35, blue: 0.28, alpha: 1.0))
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  func getBounds() -> BoundingBox {
    let radius: Float = 4
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  // 144 swords: 6 layers with varying counts (fewer inside, more outside)
  // Layer 0: 16, Layer 1: 20, Layer 2: 24, Layer 3: 26, Layer 4: 28, Layer 5: 30 = 144 total
  let swordCount: Int = 144
  let swordsPerLayer: [Int] = [16, 20, 24, 26, 28, 30]

  // Blade: vertices 0-14 (15 vertices per sword)
  let bladeVerticesPerSword: Int = 15
  // Hilt: vertices 15-39 (25 vertices per sword: guard + handle + pommel)
  let hiltVerticesPerSword: Int = 25
  // Total vertices (for reference)
  let verticesPerSword: Int = 40

  var bladeVertexCapacity: Int {
    return swordCount * bladeVerticesPerSword
  }
  
  var hiltVertexCapacity: Int {
    return swordCount * hiltVerticesPerSword
  }

  // Triangles for blade only (vertices 0-14)
  var bladeTriangles: [Int] = [
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
  ]
  
  // Triangles for hilt only (originally vertices 15-39, remapped to 0-24)
  var hiltTriangles: [Int] = [
    // === GUARD (closed box) ===
    // Guard vertices: 0-3 front face (TL, TR, BL, BR), 4-7 back face (TL, TR, BL, BR)
    // (original 15-22 -> 0-7)
    // Front face
    0, 2, 1,
    1, 2, 3,
    // Back face
    4, 5, 6,
    5, 7, 6,
    // Top face
    0, 1, 4,
    1, 5, 4,
    // Bottom face
    2, 6, 3,
    3, 6, 7,
    // Left face
    0, 4, 2,
    2, 4, 6,
    // Right face
    1, 3, 5,
    3, 7, 5,

    // === HANDLE (closed tapered box) ===
    // Handle vertices: 8-11 front (connected to guard back), 12-15 back
    // (original 23-30 -> 8-15)
    // Connect guard back to handle front
    4, 8, 5,
    5, 8, 9,
    6, 10, 4,
    4, 10, 8,
    7, 11, 6,
    6, 11, 10,
    5, 9, 7,
    7, 9, 11,
    // Handle body - front to back
    // Top face
    8, 12, 9,
    9, 12, 13,
    // Bottom face
    10, 11, 14,
    11, 15, 14,
    // Left face
    8, 10, 12,
    10, 14, 12,
    // Right face
    9, 13, 11,
    11, 13, 15,

    // === POMMEL (octagonal end cap) ===
    // Pommel vertices: 16-23 octagonal ring, 24 center
    // (original 31-39 -> 16-24)
    // Connect handle back to pommel ring
    12, 16, 17,
    12, 17, 13,
    13, 17, 18,
    13, 18, 19,
    13, 19, 15,
    15, 19, 20,
    15, 20, 21,
    15, 21, 14,
    14, 21, 22,
    14, 22, 23,
    14, 23, 12,
    12, 23, 16,
    // Octagonal end cap (center at 24)
    16, 17, 24,
    17, 18, 24,
    18, 19, 24,
    19, 20, 24,
    20, 21, 24,
    21, 22, 24,
    22, 23, 24,
    23, 16, 24,
  ]

  var bladeIndicesPerSword: Int {
    return bladeTriangles.count
  }
  
  var hiltIndicesPerSword: Int {
    return hiltTriangles.count
  }

  var bladeIndexCount: Int {
    return swordCount * bladeIndicesPerSword
  }
  
  var hiltIndexCount: Int {
    return swordCount * hiltIndicesPerSword
  }

  func createSwordBuffer() -> MTLBuffer {
    let bufferSize = MemoryLayout<SwordBase>.stride * swordCount
    let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)!

    let contents = buffer.contents()
    let swords = contents.bindMemory(to: SwordBase.self, capacity: swordCount)

    // Layer radii (distance from center in XY plane) - 6 concentric rings
    // Inner circle starts at 1.6m radius, spacing ~0.6m between layers
    let layerRadii: [Float] = [1.6, 2.2, 2.8, 3.4, 4.0, 4.6]

    // All swords move at the same linear speed (0.15 m/s)
    // Angular speed = linear speed / radius
    let linearSpeed: Float = 0.15
    // Alternate direction for each layer
    let directions: [Float] = [1.0, -1.0, 1.0, -1.0, 1.0, -1.0]

    var idx = 0
    for layer in 0..<6 {
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
          speed: angularSpeed,
          launchDelay: 0.0,
          launchSpeed: 3.0,
          launchTime: -1.0,  // Not launched
          launchStartPos: .zero
        )
        idx += 1
      }
    }

    return buffer
  }

  func createBladeMesh() throws -> LowLevelMesh {
    var desc = VertexData.descriptor
    desc.vertexCapacity = bladeVertexCapacity
    desc.indexCapacity = bladeIndexCount

    let mesh = try LowLevelMesh(descriptor: desc)

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<swordCount {
        for j in 0..<bladeIndicesPerSword {
          indices[i * bladeIndicesPerSword + j] =
            UInt32(bladeTriangles[j]) + UInt32(i * bladeVerticesPerSword)
        }
      }
    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: bladeIndexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])

    return mesh
  }
  
  func createHiltMesh() throws -> LowLevelMesh {
    var desc = VertexData.descriptor
    desc.vertexCapacity = hiltVertexCapacity
    desc.indexCapacity = hiltIndexCount

    let mesh = try LowLevelMesh(descriptor: desc)

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<swordCount {
        for j in 0..<hiltIndicesPerSword {
          indices[i * hiltIndicesPerSword + j] =
            UInt32(hiltTriangles[j]) + UInt32(i * hiltVerticesPerSword)
        }
      }
    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: hiltIndexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])

    return mesh
  }

  private func getParams() -> FlyingSwordsParams {
    return FlyingSwordsParams(time: time, dt: Float(1 / fps))
  }

  func updateBladeMesh(vertexBuffer: MTLBuffer) {
    guard let mesh = bladeMesh,
      let swordBuffer = swordBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateBladeMesh: failed to get mesh or swordBuffer or commandBuffer or computeEncoder")
      return
    }

    // Copy data from mesh to vertexBuffer
    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      vertexBuffer.contents().copyMemory(
        from: rawBytes.baseAddress!, byteCount: rawBytes.count)
    }

    computeEncoder.setComputePipelineState(bladePipeline)

    // idx 0: swordBuffer
    computeEncoder.setBuffer(swordBuffer, offset: 0, index: 0)

    // idx 1: vertexBuffer
    computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 1)

    var params = getParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<FlyingSwordsParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: bladeVertexCapacity, height: 1, depth: 1)
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
        indexCount: bladeIndexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])
  }
  
  func updateHiltMesh(vertexBuffer: MTLBuffer) {
    guard let mesh = hiltMesh,
      let swordBuffer = swordBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateHiltMesh: failed to get mesh or swordBuffer or commandBuffer or computeEncoder")
      return
    }

    // Copy data from mesh to vertexBuffer
    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      vertexBuffer.contents().copyMemory(
        from: rawBytes.baseAddress!, byteCount: rawBytes.count)
    }

    computeEncoder.setComputePipelineState(hiltPipeline)

    // idx 0: swordBuffer
    computeEncoder.setBuffer(swordBuffer, offset: 0, index: 0)

    // idx 1: vertexBuffer
    computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 1)

    var params = getParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<FlyingSwordsParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: hiltVertexCapacity, height: 1, depth: 1)
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
        indexCount: hiltIndexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])
  }
}
