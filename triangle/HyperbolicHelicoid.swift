import Metal
import RealityKit
import SwiftUI

private struct MovingCellParams {
  var width: Float
  var dt: Float
  var timestamp: Float = 0
}

private struct VertexData {
  var position: SIMD3<Float> = .zero
  // var normal: SIMD3<Float> = .zero
  // var uv: SIMD2<Float> = .zero

  @MainActor static var vertexAttributes: [LowLevelMesh.Attribute] = [
    .init(
      semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!)
    // .init(semantic: .normal, format: .float3, offset: MemoryLayout<Self>.offset(of: \.normal)!),
    // .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Self>.offset(of: \.uv)!),
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

/// placement of a cube
private struct CellBase {
  var xy: SIMD2<Float>
}

struct HyperbolicHelicoidView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let fps: Double = 120

  @State var timer: Timer?
  @State private var updateTrigger = false

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let vertexPipeline: MTLComputePipelineState

  @State var pingPongBuffer: PingPongBuffer?
  /// The vertex buffer for the mesh
  @State var vertexBuffer: MTLBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!

    let updateCellVertexes = library.makeFunction(name: "updateHyperbolicHelicoidVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateCellVertexes)
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

        // let pointLight = PointLight()
        // pointLight.position.z = 2.0
        // pointLight.light.color = .white
        // pointLight.light.intensity = 1000

        let spotLight = SpotLight()
        spotLight.light.color = .white
        spotLight.light.intensity = 221000
        spotLight.light.innerAngleInDegrees = 40
        spotLight.light.outerAngleInDegrees = 80
        spotLight.light.attenuationRadius = 10
        spotLight.position = [1, 1, 1]
        spotLight
          .look(
            at: [0, 0, 0],
            from: [1, 1, 1],
            upVector: [0, 4, 0],
            relativeTo: nil
          )
        let orangeLightComponent = DirectionalLightComponent(
          color: .orange, intensity: 10_000
        )

        rootEntity.components.set(modelComponent)
        rootEntity.components.set(orangeLightComponent)
        // rootEntity.scale = SIMD3(repeating: 1.)
        rootEntity.position.y = 1
        // rootEntity.position.x = 1.6
        rootEntity.position.z = -1
        content.add(rootEntity)
        content.add(spotLight)
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
    self.mesh = try! createMesh()  // recreate mesh when start timer
    self.pingPongBuffer = createPingPongBuffer()

    self.vertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * vertexCapacity, options: .storageModeShared)

    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in

      DispatchQueue.main.async {
        if let vertexBuffer = self.vertexBuffer {
          self.updateMesh(vertexBuffer: vertexBuffer)

          // swap buffers
          self.pingPongBuffer!.swap()
        } else {
          print("[ERR] vertex buffer is not initialized")
        }
        self.updateTrigger.toggle()
      }
    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
    pingPongBuffer = nil
    mesh = nil
    self.vertexBuffer = nil
  }

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    // var unlitMaterial = UnlitMaterial(color: .white)
    // unlitMaterial.faceCulling = .none

    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = .yellow
    material.roughness = PhysicallyBasedMaterial.Roughness(
      floatLiteral: 0.7
    )
    material.metallic = PhysicallyBasedMaterial.Metallic(
      floatLiteral: 0.3
    )
    material.faceCulling = .none
    // let sheenTint = PhysicallyBasedMaterial.Color(
    //   red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0
    // )
    // material.sheen = PhysicallyBasedMaterial.SheenColor(
    //   tint: sheenTint
    // )

    return ModelComponent(mesh: resource, materials: [material])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let gridSize: Int = 800

  var cellCount: Int {
    return gridSize * gridSize
  }

  var vertexCapacity: Int {
    return cellCount
  }

  var indexCount: Int {
    return (gridSize - 1) * (gridSize - 1) * 6
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<CellBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let cubes = contents.bindMemory(to: CellBase.self, capacity: cellCount)
    for i in 0..<gridSize {
      for j in 0..<gridSize {
        let iv = Float(i) / Float(gridSize) - 0.5
        let jv = Float(j) / Float(gridSize) - 0.5

        cubes[i * gridSize + j] = CellBase(
          xy: SIMD2<Float>(iv, jv) * 20
        )
      }
    }

    // copy data from current buffer to next buffer
    buffer.nextBuffer.contents().copyMemory(
      from: buffer.currentBuffer.contents(), byteCount: buffer.currentBuffer.length)

    return buffer
  }

  func createMesh() throws -> LowLevelMesh {
    var desc = VertexData.descriptor
    desc.vertexCapacity = vertexCapacity
    desc.indexCapacity = indexCount

    let mesh = try LowLevelMesh(descriptor: desc)

    // vertexes are set from compute shader

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<(gridSize - 1) {
        for j in 0..<(gridSize - 1) {
          let idx = (i * (gridSize - 1) + j) * 6
          indices[idx] = UInt32(i * gridSize + j)
          indices[idx + 1] = UInt32(i * gridSize + j + 1)
          indices[idx + 2] = UInt32((i + 1) * gridSize + j + 1)
          indices[idx + 3] = UInt32(i * gridSize + j)
          indices[idx + 4] = UInt32((i + 1) * gridSize + j + 1)
          indices[idx + 5] = UInt32((i + 1) * gridSize + j)
        }
      }

    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .lineStrip,
        bounds: getBounds()
      )
    ])

    return mesh
  }

  @State private var viewStartTime: Date = Date()

  private func getMovingParams() -> MovingCellParams {
    let delta = -Float(viewStartTime.timeIntervalSinceNow)
    return MovingCellParams(
      width: 0.003, dt: 0.02, timestamp: delta)
  }

  func updateMesh(vertexBuffer: MTLBuffer) {
    guard let mesh = mesh,
      let pingPongBuffer = pingPongBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateMesh: failed to get mesh or pingPongBuffer or commandBuffer or computeEncoder")
      return
    }

    // copy data from mesh to vertexBuffer
    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      vertexBuffer.contents().copyMemory(
        from: rawBytes.baseAddress!, byteCount: rawBytes.count)
    }

    computeEncoder.setComputePipelineState(vertexPipeline)

    // idx 0: pingPongBuffer
    computeEncoder.setBuffer(
      pingPongBuffer.currentBuffer, offset: 0, index: 0)

    // idx 1: vertexBuffer
    computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 1)

    var params = getMovingParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingCellParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: vertexCapacity, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
    computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    computeEncoder.endEncoding()

    // copy data from vertexBuffer to mesh
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.copy(
      from: vertexBuffer, sourceOffset: 0,
      to: mesh.replace(bufferIndex: 0, using: commandBuffer), destinationOffset: 0,
      size: vertexBuffer.length)
    blitEncoder.endEncoding()

    commandBuffer.commit()

    // apply entity with mesh data
    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])
  }
}
