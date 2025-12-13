import Metal
import RealityKit
import SwiftUI

private struct SphereLineParams {
  var vertexPerCell: Int32
  var dt: Float
  var sphereRadius: Float
  var controlPoint1: SIMD3<Float>
  var controlPoint2: SIMD3<Float>
  var controlPoint3: SIMD3<Float>
  var controlPoint4: SIMD3<Float>
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

/// 球面线段的基础数据结构
private struct SphereLineBase {
  var position: SIMD3<Float>  // 线段起点在球面上的位置
  var size: Float  // 线段长度因子
  var rotate: Float  // 当前旋转角度
}

struct SphereLineView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let fps: Double = 120

  @State var timer: Timer?
  @State private var updateTrigger = false

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let sphereLinePipeline: MTLComputePipelineState
  let vertexPipeline: MTLComputePipelineState

  @State var pingPongBuffer: PingPongBuffer?
  /// The vertex buffer for the mesh
  @State var vertexBuffer: MTLBuffer?
  /// to track previous state of vertex buffer
  @State var vertexPrevBuffer: MTLBuffer?

  // 控制点，用于计算旋转轴
  @State var controlPoint1: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
  @State var controlPoint2: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
  @State var controlPoint3: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
  @State var controlPoint4: SIMD3<Float> = SIMD3<Float>(0, 0, 0)

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateSphereLineBase = library.makeFunction(name: "updateSphereLineBase")!
    self.sphereLinePipeline = try! device.makeComputePipelineState(function: updateSphereLineBase)

    let updateSphereLineVertexes = library.makeFunction(name: "updateSphereLineVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateSphereLineVertexes)
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
                width: bounds.extents.x * 1,
                height: bounds.extents.y * 1,
                depth: bounds.extents.z * 1)
            ]
          ))

        rootEntity.position.y = 1
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

    // 随机生成四个控制点，长度控制在 0.3~0.6 单位范围内
    self.controlPoint1 = randomControlledPosition()
    self.controlPoint2 = randomControlledPosition()
    self.controlPoint3 = randomControlledPosition()
    self.controlPoint4 = randomControlledPosition()

    self.vertexBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * vertexCapacity, options: .storageModeShared)
    self.vertexPrevBuffer = device.makeBuffer(
      length: MemoryLayout<VertexData>.stride * vertexCapacity, options: .storageModeShared)

    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in
      DispatchQueue.main.async {
        if let vertexBuffer = self.vertexBuffer {
          self.updateSphereLineBase()
          self.updateMesh(vertexBuffer: vertexBuffer, prevBuffer: self.vertexPrevBuffer!)

          // Record frame if recording is active
          recordMeshIfActive(mesh: self.mesh, topology: .lines)

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
  }

  /// 生成一个控制大小的随机位置，长度控制在 0.3~0.6 单位范围内
  /// - Returns: 一个长度在 0.3~0.6 范围内的随机位置向量
  func randomControlledPosition() -> SIMD3<Float> {
    // 生成随机方向
    let direction = normalize(randomPosition(r: 1.0))
    // 生成 0.3~0.6 范围内的随机长度
    let length = Float.random(in: 0.3...0.6)
    return direction * length
  }

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    // 梵高《星夜》风格的亮金黄色
    var unlitMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0))
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 0.5  // 球面半径 0.4m 加上一些余量
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let cellCount: Int = 12000  // 减少线段数量以提高性能
  let cellSegment: Int = 32  // 每个线段的顶点数

  var vertexPerCell: Int {
    return cellSegment + 1
  }
  var indicePerCell: Int {
    return cellSegment * 2
  }

  var vertexCapacity: Int {
    return cellCount * vertexPerCell
  }
  var indiceCapacity: Int {
    return cellCount * indicePerCell
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<SphereLineBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    let contents = buffer.currentBuffer.contents()
    let sphereLines = contents.bindMemory(to: SphereLineBase.self, capacity: cellCount)

    for i in 0..<cellCount {
      // 在球面上随机生成起点位置
      let randomDir = normalize(randomPosition(r: 1))
      let spherePosition = randomDir * 0.45  // 半径 0.4m

      sphereLines[i] = SphereLineBase(
        position: spherePosition,
        size: Float.random(in: 0.05..<0.15),  // 线段长度因子
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

  private func getSphereLineParams() -> SphereLineParams {
    return SphereLineParams(
      vertexPerCell: Int32(vertexPerCell),
      dt: 0.016,  // 约60fps的时间步长
      sphereRadius: 0.45,
      controlPoint1: controlPoint1,
      controlPoint2: controlPoint2,
      controlPoint3: controlPoint3,
      controlPoint4: controlPoint4
    )
  }

  func updateSphereLineBase() {
    guard let pingPongBuffer = pingPongBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateSphereLineBase: failed to get pingPongBuffer or commandBuffer or computeEncoder")
      return
    }

    computeEncoder.setComputePipelineState(sphereLinePipeline)

    // idx 0: current buffer
    computeEncoder.setBuffer(
      pingPongBuffer.currentBuffer, offset: 0, index: 0)

    // idx 1: next buffer
    computeEncoder.setBuffer(pingPongBuffer.nextBuffer, offset: 0, index: 1)

    var params = getSphereLineParams()
    // idx 2: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<SphereLineParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: cellCount, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 16, height: 1, depth: 1)
    computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    computeEncoder.endEncoding()
    commandBuffer.commit()
  }

  func updateMesh(vertexBuffer: MTLBuffer, prevBuffer: MTLBuffer) {
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
      prevBuffer.contents().copyMemory(
        from: rawBytes.baseAddress!, byteCount: rawBytes.count)
    }

    computeEncoder.setComputePipelineState(vertexPipeline)

    // idx 0: sphere line base buffer
    computeEncoder.setBuffer(
      pingPongBuffer.currentBuffer, offset: 0, index: 0)

    // idx 1: vertex buffer
    computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 1)

    // idx 2: previous vertex buffer
    computeEncoder.setBuffer(prevBuffer, offset: 0, index: 2)

    var params = getSphereLineParams()
    // idx 3: params buffer
    computeEncoder.setBytes(&params, length: MemoryLayout<SphereLineParams>.size, index: 3)

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
        topology: .line,
        bounds: getBounds()
      )
    ])
  }
}
