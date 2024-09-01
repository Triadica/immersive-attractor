import SwiftUI
import RealityKit
import Metal

struct MorphingSphereMetalView: View {
    let rootEntity: Entity = Entity()
    let latitudeBands = 1000
    let longitudeBands = 1000
    var vertexCapacity: Int {
        return latitudeBands * longitudeBands
    }
    var indexCount: Int {
        return latitudeBands * longitudeBands
    }

    @State var mesh: LowLevelMesh?
    @State var isMorphForward: Bool = true
    @State var morphAmount: Float = 0.0
    @State var morphPhase: Float = 0.0
    @State var timer: Timer?
    @MainActor @State var frameDuration: TimeInterval = 0.0
    @State var lastUpdateTime = CACurrentMediaTime()
    @State var rotationAngles: SIMD3<Float> = [0, 0, 0]
    @State var time: Double = 0.0
    @State var lastRotationUpdateTime = CACurrentMediaTime()
    @State var radius: Float = 100

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
//                 let mesh = try! triangleMesh()
                
                let modelComponent = try! getModelComponent(mesh: mesh)
                rootEntity.components.set(modelComponent)
                // rootEntity.scale *= scalePreviewFactor
                content.add(rootEntity)
                self.radius = radius
                self.mesh = mesh
            }
//            .onAppear { startTimer() }
//            .onDisappear { stopTimer() }
        }
    }

    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1/120.0, repeats: true) { _ in
            let currentTime = CACurrentMediaTime()

            DispatchQueue.main.async {
                frameDuration = currentTime - lastUpdateTime
                lastUpdateTime = currentTime
                morphPhase = morphPhase + Float(frameDuration * 0.1)
                self.updateMesh()
                self.stepMorphAmount()
                self.stepRotationAndScale()
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

//        rotationAngles.x += Float(frameDuration * 1.0)
//        rotationAngles.y += Float(frameDuration * 0.0)
//        rotationAngles.z += Float(frameDuration * 0.25)
//
//        let rotationX = simd_quatf(angle: rotationAngles.x, axis: [1, 0, 0])
//        let rotationY = simd_quatf(angle: rotationAngles.y, axis: [0, 1, 0])
//        let rotationZ = simd_quatf(angle: rotationAngles.z, axis: [0, 0, 1])
//        rootEntity.transform.rotation = rotationX * rotationY * rotationZ

        lastRotationUpdateTime = currentTime
    }

    func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
        let resource = try MeshResource(from: mesh)

        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = .white //.init(white: 0.05, alpha: 1.0)
        material.roughness.scale = 1.0
        material.metallic.scale = 0.2
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none

        return ModelComponent(mesh: resource, materials: [material])
    }
    
    func triangleMesh() throws -> LowLevelMesh {
        var desc = VertexData.descriptor
        desc.vertexCapacity = 3
        desc.indexCapacity = 3

        let mesh = try LowLevelMesh(descriptor: desc)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: VertexData.self)
            vertices[0] = VertexData(position: [-1, -1, 0], normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>(1.0, Float(1)))
            vertices[1] = VertexData(position: [ 1, -1, 0], normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>(1, Float(1)))
            vertices[2] = VertexData(position: [ 0,  1, 0], normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>(1, Float(1)))
        }

        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            indices[0] = 0
            indices[1] = 1
            indices[2] = 2
        }

        let meshBounds = BoundingBox(min: [-10, -10, -10], max: [10, 10, 10])
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: 3,
                topology: .lineStrip,
                bounds: meshBounds
            )
        ])
        return mesh
    }


    func createMesh() throws -> LowLevelMesh {
        var desc = VertexData.descriptor
        desc.vertexCapacity = vertexCapacity
        desc.indexCapacity = indexCount

        let mesh = try LowLevelMesh(descriptor: desc)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: VertexData.self)
//            vertices[0] = VertexData(position: [-1, -1, 0], color: 0xFF00FF00)
//            vertices[1] = VertexData(position: [ 1, -1, 0], color: 0xFFFF0000)
//            vertices[2] = VertexData(position: [ 0,  1, 0], color: 0xFF0000FF)
            var index = 0;
            var base = SIMD3<Float>(0.2, 0.1, -0.2);
            
            for _ in 0..<latitudeBands {
                for _ in 0..<longitudeBands {
                    let p = lorenzIteration(p: base, dt: 0.003);
//                     let p = fakeIteration(p: base, dt: 0.1);
                    
                    vertices[index] = VertexData(position: p * 0.02 + SIMD3<Float>(0,-0,0), normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>.zero)
                    base = p;
                    index = index + 1;
                }
            }

        }


        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            var index = 0

            for _ in 0..<latitudeBands {
                for _ in 0..<longitudeBands {
                    indices[index] = UInt32(index)
                    index = index + 1
//                    let first = (latNumber * (longitudeBands + 1)) + longNumber
//                    let second = first + longitudeBands + 1
//
//                    indices[index] = UInt32(first)
//                    indices[index + 1] = UInt32(second)
//                    indices[index + 2] = UInt32(first + 1)
//
//                    indices[index + 3] = UInt32(second)
//                    indices[index + 4] = UInt32(second + 1)
//                    indices[index + 5] = UInt32(first + 1)
//
//                    index += 6
                }
            }
        }
        
        let meshBounds = BoundingBox(min: [-10, -10, -10], max: [10, 10, 10])
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: vertexCapacity,
                topology: .lineStrip,
                bounds: meshBounds
            )
        ])

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
                topology: .lineStrip,
                bounds: meshBounds
            )
        ])
    }

    struct VertexData {
        var position: SIMD3<Float> = .zero
        var normal: SIMD3<Float> = .zero
        var uv: SIMD2<Float> = .zero
        // var segmentIdx: Float = .zero;

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

func fakeIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
    let d = SIMD3<Float>(0.1, 0, 0) * dt
    return p + d
}

func lorenzIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
    let tau: Float = 10.0;
    let rou: Float = 28.0;
    let beta: Float = 8.0 / 3.0
    
    let dx = tau * (p.y - p.x)
    let dy = p.x * (rou - p.z) - p.y
    let dz = p.x * p.y - beta * p.z
    let d = SIMD3<Float>(dx, dy, dz) * dt
    return p + d
}
//fn lorenz(p: vec3f, dt: f32) -> LorenzResult {
//  let beta = 8.0 / 3.0;
//  let dx = tau * (p.y - p.x);
//  let dy = p.x * (rou - p.z) - p.y;
//  let dz = p.x * p.y - beta * p.z;
//  let d = vec3<f32>(dx, dy, dz) * dt;
//  return LorenzResult(
//    p + d,
//    vec3(dx, dy, dz),
//    length(d) * 2.1
//  );
//}

#Preview {
    MorphingSphereMetalView()
}
