import Metal

/// Represents a ping-pong or bilateral oscillation behavior
///
/// The ping-pong pattern describes a value that moves back and forth between two points,
/// similar to how a ping-pong ball bounces between players.
///
class PingPongBuffer {
  var currentBuffer: MTLBuffer
  var nextBuffer: MTLBuffer

  init(device: MTLDevice, length: Int) {
    guard let safeBuffer = device.makeBuffer(length: length, options: .storageModeShared),
      let safeBufferB = device.makeBuffer(length: length, options: .storageModeShared)
    else {
      fatalError("Failed to create ping-pong buffer")
    }
    currentBuffer = safeBuffer
    nextBuffer = safeBufferB
  }

  func swap() {
    (currentBuffer, nextBuffer) = (nextBuffer, currentBuffer)
  }

  
}
