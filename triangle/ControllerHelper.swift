import Foundation
import RealityKit
import simd

/// A shared helper for applying controller input to entities
/// This provides a simpler interface than using GameManager directly in each view
@MainActor
class ControllerHelper {
  let gameManager: GameManager
  private var lastUpdateTime: Float = 0
  private var startTime: Date = Date()

  /// Initial position offset for the entity
  var initialPosition: SIMD3<Float> = SIMD3<Float>(0, 1, 0)

  init() {
    self.gameManager = GameManager()
  }

  /// Reset the start time (call this when the view appears)
  func reset() {
    startTime = Date()
    lastUpdateTime = 0
  }

  /// Update the entity's transform based on controller input
  /// Call this in your timer loop
  /// - Parameter entity: The root entity to transform
  func updateEntityTransform(_ entity: Entity) {
    let currentTime = Float(Date().timeIntervalSince(startTime))
    let delta = max(0, currentTime - lastUpdateTime)
    guard delta > 0 else { return }

    // Use identity matrix as head transform since we're in RealityView without device tracking
    let headTransform = matrix_identity_float4x4
    _ = gameManager.updateRigState(deltaTime: delta, headTransform: headTransform)

    // Apply to entity - move scene with player movement
    entity.position = initialPosition + gameManager.playerOffset
    entity.orientation = simd_quatf(angle: gameManager.yawAngle, axis: SIMD3<Float>(0, 1, 0))

    lastUpdateTime = currentTime
  }
}
