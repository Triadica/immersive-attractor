import Foundation
import GameController
import SwiftUI
import simd

@Observable
class GameManager {
  private struct ControllerState {
    var leftStick: SIMD2<Float> = .zero
    var rightStick: SIMD2<Float> = .zero
    var buttonA: Bool = false
    var buttonB: Bool = false
    var buttonX: Bool = false
    var buttonY: Bool = false
    var boostActive: Bool = false
    // D-pad for Tetris
    var dpadUp: Bool = false
    var dpadDown: Bool = false
    var dpadLeft: Bool = false
    var dpadRight: Bool = false
  }

  private let controllerQueue = DispatchQueue(label: "vr-dive.controller.state")
  private var controllerState = ControllerState()
  private var lastInputLogTime: TimeInterval = 0

  private let movementSpeed: Float = 1.2
  private let yawSpeed: Float = .pi / 2.0
  private let deadZone: Float = 0.12
  private let boostMovementMultiplier: Float = 5.0
  private let boostYawMultiplier: Float = 2.0

  private(set) var playerOffset: SIMD3<Float> = .zero
  private(set) var yawAngle: Float = 0
  private(set) var rigTransform: simd_float4x4 = matrix_identity_float4x4

  init() {
    setupControllerObserver()
  }
  
  /// Reset the player state (position and rotation)
  func resetState() {
    playerOffset = .zero
    yawAngle = 0
    rigTransform = matrix_identity_float4x4
  }

  // MARK: - Tetris Input (PS5 Controller)
  // △ = buttonY = 向上移动
  // × = buttonA = 快速下落
  // □ = buttonX = 切换方块类型
  // ○ = buttonB = 随机旋转朝向

  struct TetrisInput {
    var dpadUp: Bool
    var dpadDown: Bool
    var dpadLeft: Bool
    var dpadRight: Bool
    var buttonCross: Bool  // × = 快速下落
    var buttonTriangle: Bool  // △ = 向上移动
    var buttonSquare: Bool  // □ = 切换方块类型
    var buttonCircle: Bool  // ○ = 随机旋转朝向
  }

  func getTetrisInput() -> TetrisInput {
    controllerQueue.sync {
      TetrisInput(
        dpadUp: controllerState.dpadUp,
        dpadDown: controllerState.dpadDown,
        dpadLeft: controllerState.dpadLeft,
        dpadRight: controllerState.dpadRight,
        buttonCross: controllerState.buttonA,  // PS5 × maps to buttonA
        buttonTriangle: controllerState.buttonY,  // PS5 △ maps to buttonY
        buttonSquare: controllerState.buttonX,  // PS5 □ maps to buttonX
        buttonCircle: controllerState.buttonB  // PS5 ○ maps to buttonB
      )
    }
  }

