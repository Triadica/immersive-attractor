import Metal
import RealityKit
import SwiftUI

private struct MovingCubesParams {
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
  var position: SIMD3<Float>
  var center: SIMD3<Float>
  var radius: Float
  var angle: Float
}

struct ChordsView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let fps: Double = 120

  @State var timer: Timer?
  @State private var updateTrigger = false

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let cubePipeline: MTLComputePipelineState
  let vertexPipeline: MTLComputePipelineState

  @State var pingPongBuffer: PingPongBuffer?
  /// The vertex buffer for the mesh
  @State var vertexBuffer: MTLBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateCellBase = library.makeFunction(name: "updateChordsBase")!
    self.cubePipeline = try! device.makeComputePipelineState(function: updateCellBase)

    let updateCubeVertexes = library.makeFunction(name: "updateChordsVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateCubeVertexes)
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
          self.updateCellBase()
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

    var unlitMaterial = UnlitMaterial(color: .yellow)
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let cellCount: Int = 600

  let segmentCount: Int = 20

  var vertexCapacity: Int {
    return (segmentCount + 1) * cellCount
  }

  var shapeIndiceCount: Int {
    return segmentCount * 2
  }

  var indexCount: Int {
    return shapeIndiceCount * cellCount
  }

  let PHI: Float = 1.618033988749895
  let PI: Float = 3.141592653589793

  func fiboGridN(n: Float, total: Float) -> SIMD3<Float> {
    let z = (2 * n - 1) / total - 1
    let t = sqrt(1 - z * z)
    let t2 = 2 * PI * PHI * n
    let x = t * cos(t2)
    let y = t * sin(t2)
    return [x, y, z]
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<CellBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()
    let p0 = SIMD3<Float>(x: 0, y: 0.5, z: 0)

    let cells = contents.bindMemory(to: CellBase.self, capacity: cellCount)
    for i in 0..<cellCount {
      let point = fiboGridN(n: Float(i), total: Float(cellCount))
      cells[i] = CellBase(
        position: [point.x, point.z, point.y] * 0.5 + p0,
        center: point,
        radius: 0.1,
        angle: 0.0
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

    let mesh = try LowLevelMesh(descriptor: desc)

    // vertexes are set from compute shader

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<cellCount {
        for j in 0..<shapeIndiceCount {
          let isEven = j % 2 == 0
          let idx = i * shapeIndiceCount + j
          indices[idx] = UInt32(i * (segmentCount + 1)) + UInt32(j / 2)
          if isEven {
          } else {
            indices[idx] += 1
          }
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

  private func getMovingParams() -> MovingCubesParams {
    let delta = -Float(viewStartTime.timeIntervalSinceNow)
    return MovingCubesParams(width: 0.003, dt: 0.02, timestamp: delta)
  }

  func updateCellBase() {
    guard let pingPongBuffer = pingPongBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateMesh: failed to get mesh or pingPongBuffer or commandBuffer or computeEncoder")
      return
    }

    computeEncoder.setComputePipelineState(cubePipeline)

    // idx 0: pingPongBuffer
    computeEncoder.setBuffer(
      pingPongBuffer.currentBuffer, offset: 0, index: 0)

    // idx 1: vertexBuffer
    computeEncoder.setBuffer(pingPongBuffer.nextBuffer, offset: 0, index: 1)

    var params = getMovingParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingCubesParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: cellCount, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 16, height: 1, depth: 1)
    computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    computeEncoder.endEncoding()

    commandBuffer.commit()
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

    // apply entity with mesh data
    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .line,
        bounds: getBounds()
      )
    ])
  }
}
