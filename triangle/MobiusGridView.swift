import Metal
import RealityKit
import SwiftUI

private struct MovingCellParams {
  var vertexPerCell: Int32
  var dt: Float
  var timestamp: Float = 0
}

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

/// placement of a cube
private struct CellBase {
  var position: SIMD3<Float> = .zero
  var index: Float
}

struct MobiusGirdView: View {
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
  /// to track previous state of vertex buffer
  @State var vertexPrevBuffer: MTLBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!

    let updatelinesVertexes = library.makeFunction(name: "updateMobiusGridVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updatelinesVertexes)
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
        // rootEntity.position.z = -2
        // rootEntity.position.x = 1.6
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

    var unlitMaterial = UnlitMaterial(color: .systemPink)
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let gridSize: Int = 40

  var cellCount: Int {
    return gridSize * gridSize * gridSize * 3
  }

  let cellSegment: Int = 4

  var vertexPerCell: Int {
    return cellSegment + 1
  }
  var vertexCapacity: Int {
    return cellCount * vertexPerCell
  }

  var indicePerCell: Int {
    return cellSegment * 2
  }
  var indiceCapacity: Int {
    return cellCount * indicePerCell
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<CellBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let cells = contents.bindMemory(to: CellBase.self, capacity: cellCount)

    let cellLength = Float(1)

    for xi in 0..<gridSize {
      for yi in 0..<gridSize {
        for zi in 0..<gridSize {
          let x = Float(xi) / Float(gridSize) * 2 - 1
          let y = Float(yi) / Float(gridSize) * 2 - 1
          let z = Float(zi) / Float(gridSize) * 2 - 1
          let pos = SIMD3<Float>(x, y, z) * cellLength

          let index = xi * gridSize * gridSize + yi * gridSize + zi * 3 * vertexPerCell
          // create 3 branches in each direction

          var cellIdx = index
          for i in 0..<vertexPerCell {
            let dx = Float(i) / Float(cellSegment) * cellLength
            cells[cellIdx] = CellBase(
              position: pos + SIMD3<Float>(dx * Float(i), 0, 0),
              index: Float(cellIdx)
            )
            cellIdx += 1
          }
          for i in 0..<vertexPerCell {
            let dy = Float(i) / Float(cellSegment) * cellLength
            cells[cellIdx] = CellBase(
              position: pos + SIMD3<Float>(0, dy * Float(i), 0),
              index: Float(cellIdx)
            )
            cellIdx += 1
          }
          for i in 0..<vertexPerCell {
            let dz = Float(i) / Float(cellSegment) * cellLength
            cells[cellIdx] = CellBase(
              position: pos + SIMD3<Float>(0, 0, dz * Float(i)),
              index: Float(cellIdx)
            )
            cellIdx += 1
          }
        }
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
    desc.indexCapacity = indiceCapacity

    let mesh = try LowLevelMesh(descriptor: desc)

    // vertexes are set from compute shader

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<cellCount {
        for j in 0..<indicePerCell {
          let is_even = j % 2 == 0
          let half = j / 2
          if is_even {
            indices[i * indicePerCell + j] = UInt32(i * vertexPerCell + half)
          } else {
            indices[i * indicePerCell + j] = UInt32(i * vertexPerCell + half + 1)
          }
        }
      }

    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indiceCapacity,
        topology: .lineStrip,
        bounds: getBounds()
      )
    ])

    return mesh
  }

  @State private var viewStartTime: Date = Date()
  @State private var frameDelta: Float = 0.0

  private func getMovingParams() -> MovingCellParams {
    let delta = -Float(viewStartTime.timeIntervalSinceNow)
    let dt = delta - frameDelta
    frameDelta = delta
    return MovingCellParams(vertexPerCell: Int32(vertexPerCell), dt: 0.8 * dt, timestamp: delta)
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
    // idx 3: params buffer
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
        indexCount: indiceCapacity,
        topology: .lineStrip,
        bounds: getBounds()
      )
    ])
  }
}
