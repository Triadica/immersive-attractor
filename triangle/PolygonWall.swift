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
  var position: SIMD3<Float>
  var size: Float
  var rotate: Float
}

struct PolygonWallView: View {
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
    let updateCellBase = library.makeFunction(name: "updatePolygonWallBase")!
    self.cubePipeline = try! device.makeComputePipelineState(function: updateCellBase)

    let updateCellVertexes = library.makeFunction(name: "updatePolygonWallVertexes")!
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
        rootEntity.components.set(modelComponent)
        // Add components for gesture support
        rootEntity.components.set(GestureComponent())
        rootEntity.components.set(InputTargetComponent())
        // Adjust collision box size to match actual content
        let bounds = getBounds()
        rootEntity.components.set(
          CollisionComponent(
            shapes: [
              .generateBox(
                width: bounds.extents.x * 4,
                height: bounds.extents.y * 4,
                depth: bounds.extents.z * 4)
            ]
          ))

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
      .gesture(
        DragGesture()
          .targetedToEntity(rootEntity)
          .onChanged { value in
            var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
            component.onDragChange(value: value)
            rootEntity.components[GestureComponent.self] = component
          }
          .onEnded { _ in
            var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
            component.onGestureEnded()
            rootEntity.components[GestureComponent.self] = component
          }
      )
      .gesture(
        RotateGesture3D()
          .targetedToEntity(rootEntity)
          .onChanged { value in

            var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
            component.onRotateChange(value: value)
            rootEntity.components[GestureComponent.self] = component
          }
          .onEnded { _ in
            var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
            component.onGestureEnded()
            rootEntity.components[GestureComponent.self] = component
          }
      )
      .simultaneousGesture(
        MagnifyGesture()
          .targetedToEntity(rootEntity)
          .onChanged { value in
            var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
            component.onScaleChange(value: value)
            rootEntity.components[GestureComponent.self] = component
          }
          .onEnded { _ in
            var component: GestureComponent =
              rootEntity.components[GestureComponent.self] ?? GestureComponent()
            component.onGestureEnded()
            rootEntity.components[GestureComponent.self] = component
          }
      )
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

    var unlitMaterial = UnlitMaterial(color: .white)
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let cellCount: Int = 600

  var vertexCapacity: Int {
    return cellCount * 4
  }

  var cubeFrame: [Int] = [
    0, 1, 1, 2, 2, 3, 3, 0,
  ]

  var shapeIndiceCount: Int {
    return cubeFrame.count
  }

  var indexCount: Int {
    return cellCount * shapeIndiceCount
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<CellBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let cubes = contents.bindMemory(to: CellBase.self, capacity: cellCount)
    var acc = 0.1
    var acc2 = -0.1
    for i in 0..<cellCount {
      acc += 0.02
      acc2 += 0.002
      cubes[i] = CellBase(
        position: SIMD3(0, 0, 0),
        size: Float(acc),
        rotate: Float(acc2)
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
          indices[i * shapeIndiceCount + j] = UInt32(cubeFrame[j]) + UInt32(i * 8)
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
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingCellParams>.size, index: 2)

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
        topology: .line,
        bounds: getBounds()
      )
    ])
  }
}