  func setupControllerObserver() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(controllerDidConnect), name: .GCControllerDidConnect, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(controllerDidDisconnect), name: .GCControllerDidDisconnect,
      object: nil)

    GCController.startWirelessControllerDiscovery(completionHandler: nil)
    for controller in GCController.controllers() {
      register(controller: controller)
    }
  }

  @objc private func controllerDidConnect(notification: Notification) {
    guard let controller = notification.object as? GCController else { return }
    register(controller: controller)
  }

  @objc private func controllerDidDisconnect(notification: Notification) {
    guard let controller = notification.object as? GCController else { return }
    print("[GameManager] Controller disconnected: \(controller.vendorName ?? "Unknown Controller")")
  }

  private func register(controller: GCController) {
    print("[GameManager] Controller connected: \(controller.vendorName ?? "Unknown Controller")")
    guard let gamepad = controller.extendedGamepad else {
      print("[GameManager] Connected controller has no extended gamepad profile")
      return
    }

    gamepad.valueChangedHandler = { [weak self] gamepad, element in
      self?.handleInput(gamepad: gamepad, element: element)
    }
  }

  private func handleInput(gamepad: GCExtendedGamepad, element: GCControllerElement) {
    let leftStick = SIMD2<Float>(
      gamepad.leftThumbstick.xAxis.value, gamepad.leftThumbstick.yAxis.value)
    let rightStick = SIMD2<Float>(
      gamepad.rightThumbstick.xAxis.value, gamepad.rightThumbstick.yAxis.value)
    let buttonA = gamepad.buttonA.isPressed
    let buttonB = gamepad.buttonB.isPressed
    let buttonX = gamepad.buttonX.isPressed
    let buttonY = gamepad.buttonY.isPressed
    let boostActive = gamepad.leftShoulder.isPressed || gamepad.rightShoulder.isPressed

    // D-pad
    let dpadUp = gamepad.dpad.up.isPressed
    let dpadDown = gamepad.dpad.down.isPressed
    let dpadLeft = gamepad.dpad.left.isPressed
    let dpadRight = gamepad.dpad.right.isPressed

    controllerQueue.sync {
      controllerState.leftStick = leftStick
      controllerState.rightStick = rightStick
      controllerState.buttonA = buttonA
      controllerState.buttonB = buttonB
      controllerState.buttonX = buttonX
      controllerState.buttonY = buttonY
      controllerState.boostActive = boostActive
      controllerState.dpadUp = dpadUp
      controllerState.dpadDown = dpadDown
      controllerState.dpadLeft = dpadLeft
      controllerState.dpadRight = dpadRight
    }

    logInputEvent(
      element: element, leftStick: leftStick, rightStick: rightStick, buttonA: buttonA,
      boost: boostActive)
  }

  private func logInputEvent(
    element: GCControllerElement, leftStick: SIMD2<Float>, rightStick: SIMD2<Float>,
    buttonA: Bool, boost: Bool
  ) {
    let now = Date().timeIntervalSince1970
    guard now - lastInputLogTime > 0.05 else { return }
    lastInputLogTime = now

    let elementName = String(describing: type(of: element))
    let formattedLeft = String(format: "(%.2f, %.2f)", leftStick.x, leftStick.y)
    let formattedRight = String(format: "(%.2f, %.2f)", rightStick.x, rightStick.y)
    print(
      "[GameManager] Input \(elementName) left=\(formattedLeft) right=\(formattedRight) A=\(buttonA) boost=\(boost)"
    )
  }

  func updateRigState(deltaTime: Float, headTransform: simd_float4x4) -> simd_float4x4 {
    controllerQueue.sync {
      let primaryStickInput = applyDeadZone(controllerState.leftStick)
      let secondaryStickInput = applyDeadZone(controllerState.rightStick)
      let movementMultiplier = controllerState.boostActive ? boostMovementMultiplier : 1.0
      let yawMultiplier = controllerState.boostActive ? boostYawMultiplier : 1.0

      let forwardInput = primaryStickInput.y
      let yawInput = primaryStickInput.x
      let strafeInput = secondaryStickInput.x
      let verticalInput = secondaryStickInput.y

      // Reduce turning speed by half when actively turning
      let turnSpeedReduction = 1.0 - abs(yawInput) * 0.5
      yawAngle -= yawInput * yawSpeed * yawMultiplier * turnSpeedReduction * deltaTime
      yawAngle = wrapAngle(yawAngle)

      // Calculate Rig Rotation (Tracking -> World rotation)
      let cosYaw = cos(-yawAngle)
      let sinYaw = sin(-yawAngle)
      let rigRotation = simd_float3x3(
        SIMD3<Float>(cosYaw, 0, sinYaw),
        SIMD3<Float>(0, 1, 0),
        SIMD3<Float>(-sinYaw, 0, cosYaw)
      )

      // Extract Head vectors in Tracking Space
      // Column 0: Right, 1: Up, 2: Backward (-Forward)
      let headRight = SIMD3<Float>(
        headTransform.columns.0.x, headTransform.columns.0.y, headTransform.columns.0.z)
      let headUp = SIMD3<Float>(
        headTransform.columns.1.x, headTransform.columns.1.y, headTransform.columns.1.z)
      let headForward = -SIMD3<Float>(
        headTransform.columns.2.x, headTransform.columns.2.y, headTransform.columns.2.z)

      // Transform to World Space
      let worldForward = rigRotation * headForward
      let worldRight = rigRotation * headRight
      let worldUp = rigRotation * headUp

      var displacement = SIMD3<Float>.zero
      displacement -= worldForward * forwardInput
      displacement -= worldRight * strafeInput
      displacement -= worldUp * verticalInput

      playerOffset += displacement * movementSpeed * movementMultiplier * deltaTime

      rigTransform = buildRigTransform()
      return rigTransform
    }
  }

  func currentRigTransform() -> simd_float4x4 {
    controllerQueue.sync { rigTransform }
  }

  private func applyDeadZone(_ input: SIMD2<Float>) -> SIMD2<Float> {
    let magnitude = simd_length(input)
    guard magnitude > deadZone else { return .zero }
    let scaled = (magnitude - deadZone) / (1 - deadZone)
    return (input / max(magnitude, 0.0001)) * scaled
  }

  private func wrapAngle(_ angle: Float) -> Float {
    var value = angle
    let twoPi: Float = .pi * 2
    value = fmod(value, twoPi)
    if value > .pi {
      value -= twoPi
    } else if value < -.pi {
      value += twoPi
    }
    return value
  }

  private func buildRigTransform() -> simd_float4x4 {
    let cosYaw = cos(-yawAngle)
    let sinYaw = sin(-yawAngle)
    let rotation = simd_float4x4(
      SIMD4<Float>(cosYaw, 0, sinYaw, 0),
      SIMD4<Float>(0, 1, 0, 0),
      SIMD4<Float>(-sinYaw, 0, cosYaw, 0),
      SIMD4<Float>(0, 0, 0, 1)
    )

    let translation = simd_float4x4(
      SIMD4<Float>(1, 0, 0, 0),
      SIMD4<Float>(0, 1, 0, 0),
      SIMD4<Float>(0, 0, 1, 0),
      SIMD4<Float>(-playerOffset.x, -playerOffset.y, -playerOffset.z, 1)
    )

    return translation * rotation
  }
}
