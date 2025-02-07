import Metal
import RealityKit
import SwiftUI

private struct MovingCubesParams {
  var width: Float
  var dt: Float
}

private struct VertexData {
  var position: SIMD3<Float> = .zero
  var normal: SIMD3<Float> = .zero
  var uv: SIMD2<Float> = .zero
  var atSide: Bool = false
  var leading: Bool = false
  var secondary: Bool = false

  @MainActor static var vertexAttributes: [LowLevelMesh.Attribute] = [
    .init(
      semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
    .init(semantic: .normal, format: .float3, offset: MemoryLayout<Self>.offset(of: \.normal)!),
    .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Self>.offset(of: \.uv)!),
    // .init(
    //   semantic: .unspecified, format: .float,
    //   offset: MemoryLayout<Self>.offset(of: \.atSide)!
    // ),
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
private struct CubeBase {
  var position: SIMD3<Float>
  var size: Float
  var rotate: Float
}

struct CubesMovingView: View {
  let rootEntity: Entity = Entity()

  let fps: Double = 120

  // fourwing params
  let stripWidth: Float = 0.003
  let stripScale: Float = 1.2
  let iterateDt: Float = 0.02

  @State var mesh: LowLevelMesh?
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
    let updateFunction = library.makeFunction(name: "updateMovingCubes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateFunction)

  }

  var body: some View {
    GeometryReader3D { proxy in
      RealityView { content in
        let mesh = try! createMesh()

        let modelComponent = try! getModelComponent(mesh: mesh)
        rootEntity.components.set(modelComponent)
        rootEntity.scale = SIMD3(repeating: stripScale)
        rootEntity.position.y = 1
        // rootEntity.position.x = 1.6
        rootEntity.position.z = -1
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
    self.mesh = try! createMesh()  // recreate mesh when start timer
    self.pingPongBuffer = createPingPongBuffer()

    self.vertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * vertexCapacity, options: .storageModeShared)

    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in

      DispatchQueue.main.async {
        if let vertexBuffer = self.vertexBuffer {
          self.updateMesh(vertexBuffer: vertexBuffer)
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

    var unlitMaterial = UnlitMaterial(color: .yellow)
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  func getCubePoints() -> [SIMD3<Float>] {
    var positions: [SIMD3<Float>] = []
    positions.append(SIMD3<Float>(-1, -1, 1))
    positions.append(SIMD3<Float>(1, -1, 1))
    positions.append(SIMD3<Float>(1, -1, -1))
    positions.append(SIMD3<Float>(-1, -1, -1))
    positions.append(SIMD3<Float>(-1, 1, 1))
    positions.append(SIMD3<Float>(1, 1, 1))
    positions.append(SIMD3<Float>(1, 1, -1))
    positions.append(SIMD3<Float>(-1, 1, -1))

    return positions
  }

  let cubeCount: Int = 1

  var vertexCapacity: Int {
    return cubeCount * 8
  }
  var indexCount: Int {
    return cubeCount * 36
  }

  /// Triangle indices for a cube
  var cubeTriangles: [Int] = [
    0, 1, 2, 0, 2, 3,
    4, 5, 6, 4, 6, 7,
    0, 1, 5, 0, 5, 4,
    2, 3, 7, 2, 7, 6,
    0, 3, 7, 0, 7, 4,
    1, 2, 6, 1, 6, 5,
  ]

  func randomPosition(r: Float) -> SIMD3<Float> {
    let x = Float.random(in: -r...r)
    let y = Float.random(in: -r...r)
    let z = Float.random(in: -r...r)
    return SIMD3<Float>(x, y, z)
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<CubeBase>.stride * cubeCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let cubes = contents.bindMemory(to: CubeBase.self, capacity: cubeCount)
    for i in 0..<cubeCount {
      cubes[i] = CubeBase(
        position: randomPosition(r: 1),
        size: Float.random(in: 0.2..<0.8),
        rotate: 0
      )
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

    let cubePoints = getCubePoints()

    let mesh = try LowLevelMesh(descriptor: desc)
    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      let vertices = rawBytes.bindMemory(to: VertexData.self)

      let defaultNormal = SIMD3<Float>(0.7, 0.7, 0.7)

      for (idx, point) in cubePoints.enumerated() {
        vertices[idx] = VertexData(
          position: point * 0.1,
          normal: defaultNormal,
          uv: SIMD2<Float>.zero,
          atSide: false,
          leading: false,
          secondary: false
        )
      }

    }

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<cubeCount {
        for j in 0..<36 {
          indices[i * 36 + j] = UInt32(cubeTriangles[j]) + UInt32(i * 8)
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

    var params = MovingCubesParams(width: stripWidth, dt: iterateDt)
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingCubesParams>.size, index: 2)

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

    // swap buffers
    pingPongBuffer.swap()

    // apply entity with mesh data
    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .lineStrip,
        bounds: getBounds()
      )
    ])
  }
}
