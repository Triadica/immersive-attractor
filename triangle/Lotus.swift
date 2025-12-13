import Metal
import RealityKit
import SwiftUI

private struct MovingCellParams {
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
  var seed: Float = 0
}

struct LotusView: View {
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

    let updateVertexes = library.makeFunction(name: "updateLotusVertexes")!
    self.vertexPipeline = try! device.makeComputePipelineState(function: updateVertexes)
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
          self.updateMesh(vertexBuffer: vertexBuffer)

          // Record frame if recording is active
          recordMeshIfActive(mesh: self.mesh, topology: .triangles)
          // no need to swap buffers
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

    var unlitMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.7, blue: 0.7, alpha: 1.0))
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 10
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  let petalCount: Int = 60
  var petalArea: Float {
    Float(petalCount) * 1.5
  }

  let venationSize: Int = 32
  let venationGap: Float = 0.04

  let segmentCount: Int = 40

  var verticesPerStrip: Int {
    return segmentCount + 1
  }

  var cellCount: Int {
    return petalCount * venationSize * verticesPerStrip
  }

  var vertexCapacity: Int {
    return cellCount
  }

  var indicesPerStrip: Int {
    return segmentCount * 2
  }

  var indiceCapacity: Int {
    return petalCount * venationSize * indicesPerStrip
  }

  func createPingPongBuffer() -> PingPongBuffer {
    let bufferSize = MemoryLayout<CellBase>.stride * cellCount
    let buffer = PingPongBuffer(device: device, length: bufferSize)

    // 使用 contents() 前检查 buffer 是否有效
    let contents = buffer.currentBuffer.contents()

    let cells = contents.bindMemory(to: CellBase.self, capacity: cellCount)

    for petalIdx in 0..<petalCount {
      let endPoint = fibonacciGrid(
        n: Float(petalIdx),
        total: Float(petalArea)
      )
      let angle = atan2(endPoint.z, endPoint.x)
      for venationIdx in 0..<venationSize {
        let ve: Float = Float(venationIdx) - Float(venationSize) * 0.5
        let venationAngle = angle + ve * venationGap
        let r0: Float = 0.1
        let yPart: SIMD3<Float> = SIMD3<Float>(0, endPoint.y * 0.2, 0)
        let venationStart =
          SIMD3<Float>(
            r0 * cos(venationAngle),
            0,
            r0 * sin(venationAngle)
          ) + yPart * 0.08
        let p1 = venationStart * 5 + yPart * 0.4
        let p2: SIMD3<Float> = venationStart * 5 + yPart * 0.4
        for segmentIdx in 0...segmentCount {
          let idx =
            petalIdx * venationSize * (segmentCount + 1) + venationIdx * (segmentCount + 1)
            + segmentIdx
          let t = Float(segmentIdx) / Float(segmentCount)
          // let venation = venationStart + (endPoint - venationStart) * t
          let venation: SIMD3<Float> = bezierCurve(
            p0: venationStart, p1: p1, p2: p2, p3: endPoint, t: t)
          cells[idx].position = venation
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

      let size = petalCount * venationSize
      for i in 0..<size {
        for j in 0..<indicesPerStrip {
          let idx = i * indicesPerStrip + j  // for indice location
          let vertexIdxBase = i * verticesPerStrip  // for vertex location
          let even = j % 2 == 0
          let half = j / 2
          if even {
            indices[idx] = UInt32(vertexIdxBase + half)
          } else {
            indices[idx] = UInt32(vertexIdxBase + half + 1)
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
    return MovingCellParams(dt: 0.8 * dt, timestamp: delta)
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
        topology: .line,
        bounds: getBounds()
      )
    ])
  }
}
