import RealityKit
import SwiftUI

private final class GestureStateComponent: @unchecked Sendable {
  var targetedEntity: Entity?
  var dragStartPosition: SIMD3<Float> = .zero
  var isDragging = false
  var startScale: SIMD3<Float> = .one
  var isScaling = false
  var startOrientation = Rotation3D.identity
  var isRotating = false
}

struct GestureComponent: Component, Codable {
  var canDrag: Bool = true
  var canScale: Bool = true
  var canRotate: Bool = true

  private static let state = GestureStateComponent()

  @MainActor mutating func onDragChange(value: EntityTargetValue<DragGesture.Value>) {
    guard canDrag else { return }
    let entity = value.entity
    // Skip if already scaling or rotating
    if GestureComponent.state.isScaling || GestureComponent.state.isRotating {
      return
    }

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
