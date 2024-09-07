import SwiftUI
import RealityKit
import Metal

struct MorphingSphereMetalView: View {
  let rootEntity: Entity = Entity()
  let latitudeBands = 120
  let longitudeBands = 120
  var vertexCapacity: Int {
    return (latitudeBands + 1) * (longitudeBands + 1)
  }
  var indexCount: Int {
    return latitudeBands * longitudeBands * 6
  }
  
  @State var mesh: LowLevelMesh?
  @State var isMorphForward: Bool = true
  @State var morphAmount: Float = 0.0
  @State var morphPhase: Float = 0.0
  @State var timer: Timer?
  @State var frameDuration: TimeInterval = 0.0
  @State var lastUpdateTime = CACurrentMediaTime()
  @State var rotationAngles: SIMD3<Float> = [0, 0, 0]
  @State var time: Double = 0.0
  @State var lastRotationUpdateTime = CACurrentMediaTime()
  @State var radius: Float = 0.1
  
  let device: MTLDevice
  let commandQueue: MTLCommandQueue
  let computePipeline: MTLComputePipelineState
  
  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!
    
    let library = device.makeDefaultLibrary()!
    let updateFunction = library.makeFunction(name: "updateMorphingSphere")!
    self.computePipeline = try! device.makeComputePipelineState(function: updateFunction)
  }
  
  var body: some View {
    GeometryReader3D { proxy in
      RealityView { content in
        let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene).extents
        let radius = Float(0.5 * size.x)
        let mesh = try! createMesh()
        let modelComponent = try! getModelComponent(mesh: mesh)
        rootEntity.components.set(modelComponent)
//        rootEntity.scale *= scalePreviewFactor
        content.add(rootEntity)
        self.radius = radius
        self.mesh = mesh
      }
      .onAppear { startTimer() }
      .onDisappear { stopTimer() }
    }
  }
  
  func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1/120.0, repeats: true) { _ in
      DispatchQueue.main.async {
        let currentTime = CACurrentMediaTime()
        frameDuration = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        morphPhase = morphPhase + Float(frameDuration * 0.1)
        updateMesh()
        stepMorphAmount()
        stepRotationAndScale()
      }
    }
  }
  
  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }
  
  func stepMorphAmount() {
    if isMorphForward {
      morphAmount += 0.125
      if morphAmount >= 5.0 {
        isMorphForward = false
      }
    } else {
      morphAmount -= 0.01
      if morphAmount <= 0.0 {
        isMorphForward = true
      }
    }
  }
  
  func stepRotationAndScale() {
    let currentTime = CACurrentMediaTime()
    let frameDuration = currentTime - lastRotationUpdateTime
    
    rotationAngles.x += Float(frameDuration * 1.0)
    rotationAngles.y += Float(frameDuration * 0.0)
    rotationAngles.z += Float(frameDuration * 0.25)
    
    let rotationX = simd_quatf(angle: rotationAngles.x, axis: [1, 0, 0])
    let rotationY = simd_quatf(angle: rotationAngles.y, axis: [0, 1, 0])
    let rotationZ = simd_quatf(angle: rotationAngles.z, axis: [0, 0, 1])
    rootEntity.transform.rotation = rotationX * rotationY * rotationZ
    
    lastRotationUpdateTime = currentTime
  }
  
  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)
    
    var material = PhysicallyBasedMaterial()
    material.baseColor.tint = .orange //.init(white: 0.05, alpha: 1.0)
    material.roughness.scale = 0.5
    material.metallic.scale = 1.0
    material.blending = .transparent(opacity: 1.0)
    material.faceCulling = .none
    
    return ModelComponent(mesh: resource, materials: [material])
  }
  
  func createMesh() throws -> LowLevelMesh {
    var desc = VertexData.descriptor
    desc.vertexCapacity = vertexCapacity
    desc.indexCapacity = indexCount
    
    let mesh = try LowLevelMesh(descriptor: desc)
    
    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)
      var index = 0
      
      for latNumber in 0..<latitudeBands {
        for longNumber in 0..<longitudeBands {
          let first = (latNumber * (longitudeBands + 1)) + longNumber
          let second = first + longitudeBands + 1
          
          indices[index] = UInt32(first)
          indices[index + 1] = UInt32(second)
          indices[index + 2] = UInt32(first + 1)
          
          indices[index + 3] = UInt32(second)
          indices[index + 4] = UInt32(second + 1)
          indices[index + 5] = UInt32(first + 1)
          
          index += 6
        }
      }
    }
    
    return mesh
  }
  
  func updateMesh() {
    guard let mesh = mesh,
          let commandBuffer = commandQueue.makeCommandBuffer(),
          let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
    
    let vertexBuffer = mesh.replace(bufferIndex: 0, using: commandBuffer)
    
    computeEncoder.setComputePipelineState(computePipeline)
    computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
    
    var params = MorphingSphereParams(
      latitudeBands: Int32(latitudeBands),
      longitudeBands: Int32(longitudeBands),
      radius: radius,
      morphAmount: morphAmount,
      morphPhase: morphPhase
    )
    computeEncoder.setBytes(&params, length: MemoryLayout<MorphingSphereParams>.size, index: 1)
    
    let threadsPerGrid = MTLSize(width: vertexCapacity, height: 1, depth: 1)
    let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
    computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    
    computeEncoder.endEncoding()
    commandBuffer.commit()
    
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
    
    @MainActor static var vertexAttributes: [LowLevelMesh.Attribute] = [
      .init(semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
      .init(semantic: .normal, format: .float3, offset: MemoryLayout<Self>.offset(of: \.normal)!),
      .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Self>.offset(of: \.uv)!)
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
  
  struct MorphingSphereParams {
    var latitudeBands: Int32
    var longitudeBands: Int32
    var radius: Float
    var morphAmount: Float
    var morphPhase: Float
  }
}

#Preview {
  MorphingSphereMetalView()
}
