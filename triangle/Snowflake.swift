import Metal
import RealityKit
import SwiftUI

private struct MovingSnowflakeParams {
  var width: Float
  var dt: Float
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
private struct SnowflakeBase {
  var position: SIMD3<Float>
  var size: Float
  var axis: SIMD3<Float> = .zero
  var rotate: Float
  var velocity: SIMD3<Float> = .zero
}

struct SnowflakeView: View {
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
    let updateSnowflakeBase = library.makeFunction(name: "updateSnowflakeBase")!
    self.cubePipeline = try! device.makeComputePipelineState(function: updateSnowflakeBase)

    let updateVertexes = library.makeFunction(name: "updateSnowflakeVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateVertexes)
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
          self.updateCellsBase()
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

    var unlitMaterial = UnlitMaterial(
      color: UIColor(Color(red: 0.85, green: 0.95, blue: 0.98, opacity: 0.4)),
    )
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 2
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let cellCount: Int = 4000

  let vertexesPerCell: Int = 36

  var vertexCapacity: Int {
    return cellCount * vertexesPerCell
  }

  let shapeIndiceCount: Int = 36

  var indexCount: Int {
    return cellCount * shapeIndiceCount
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<SnowflakeBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let cubes = contents.bindMemory(to: SnowflakeBase.self, capacity: cellCount)
    for i in 0..<cellCount {
      var velocity = randomPosition(r: 0.3)
      // velocity.y = Float.random(in: (-1.2)..<(-1.0))
      velocity.y = -1.0
      cubes[i] = SnowflakeBase(
        position: randomPosition(r: 16),
        size: Float.random(in: 0.2..<0.4),
        axis: normalize(randomPosition(r: 1)),
        rotate: 0,
        velocity: velocity,
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

    // vertexes are set from vertex shader

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<(cellCount * shapeIndiceCount) {
        indices[i] = UInt32(i)
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

  private func getMovingParams() -> MovingSnowflakeParams {
    return MovingSnowflakeParams(width: 0.003, dt: 0.02)
  }

  func updateCellsBase() {
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
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingSnowflakeParams>.size, index: 2)

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
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingSnowflakeParams>.size, index: 2)

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
