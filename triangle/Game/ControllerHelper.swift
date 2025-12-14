import ARKit
import Foundation
import GameController
import RealityKit
import simd

/// A shared helper for applying controller input to entities
/// Uses GameManager for full controller functionality with ARKit head tracking
@MainActor
class ControllerHelper {
  let gameManager: GameManager
  private var lastUpdateTime: Float = 0
  private var startTime: Date = Date()

  /// Initial position offset for the entity
  var initialPosition: SIMD3<Float> = SIMD3<Float>(0, 1, 0)

  // ARKit session for head tracking
  private var arkitSession: ARKitSession?
  private var worldTracking: WorldTrackingProvider?

  init() {
    self.gameManager = GameManager()
    setupARKitSession()
  }

  private func setupARKitSession() {
    Task {
      let session = ARKitSession()
      let worldTracking = WorldTrackingProvider()

      do {
        try await session.run([worldTracking])
        self.arkitSession = session
        self.worldTracking = worldTracking
        print("[ControllerHelper] ARKit world tracking started")
      } catch {
        print("[ControllerHelper] Failed to start ARKit session: \(error)")
      }
    }
  }

  /// Get the current head (device) transform from ARKit
  private func getHeadTransform() -> simd_float4x4 {
    guard let worldTracking = worldTracking,
      let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
    else {
      // Return identity matrix if ARKit not available
      return matrix_identity_float4x4
    }
    return deviceAnchor.originFromAnchorTransform
  }

  /// Reset the controller state (call this when the view appears)
  func reset() {
    startTime = Date()
    lastUpdateTime = 0
    gameManager.resetState()
  }

  /// Update the entity's transform based on controller input
  /// Uses GameManager with ARKit head tracking for movement direction
  ///
  /// Controls (from GameManager):
  /// - Left stick Y: Move forward/backward (in head facing direction)
  /// - Left stick X: Yaw rotation (turn left/right)
  /// - Right stick X: Strafe left/right
  /// - Right stick Y: Move up/down
  /// - L1/R1: Boost (5x speed)
  ///
  /// - Parameter entity: The root entity to transform
  func updateEntityTransform(_ entity: Entity) {
    let currentTime = Float(Date().timeIntervalSince(startTime))
    let delta = max(0, currentTime - lastUpdateTime)
    guard delta > 0 else { return }
    lastUpdateTime = currentTime

    // Get head transform from ARKit for movement direction
    let headTransform = getHeadTransform()

    // Use GameManager to calculate rig transform with head tracking
    _ = gameManager.updateRigState(deltaTime: delta, headTransform: headTransform)

    // Apply inverse transform to scene (camera moves forward = scene moves backward)
    // GameManager provides playerOffset and yawAngle

    // Inverse yaw for scene rotation
    let inverseYaw = -gameManager.yawAngle
    let inverseRotation = simd_quatf(angle: inverseYaw, axis: SIMD3<Float>(0, 1, 0))

    // playerOffset is in world space, but since we rotate the scene by inverseRotation,
    // we need to transform the offset into the rotated scene's coordinate system
    let rotationMatrix = float3x3(inverseRotation)
    let inverseOffset = rotationMatrix * (-gameManager.playerOffset)

    entity.position = initialPosition + inverseOffset
    entity.orientation = inverseRotation
  }
}
