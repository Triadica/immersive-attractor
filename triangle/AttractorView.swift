import SwiftUI
import RealityKit
import Metal

struct AttractorView: View {
    let rootEntity: Entity = Entity()
    let allSize: Int = 200000
    var vertexCapacity: Int {
        return allSize * 4
    }
    var indexCount: Int {
        return allSize * 6
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


    init() {
        
    }

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene).extents
                let radius = Float(0.5 * size.x)
                let mesh = try! createMesh()
                // let mesh = try! triangleMesh()
                
                let modelComponent = try! getModelComponent(mesh: mesh)
                rootEntity.components.set(modelComponent)
                // rootEntity.scale *= scalePreviewFactor
                content.add(rootEntity)
                self.radius = radius
                self.mesh = mesh
                
                let pointLight = PointLight()
                pointLight.light.intensity = 5000
                pointLight.light.color = UIColor.yellow
                pointLight.light.attenuationRadius = 2
                pointLight.position = SIMD3<Float>(0, 0, 0.4)
                
                content.add(pointLight)

            }
            .onAppear {
              // startTimer()
                

            }
//            .onDisappear { stopTimer() }
        }
    }

    func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
        let resource = try MeshResource(from: mesh)

        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = .white //.init(white: 0.05, alpha: 1.0)
        material.roughness.scale = 0.9
        material.metallic.scale = 0.4
        material.blending = .transparent(opacity: 1.0)
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
            var base = SIMD3<Float>(0.4, 0.4, -0.2);
            
            for idx in 0..<allSize {
                let p = lorenzIteration(p: base, dt: 0.002)
//                let p = fakeIteration(p: base, dt: 0.02)
//                let p = fourwingIteration(p: base, dt: 0.01)
                
                let index = idx * 4
                let scale: Float = 0.009
                
                vertices[index] = VertexData(position: base * scale + SIMD3<Float>(0,-0,0), normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>.zero)
                vertices[index+1] = VertexData(position: base * scale + SIMD3<Float>(0.002,-0,0), normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>.zero)
                vertices[index+2] = VertexData(position: p * scale + SIMD3<Float>(0,-0,0), normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>.zero)
                vertices[index+3] = VertexData(position: p * scale + SIMD3<Float>(0.002,-0,0), normal: SIMD3<Float>(0,1,1), uv: SIMD2<Float>.zero)
                base = p;
                
            }

        }

        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)

            for idx in 0..<allSize {
                let index = idx * 6
                let dx = idx * 4
                indices[index] = UInt32(dx)
                indices[index+1] = UInt32(dx + 1)
                indices[index+2] = UInt32(dx + 2)
                indices[index+3] = UInt32(dx + 2)
                indices[index+4] = UInt32(dx + 1)
                indices[index+5] = UInt32(dx + 3)
            }
        }
        
        let meshBounds = BoundingBox(min: [-10, -10, -10], max: [10, 10, 10])
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: indexCount,
                topology: .triangle,
                bounds: meshBounds
            )
        ])

        return mesh
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

private func lorenzIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
    let tau: Float = 10.0;
    let rou: Float = 28.0;
    let beta: Float = 8.0 / 3.0
    
    let dx = tau * (p.y - p.x)
    let dy = p.x * (rou - p.z) - p.y
    let dz = p.x * p.y - beta * p.z
    let d = SIMD3<Float>(dx, dy, dz) * dt
    return p + d
}

private func fourwingIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
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

