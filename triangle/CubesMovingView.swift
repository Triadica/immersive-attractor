//
//  CubesView.swift
//  triangle
//
//  Created by chen on 2025/2/6.
//

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
  let computePipeline: MTLComputePipelineState
  @State var pingPongBuffer: PingPongBuffer?

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

    let library = device.makeDefaultLibrary()!
    let updateFunction = library.makeFunction(name: "updateMovingCubes")!
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

  var vertexCapacity: Int {
    return 8
  }
  var indexCount: Int {
    return 36
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
          position: point * 0.2,
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

      // bottom triangles
      indices[0] = 0
      indices[1] = 1
      indices[2] = 2
      indices[3] = 0
      indices[4] = 2
      indices[5] = 3
      // top triangles
      indices[6] = 4
      indices[7] = 5
      indices[8] = 6
      indices[9] = 4
      indices[10] = 6
      indices[11] = 7
      // near triangles
      indices[12] = 0
      indices[13] = 1
      indices[14] = 5
      indices[15] = 0
      indices[16] = 5
      indices[17] = 4
      // far triangles
      indices[18] = 2
      indices[19] = 3
      indices[20] = 7
      indices[21] = 2
      indices[22] = 7
      indices[23] = 6
      // left triangles
      indices[24] = 0
      indices[25] = 3
      indices[26] = 7
      indices[27] = 0
      indices[28] = 7
      indices[29] = 4
      // right triangles
      indices[30] = 1
      indices[31] = 2
      indices[32] = 6
      indices[33] = 1
      indices[34] = 6
      indices[35] = 5
    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: indexCount,
        topology: .triangle,
        bounds: getBounds()
      )
    ])
    if let pingPongBuffer = pingPongBuffer {
      // copy data from mesh to current buffer
      mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
        pingPongBuffer.currentBuffer.contents().copyMemory(
          from: rawBytes.baseAddress!, byteCount: rawBytes.count)
      }
    }
    return mesh
  }

  func updateMesh() {
    // guard let mesh = mesh,
    //   let pingPongBuffer = pingPongBuffer,
    //   let commandBuffer = commandQueue.makeCommandBuffer(),
    //   let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    // else {
    //   print("updateMesh: failed to get mesh or pingPongBuffer or commandBuffer or computeEncoder")
    //   return
    // }

    // computeEncoder.setComputePipelineState(computePipeline)
    // computeEncoder.setBuffer(pingPongBuffer.currentBuffer, offset: 0, index: 0)
    // computeEncoder.setBuffer(pingPongBuffer.nextBuffer, offset: 0, index: 1)

    // var params = MovingCubesParams(width: stripWidth, dt: iterateDt)
    // computeEncoder.setBytes(&params, length: MemoryLayout<MovingCubesParams>.size, index: 2)

    // let threadsPerGrid = MTLSize(width: vertexCapacity, height: 1, depth: 1)
    // let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)

    // computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    // computeEncoder.endEncoding()

    // // copy data from next buffer to mesh
    // let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    // blitEncoder.copy(
    //   from: pingPongBuffer.nextBuffer, sourceOffset: 0,
    //   to: mesh.replace(bufferIndex: 0, using: commandBuffer), destinationOffset: 0,
    //   size: pingPongBuffer.nextBuffer.length)
    // blitEncoder.endEncoding()

    // commandBuffer.commit()

    // // swap buffers
    // pingPongBuffer.swap()

    // mesh.parts.replaceAll([
    //   LowLevelMesh.Part(
    //     indexCount: indexCount,
    //     topology: .triangle,
    //     bounds: getBounds()
    //   )
    // ])
  }
}
