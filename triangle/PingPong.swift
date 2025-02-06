import Metal

/// Represents a ping-pong or bilateral oscillation behavior
///
/// The ping-pong pattern describes a value that moves back and forth between two points,
/// similar to how a ping-pong ball bounces between players.
///
class PingPongBuffer {
  let bufferA: MTLBuffer
  let bufferB: MTLBuffer
  var currentBuffer: MTLBuffer
  var nextBuffer: MTLBuffer

  init(device: MTLDevice, length: Int) {
    bufferA = device.makeBuffer(length: length, options: .storageModeShared)!
    bufferB = device.makeBuffer(length: length, options: .storageModeShared)!
    currentBuffer = bufferA
    nextBuffer = bufferB
  }

  func swap() {
    (currentBuffer, nextBuffer) = (nextBuffer, currentBuffer)
  }
}
