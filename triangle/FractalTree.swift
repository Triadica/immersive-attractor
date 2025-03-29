import Metal
import RealityKit
import RealityKitContent
import SwiftUI

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

private final class GestureStateComponent: @unchecked Sendable {
  var targetedEntity: Entity?
  var dragStartPosition: SIMD3<Float> = .zero
  var isDragging = false
  var startScale: SIMD3<Float> = .one
  var isScaling = false
  var startOrientation = Rotation3D.identity
  var isRotating = false
}

private struct GestureComponent: Component, Codable {
  var canDrag: Bool = true
  var canScale: Bool = true
  var canRotate: Bool = true

  private static let state = GestureStateComponent()

  @MainActor mutating func onDragChange(value: EntityTargetValue<DragGesture.Value>) {
    guard canDrag else { return }
    let entity = value.entity

    if !GestureComponent.state.isDragging {
      GestureComponent.state.targetedEntity = entity
      GestureComponent.state.dragStartPosition = entity.position
      GestureComponent.state.isDragging = true
    }

    let translation = value.convert(value.translation3D, from: .local, to: .scene)
    entity.position = GestureComponent.state.dragStartPosition + translation
  }

  @MainActor mutating func onScaleChange(value: EntityTargetValue<MagnifyGesture.Value>) {
    guard canScale else { return }
    let entity = value.entity

    if !GestureComponent.state.isScaling {
      GestureComponent.state.targetedEntity = entity
      GestureComponent.state.startScale = entity.scale
      GestureComponent.state.isScaling = true
    }

    let scale = Float(value.magnification)
    entity.scale = GestureComponent.state.startScale * scale
  }

  @MainActor mutating func onRotateChange(value: EntityTargetValue<RotateGesture3D.Value>) {
    guard canRotate else { return }
    let entity = value.entity

    if !GestureComponent.state.isRotating {
      GestureComponent.state.targetedEntity = entity
      GestureComponent.state.startOrientation = Rotation3D(entity.orientation)
      GestureComponent.state.isRotating = true
    }

    // Create a flipped rotation to correct the rotation direction
    let rotation = value.rotation
    let flippedRotation = Rotation3D(
      angle: rotation.angle,
      axis: RotationAxis3D(
        x: -rotation.axis.x,
        y: rotation.axis.y,
        z: -rotation.axis.z))

    // Apply the flipped rotation to the starting orientation
    let newOrientation = GestureComponent.state.startOrientation.rotated(by: flippedRotation)
    entity.setOrientation(.init(newOrientation), relativeTo: nil)
  }

  mutating func onGestureEnded() {
    GestureComponent.state.isDragging = false
    GestureComponent.state.isScaling = false
    GestureComponent.state.isRotating = false
    GestureComponent.state.targetedEntity = nil
  }
}

struct FractalTreeView: View {
  let rootEntity: Entity = Entity()
  @State var mesh: LowLevelMesh?

  let device: MTLDevice
  let commandQueue: MTLCommandQueue

  init() {
    self.device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!

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

        // Add components for gesture support
        rootEntity.components.set(modelComponent)
        rootEntity.components.set(GestureComponent())
        rootEntity.components.set(InputTargetComponent())

        // Enable world sensing
        // content.enableWorldSensing([.hands])

        // Adjust collision box size to match actual content
        let bounds = getBounds()
        rootEntity.components.set(
          CollisionComponent(
            shapes: [
              .generateBox(
                width: bounds.extents.x * 2,
                height: bounds.extents.y * 2,
                depth: bounds.extents.z * 2)
            ]
          ))

        // Move entity closer to user
        rootEntity.position = SIMD3<Float>(0, 0, -1)  // Adjust these values
        content.add(rootEntity)
        self.mesh = mesh
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
      .simultaneousGesture(
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

  func getModelComponent(mesh: LowLevelMesh) throws -> ModelComponent {
    let resource = try MeshResource(from: mesh)

    var unlitMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.5, blue: 0.5, alpha: 0.8))
    unlitMaterial.faceCulling = .none

    return ModelComponent(mesh: resource, materials: [unlitMaterial])
  }

  /// Create a bounding box for the mesh
  func getBounds() -> BoundingBox {
    let radius: Float = 10
    return BoundingBox(min: [-radius, -radius, -radius], max: [radius, radius, radius])
  }

  func createMesh() throws -> LowLevelMesh {

    let v0 = SIMD3<Float>(0, 4, 0)
    let v1 = SIMD3<Float>(0, 0, 1)
    var allVertexes: [SIMD3<Float>] = []
    func write(p0: SIMD3<Float>, p1: SIMD3<Float>) {
      allVertexes.append(p0 - v0)
      allVertexes.append(p1 - v0)
    }

    buildUmbrella(
      p0: SIMD3<Float>(0, 0, 0), v0: v0, relative: v1, parts: 8, elevation: 0.25 * Float.pi,
      decay: 0.4,
      step: 7,
      write: write, middle: true)

    let allLength = allVertexes.count

    var desc = VertexData.descriptor
    desc.vertexCapacity = allLength
    desc.indexCapacity = allLength

    let mesh = try LowLevelMesh(descriptor: desc)

    mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
      let vertexes = rawBytes.bindMemory(to: VertexData.self)

      for i in 0..<allLength {
        vertexes[i].position = allVertexes[i]
      }
    }

    mesh.withUnsafeMutableIndices { rawIndices in
      let indices = rawIndices.bindMemory(to: UInt32.self)

      for i in 0..<allLength {
        indices[i] = UInt32(i)
      }
    }

    mesh.parts.replaceAll([
      LowLevelMesh.Part(
        indexCount: allLength,
        topology: .line,
        bounds: getBounds()
      )
    ])

    return mesh
  }

}
