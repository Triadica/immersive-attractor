import Metal
import RealityKit
import SwiftUI
import simd

private struct MovingNestParams {
  var width: Float
  var dt: Float
  var timestamp: Float
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

/// placement of a nest
private struct NestBase {
  var position: SIMD3<Float>
  var size: Float
  var noiseValue: Float  // 0~1之间的值，控制线段长度
}

struct NestView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let fps: Double = 120

  @State var timer: Timer?
  @State private var updateTrigger = false

  // MARK: - Controller for gamepad input
  let controllerHelper = ControllerHelper()

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let nestPipeline: MTLComputePipelineState
  let vertexPipeline: MTLComputePipelineState

  @State var pingPongBuffer: PingPongBuffer?
  /// The vertex buffer for the mesh
  @State var vertexBuffer: MTLBuffer?

  // 网格参数：每个维度从-5到5，间隔0.5米
  // 为了性能考虑，使用20x20x20的网格密度
  // 每个立方体中心点有7条线段（3条轴向 + 4条对角线）穿过中心
  let gridDensity: Int = 20  // 进一步降低到20以提高性能
  let gridSpacing: Float = 0.5  // 相应调整间距
  let gridMin: Float = -5.0

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateNestBase = library.makeFunction(name: "updateNestBase")!
    self.nestPipeline = try! device.makeComputePipelineState(function: updateNestBase)

    let updateNestVertexes = library.makeFunction(name: "updateNestVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateNestVertexes)
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
        // Controller: rootEntity.components.set(GestureComponent())
        // Controller: rootEntity.components.set(InputTargetComponent())
        // Adjust collision box size to match actual content
        // Controller: let bounds = getBounds()

        // Controller: rootEntity.components.set(

        // Controller: CollisionComponent(

        // Controller: shapes: [

        // Controller: .generateBox(

        // Controller: width: bounds.extents.x * 4,

        // Controller: height: bounds.extents.y * 4,

        // Controller: depth: bounds.extents.z * 4)

        // Controller: ]

        // Controller: ))

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
      // Controller: .gesture(
      // Controller: DragGesture()
      // Controller: .targetedToEntity(rootEntity)
      // Controller: .onChanged { value in
      // Controller: var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
      // Controller: component.onDragChange(value: value)
      // Controller: rootEntity.components[GestureComponent.self] = component
      // Controller: }
      // Controller: .onEnded { _ in
      // Controller: var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
      // Controller: component.onGestureEnded()
      // Controller: rootEntity.components[GestureComponent.self] = component
      // Controller: }
      // Controller: )
      // Controller: .gesture(
      // Controller: RotateGesture3D()
      // Controller: .targetedToEntity(rootEntity)
      // Controller: .onChanged { value in

      // Controller: var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
      // Controller: component.onRotateChange(value: value)
      // Controller: rootEntity.components[GestureComponent.self] = component
      // Controller: }
      // Controller: .onEnded { _ in
      // Controller: var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
      // Controller: component.onGestureEnded()
      // Controller: rootEntity.components[GestureComponent.self] = component
      // Controller: }
      // Controller: )
      // Controller: .simultaneousGesture(
      // Controller: MagnifyGesture()
      // Controller: .targetedToEntity(rootEntity)
      // Controller: .onChanged { value in
      // Controller: var component = rootEntity.components[GestureComponent.self] ?? GestureComponent()
      // Controller: component.onScaleChange(value: value)
      // Controller: rootEntity.components[GestureComponent.self] = component
      // Controller: }
      // Controller: .onEnded { _ in
      // Controller: var component: GestureComponent =
      // Controller: rootEntity.components[GestureComponent.self] ?? GestureComponent()
      // Controller: component.onGestureEnded()
      // Controller: rootEntity.components[GestureComponent.self] = component
      // Controller: }
      // Controller: )
    }
  }

  func startTimer() {
    self.mesh = try! createMesh()
    controllerHelper.reset()  // Reset controller timing  // recreate mesh when start timer
    self.pingPongBuffer = createPingPongBuffer()

    self.vertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * vertexCapacity, options: .storageModeShared)

    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in

      DispatchQueue.main.async {
        if let vertexBuffer = self.vertexBuffer {
          self.updateNestBase()
          self.updateMesh(vertexBuffer: vertexBuffer)

          // swap buffers
          self.pingPongBuffer!.swap()
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
    let radius: Float = 6  // 扩大边界框以容纳新的网格范围
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  var nestCount: Int {
    return gridDensity * gridDensity * gridDensity  // 20^3 = 8,000
  }

  var vertexCapacity: Int {
    return nestCount * 14  // 每个立方体7条线段，每条线段2个顶点
  }

  /// Line indices for a cube with 7 lines (3 axis + 4 diagonals through center)
  /// Each line has 2 vertices, so 14 vertices total per cube
  var nestLines: [Int] = [
    // 3 axis lines through center
    0, 1,  // X axis: left to right
    2, 3,  // Y axis: bottom to top
    4, 5,  // Z axis: back to front
    // 4 diagonal lines through center
    6, 7,  // diagonal 1
    8, 9,  // diagonal 2
    10, 11,  // diagonal 3
    12, 13,  // diagonal 4
  ]

  var shapeIndiceCount: Int {
    return nestLines.count  // 14 indices for 7 lines
  }

  var indexCount: Int {
    return nestCount * shapeIndiceCount
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<NestBase>.stride * nestCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let nests = contents.bindMemory(to: NestBase.self, capacity: nestCount)

    // 生成网格分布的中心点
    var index = 0
    for x in 0..<gridDensity {
      for y in 0..<gridDensity {
        for z in 0..<gridDensity {
          let position = SIMD3<Float>(
            gridMin + Float(x) * gridSpacing,
            gridMin + Float(y) * gridSpacing,
            gridMin + Float(z) * gridSpacing
          )
          nests[index] = NestBase(
            position: position,
            size: 0.05,  // 统一的小尺寸
            noiseValue: 0.0  // 初始值，会在Metal shader中计算
          )
          index += 1
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
    desc.indexCapacity = indexCount

    let mesh = try LowLevelMesh(descriptor: desc)

    // vertexes are set from compute shader

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<nestCount {
        for j in 0..<shapeIndiceCount {
          indices[i * shapeIndiceCount + j] = UInt32(nestLines[j]) + UInt32(i * 14)
        }
      }

    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .line,  // 使用线条而不是线带
        bounds: getBounds()
      )
    ])

    return mesh
  }

  @State private var viewStartTime: Date = Date()
  @State private var frameDelta: Float = 0.0

  private func getMovingParams() -> MovingNestParams {
    let delta = -Float(viewStartTime.timeIntervalSinceNow)
    let dt = delta - frameDelta
    frameDelta = delta
    return MovingNestParams(width: 0.03, dt: 0.8 * dt, timestamp: delta)
  }

  func updateNestBase() {
    guard let pingPongBuffer = pingPongBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateMesh: failed to get mesh or pingPongBuffer or commandBuffer or computeEncoder")
      return
    }

    computeEncoder.setComputePipelineState(nestPipeline)

    // idx 0: pingPongBuffer
    computeEncoder.setBuffer(
      pingPongBuffer.currentBuffer, offset: 0, index: 0)

    // idx 1: vertexBuffer
    computeEncoder.setBuffer(pingPongBuffer.nextBuffer, offset: 0, index: 1)

    var params = getMovingParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingNestParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: nestCount, height: 1, depth: 1)
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
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingNestParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: vertexCapacity, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 32, height: 1, depth: 1)  // 减小线程组大小以适应更大的工作量
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
