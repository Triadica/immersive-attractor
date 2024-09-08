import Metal
import RealityKit
import SwiftUI

struct MovingLorenzView: View {
  let rootEntity: Entity = Entity()
  let latitudeBands: Int = 32
  let longitudeBands: Int = 32
  /** 3 dimentions to control size */
  let altitudeBands: Int = 32
  /** how many segments in each strip */
  let stripSize: Int = 8
  let stripWidth: Float = 0.2
  let stripScale: Float = 0.002
  let iterateDt: Float = 0.0001
  let fps: Double = 90
  let gridWidth: Float = 4

  var vertexCapacity: Int {
    return latitudeBands * longitudeBands * altitudeBands * stripSize * 4
  }
  var indexCount: Int {
    return latitudeBands * longitudeBands * altitudeBands * stripSize * 6
  }

  @State var mesh: LowLevelMesh?
  @State var timer: Timer?

  @State private var updateTrigger = false

  let radius: Float = 100

  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let computePipeline: MTLComputePipelineState
  @State var pingPongBuffer: PingPongBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateFunction = library.makeFunction(name: "updateMovingLorenz")!
    self.computePipeline = try! device.makeComputePipelineState(function: updateFunction)
  }

  var body: some View {
    GeometryReader3D { proxy in
      RealityView { content in
        // let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene).extents
        // let radius = Float(0.5 * size.x)

        self.pingPongBuffer = PingPongBuffer(
          device: device, length: MemoryLayout<VertexData>.stride * vertexCapacity)
        let mesh = try! createMesh()

        let modelComponent = try! getModelComponent(mesh: mesh)
        rootEntity.components.set(modelComponent)
        rootEntity.scale *= stripScale
        content.add(rootEntity)
        // self.radius = radius
        self.mesh = mesh

        let pointLight = PointLight()
        pointLight.light.intensity = 5000
        pointLight.light.color = UIColor.yellow
        pointLight.light.attenuationRadius = 20
        pointLight.position = SIMD3<Float>(0.5, 0.2, 0.4)

        let pointLight2 = PointLight()
        pointLight2.light.intensity = 5000
        pointLight2.light.color = UIColor.yellow
        pointLight2.light.attenuationRadius = 20
        pointLight2.position = SIMD3<Float>(-0.5, 0.2, 0.4)

        content.add(pointLight)

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
    timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in

      DispatchQueue.main.async {
        self.updateMesh()
        self.updateTrigger.toggle()
      }

    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = .white  //.init(white: 0.05, alpha: 1.0)
    material.roughness.scale = 0.9
    material.metallic.scale = 0.1
    // material.blending = .transparent(opacity: 1.0)
    material.blending = .opaque
    material.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [material])
  }

  func createMesh() throws -> LowLevelMesh {
    var desc = VertexData.descriptor
    desc.vertexCapacity = vertexCapacity
    desc.indexCapacity = indexCount

    let mesh = try LowLevelMesh(descriptor: desc)
    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      let vertices = rawBytes.bindMemory(to: VertexData.self)

      for x in 0..<latitudeBands {
        for y in 0..<longitudeBands {
          for z in 0..<altitudeBands {

            var base = SIMD3<Float>(
              gridWidth * Float(x - latitudeBands / 2),
              gridWidth * Float(y - longitudeBands / 2),
              -gridWidth * Float(z - altitudeBands / 2))
            let gridBase = (x * latitudeBands + y) * longitudeBands + z

            // each strip has `stripSize` points, and each point has 4 vertices, and using 6 indices to draw a strip
            for i in 0..<stripSize {
              let vertexBase = (gridBase * stripSize + i) * 4

              // let p = fourwingIteration(p: base, dt: 0.04)
              // let p = fakeIteration(p: base, dt: 0.04)

              vertices[vertexBase] = VertexData(
                position: base + SIMD3<Float>(0, 0, 0),
                normal: SIMD3<Float>(0, 0.7, 0.7),
                uv: SIMD2<Float>.zero,
                atSide: false,
                leading: i == 0,
                secondary: false
                  // originalPosition: base,
              )
              vertices[vertexBase + 1] = VertexData(
                position: base + SIMD3<Float>(stripWidth, 0, 0),
                normal: SIMD3<Float>(0, 0.7, 0.7),
                uv: SIMD2<Float>.zero,
                atSide: true,
                leading: i == 0,
                secondary: false
                  // originalPosition: base,
              )

              vertices[vertexBase + 2] = VertexData(
                position: base + SIMD3<Float>(0, 0, 0),
                normal: SIMD3<Float>(0, 0.7, 0.7),
                uv: SIMD2<Float>.zero,
                atSide: false,
                leading: i == 0,
                secondary: true
                  // originalPosition: p,
              )
              vertices[vertexBase + 3] = VertexData(
                position: base + SIMD3<Float>(stripWidth, 0, 0),
                normal: SIMD3<Float>(0, 0.7, 0.7),
                uv: SIMD2<Float>.zero,
                atSide: true,
                leading: i == 0,
                secondary: true
                  // originalPosition: p,

              )

              // base = p
            }

          }

        }
      }

    }

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for x in 0..<latitudeBands {
        for y in 0..<longitudeBands {
          for z in 0..<altitudeBands {
            let gridBase = (x * latitudeBands + y) * longitudeBands + z

            for i in 0..<stripSize {
              // each segment has 4 vertices, and 6 indices to draw a strip
              let segmentBase = (gridBase * stripSize + i) * 6
              let vertexBase = UInt32((gridBase * stripSize + i) * 4)
              indices[segmentBase + 0] = vertexBase
              indices[segmentBase + 1] = vertexBase + 1
              indices[segmentBase + 2] = vertexBase + 2
              indices[segmentBase + 3] = vertexBase + 2
              indices[segmentBase + 4] = vertexBase + 1
              indices[segmentBase + 5] = vertexBase + 3
            }
          }
        }
      }
    }

    let meshBounds = BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .triangle,
        bounds: meshBounds
      )
    ])
    if let pingPongBuffer = pingPongBuffer {
      mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
        pingPongBuffer.currentBuffer.contents().copyMemory(
          from: rawBytes.baseAddress!, byteCount: rawBytes.count)
      }
    }
    return mesh
  }

  func updateMesh() {
    guard let mesh = mesh,
      let pingPongBuffer = pingPongBuffer,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else {
      print("updateMesh: failed to get mesh or pingPongBuffer or commandBuffer or computeEncoder")
      return
    }

    computeEncoder.setComputePipelineState(computePipeline)
    computeEncoder.setBuffer(pingPongBuffer.currentBuffer, offset: 0, index: 0)
    computeEncoder.setBuffer(pingPongBuffer.nextBuffer, offset: 0, index: 1)

    var params = MovingLorenzParams(width: stripWidth, dt: iterateDt)
    computeEncoder.setBytes(&params, length: MemoryLayout<MovingLorenzParams>.size, index: 2)

    let threadsPerGrid = MTLSize(width: vertexCapacity, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)

    computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    computeEncoder.endEncoding()

    // copy data from next buffer to mesh
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.copy(
      from: pingPongBuffer.nextBuffer, sourceOffset: 0,
      to: mesh.replace(bufferIndex: 0, using: commandBuffer), destinationOffset: 0,
      size: pingPongBuffer.nextBuffer.length)
    blitEncoder.endEncoding()

    commandBuffer.commit()

    // swap buffers
    pingPongBuffer.swap()

    let meshBounds = BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .triangle,
        bounds: meshBounds
      )
    ])
  }

  struct VertexData {
    var position: SIMD3<Float> = .zero
    var normal: SIMD3<Float> = .zero
    var uv: SIMD2<Float> = .zero
    var atSide: Bool = false
    var leading: Bool = false
    var secondary: Bool = false
    // var originalPosition: SIMD3<Float> = .zero

    @MainActor static var vertexAttributes: [LowLevelMesh.Attribute] = [
      .init(
        semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
      .init(semantic: .normal, format: .float3, offset: MemoryLayout<Self>.offset(of: \.normal)!),
      .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Self>.offset(of: \.uv)!),
      // .init(
      //   semantic: .unspecified, format: .float3,
      //   offset: MemoryLayout<Self>
      //     .offset(of: \.originalPosition)!),
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

  struct MovingLorenzParams {
    var width: Float
    var dt: Float
  }

  private func fakeIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
    let d = SIMD3<Float>(0.1, 0.1, -0.1) * dt
    return p + d
  }

  func lorenzIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
    let tau: Float = 10.0
    let rou: Float = 28.0
    let beta: Float = 8.0 / 3.0

    let dx = tau * (p.y - p.x)
    let dy = p.x * (rou - p.z) - p.y
    let dz = p.x * p.y - beta * p.z
    let d = SIMD3<Float>(dx, dy, dz) * dt
    return p + d
  }

  func fourwingIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
    let a: Float = 0.2
    let b: Float = 0.01
    let c: Float = -0.4
    let x = p.x
    let y = p.y
    let z = p.z
    let dx = a * x + y * z
    let dy = b * x + c * y - x * z
    let dz = -z - x * y
    let d = SIMD3<Float>(dx, dy, dz) * dt
    return p + d
  }
}

class PingPongBuffer {
  let bufferA: MTLBuffer
  let bufferB: MTLBuffer
  var currentBuffer: MTLBuffer
  var nextBuffer: MTLBuffer

  init(device: MTLDevice, length: Int) {
    bufferA = device.makeBuffer(length: length, options: .storageModeShared)!
    bufferB = device.makeBuffer(length: length, options: .storageModeShared)!
    currentBuffer = bufferA
    nextBuffer = bufferB
  }

  func swap() {
    (currentBuffer, nextBuffer) = (nextBuffer, currentBuffer)
  }
}
