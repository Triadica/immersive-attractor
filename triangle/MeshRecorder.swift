import Foundation
import Metal
import RealityKit
import simd

/// Represents a single frame of recorded vertex data
struct RecordedFrame {
  let timestamp: Double
  let vertices: [SIMD3<Float>]
  let indices: [UInt32]
  let topology: MeshTopology
}

/// Topology type for the mesh
enum MeshTopology: String {
  case triangles = "triangles"
  case lines = "lines"
  case lineStrip = "lineStrip"
  case points = "points"
}

/// A recorder that captures vertex data from LowLevelMesh for USDZ export
@MainActor
class MeshRecorder: ObservableObject {
  @Published var isRecording = false
  @Published var recordedFrameCount = 0
  @Published var recordingProgress: Double = 0

  private var frames: [RecordedFrame] = []
  private var startTime: Date?
  private var maxDuration: TimeInterval = 10.0  // Default max recording duration
  private var targetFPS: Double = 30.0  // Target FPS for export
  private var lastRecordedTime: Date?
  private var frameInterval: TimeInterval { 1.0 / targetFPS }

  /// Start recording
  func startRecording(duration: TimeInterval = 10.0, fps: Double = 30.0) {
    frames.removeAll()
    isRecording = true
    recordedFrameCount = 0
    recordingProgress = 0
    startTime = Date()
    lastRecordedTime = nil
    maxDuration = duration
    targetFPS = fps
    print("[MeshRecorder] Started recording - duration: \(duration)s, fps: \(fps)")
  }

  /// Stop recording
  func stopRecording() {
    isRecording = false
    print("[MeshRecorder] Stopped recording - \(frames.count) frames captured")
  }

  /// Record a frame from LowLevelMesh
  func recordFrame(mesh: LowLevelMesh, topology: MeshTopology = .lines) {
    guard isRecording, let startTime = startTime else { return }

    let currentTime = Date()
    let elapsed = currentTime.timeIntervalSince(startTime)

    // Check if we've exceeded max duration
    if elapsed >= maxDuration {
      stopRecording()
      return
    }

    // Throttle frame capture to target FPS
    if let lastTime = lastRecordedTime {
      if currentTime.timeIntervalSince(lastTime) < frameInterval {
        return
      }
    }

    lastRecordedTime = currentTime
    recordingProgress = elapsed / maxDuration

    // Extract vertices from mesh
    var vertices: [SIMD3<Float>] = []

    // Check if vertex buffer exists and has data
    guard mesh.parts.count > 0 else {
      print("[ERR] mesh has no parts")
      return
    }

    do {
      try mesh.withUnsafeBytes(bufferIndex: 0) { rawBytes in
        guard rawBytes.count > 0 else {
          print("[ERR] vertex buffer is empty")
          return
        }
        let stride = MemoryLayout<SIMD3<Float>>.stride
        let count = rawBytes.count / stride
        let pointer = rawBytes.bindMemory(to: SIMD3<Float>.self)
        for i in 0..<count {
          vertices.append(pointer[i])
        }
      }
    } catch {
      print("[ERR] vertex buffer is not initialized: \(error)")
      return
    }

    // Check if we got valid vertices
    guard vertices.count > 0 else {
      return
    }

    // Extract indices from mesh
    var indices: [UInt32] = []
    do {
      try mesh.withUnsafeIndices { rawIndices in
        let pointer = rawIndices.bindMemory(to: UInt32.self)
        for i in 0..<rawIndices.count / MemoryLayout<UInt32>.stride {
          indices.append(pointer[i])
        }
      }
    } catch {
      print("[ERR] index buffer is not initialized: \(error)")
      return
    }

    let frame = RecordedFrame(
      timestamp: elapsed,
      vertices: vertices,
      indices: indices,
      topology: topology
    )

    frames.append(frame)
    recordedFrameCount = frames.count
  }

  /// Record a frame directly from vertex buffer
  func recordFrame(
    vertexBuffer: MTLBuffer, vertexCount: Int, indices: [UInt32], topology: MeshTopology = .lines
  ) {
    guard isRecording, let startTime = startTime else { return }

    let currentTime = Date()
    let elapsed = currentTime.timeIntervalSince(startTime)

    if elapsed >= maxDuration {
      stopRecording()
      return
    }

    if let lastTime = lastRecordedTime {
      if currentTime.timeIntervalSince(lastTime) < frameInterval {
        return
      }
    }

    lastRecordedTime = currentTime
    recordingProgress = elapsed / maxDuration

    // Extract vertices from buffer
    var vertices: [SIMD3<Float>] = []
    let pointer = vertexBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
    for i in 0..<vertexCount {
      vertices.append(pointer[i])
    }

    let frame = RecordedFrame(
      timestamp: elapsed,
      vertices: vertices,
      indices: indices,
      topology: topology
    )

    frames.append(frame)
    recordedFrameCount = frames.count
  }

  /// Get the best export directory (prefers Downloads on Mac/Simulator)
  private func getExportDirectory() -> URL {
    // Try to use Downloads directory first (works better for simulator)
    if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
      .first
    {
      // Check if we can write to it
      if FileManager.default.isWritableFile(atPath: downloadsURL.path) {
        return downloadsURL
      }
    }

    // Fallback to Documents directory
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  /// Export recorded frames to USDA format
  func exportToUSDA(filename: String = "animation") async throws -> URL {
    guard !frames.isEmpty else {
      throw MeshRecorderError.noFramesRecorded
    }

    let exportDir = getExportDirectory()
    let fileURL = exportDir.appendingPathComponent("\(filename).usda")

    let usdaContent = generateUSDAContent()
    try usdaContent.write(to: fileURL, atomically: true, encoding: .utf8)

    print("[MeshRecorder] Exported USDA to: \(fileURL.path)")
    return fileURL
  }

  /// Export to USDZ format using zip compression
  func exportToUSDZ(filename: String = "animation") async throws -> URL {
    guard !frames.isEmpty else {
      throw MeshRecorderError.noFramesRecorded
    }

    let exportDir = getExportDirectory()
    let usdaURL = exportDir.appendingPathComponent("\(filename).usda")
    let usdzURL = exportDir.appendingPathComponent("\(filename).usdz")

    // Capture frames data for background processing
    let capturedFrames = self.frames
    let fps = self.targetFPS

    // Run heavy work on background thread
    return try await Task.detached(priority: .userInitiated) {
      // Generate USDA content on background thread
      let usdaContent = Self.generateUSDAContentStatic(frames: capturedFrames, targetFPS: fps)
      try usdaContent.write(to: usdaURL, atomically: true, encoding: .utf8)

      // Create USDZ by wrapping USDA in a zip archive
      try Self.createUSDZStatic(from: usdaURL, to: usdzURL)

      // Clean up the intermediate USDA file
      try? FileManager.default.removeItem(at: usdaURL)

      print("[MeshRecorder] Exported USDZ to: \(usdzURL.path)")
      return usdzURL
    }.value
  }

  /// Create USDZ file from USDA (USDZ is a zip with specific structure)
  nonisolated private static func createUSDZStatic(from usdaURL: URL, to usdzURL: URL) throws {
    // Remove existing file if present
    try? FileManager.default.removeItem(at: usdzURL)

    // Read USDA content
    let usdaData = try Data(contentsOf: usdaURL)

    // Create a simple uncompressed zip archive
    // USDZ requires uncompressed storage
    var zipData = Data()

    let filename = usdaURL.lastPathComponent
    let filenameData = filename.data(using: .utf8)!

    // Local file header
    zipData.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])  // Local file header signature
    zipData.append(contentsOf: [0x0A, 0x00])  // Version needed (1.0)
    zipData.append(contentsOf: [0x00, 0x00])  // General purpose bit flag
    zipData.append(contentsOf: [0x00, 0x00])  // Compression method (stored/none)
    zipData.append(contentsOf: [0x00, 0x00])  // Last mod file time
    zipData.append(contentsOf: [0x00, 0x00])  // Last mod file date

    // CRC-32
    let crc = crc32Static(usdaData)
    zipData.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })

    // Compressed size (same as uncompressed for stored)
    let size = UInt32(usdaData.count)
    zipData.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })

    // Uncompressed size
    zipData.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })

    // Filename length
    let filenameLength = UInt16(filenameData.count)
    zipData.append(contentsOf: withUnsafeBytes(of: filenameLength.littleEndian) { Array($0) })

    // Extra field length
    zipData.append(contentsOf: [0x00, 0x00])

    // Filename
    zipData.append(filenameData)

    // File data
    let localHeaderOffset = UInt32(0)
    zipData.append(usdaData)

    // Central directory header
    let centralDirOffset = UInt32(zipData.count)
    zipData.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])  // Central directory signature
    zipData.append(contentsOf: [0x0A, 0x00])  // Version made by
    zipData.append(contentsOf: [0x0A, 0x00])  // Version needed
    zipData.append(contentsOf: [0x00, 0x00])  // General purpose bit flag
    zipData.append(contentsOf: [0x00, 0x00])  // Compression method
    zipData.append(contentsOf: [0x00, 0x00])  // Last mod file time
    zipData.append(contentsOf: [0x00, 0x00])  // Last mod file date
    zipData.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
    zipData.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
    zipData.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
    zipData.append(contentsOf: withUnsafeBytes(of: filenameLength.littleEndian) { Array($0) })
    zipData.append(contentsOf: [0x00, 0x00])  // Extra field length
    zipData.append(contentsOf: [0x00, 0x00])  // File comment length
    zipData.append(contentsOf: [0x00, 0x00])  // Disk number start
    zipData.append(contentsOf: [0x00, 0x00])  // Internal file attributes
    zipData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // External file attributes
    zipData.append(contentsOf: withUnsafeBytes(of: localHeaderOffset.littleEndian) { Array($0) })
    zipData.append(filenameData)

    // End of central directory
    let centralDirSize = UInt32(zipData.count) - centralDirOffset
    zipData.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])  // End of central directory signature
    zipData.append(contentsOf: [0x00, 0x00])  // Number of this disk
    zipData.append(contentsOf: [0x00, 0x00])  // Disk where central directory starts
    zipData.append(contentsOf: [0x01, 0x00])  // Number of central directory records on this disk
    zipData.append(contentsOf: [0x01, 0x00])  // Total number of central directory records
    zipData.append(contentsOf: withUnsafeBytes(of: centralDirSize.littleEndian) { Array($0) })
    zipData.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Array($0) })
    zipData.append(contentsOf: [0x00, 0x00])  // Comment length

    try zipData.write(to: usdzURL)
  }

  /// Calculate CRC32 checksum
  nonisolated private static func crc32Static(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    let polynomial: UInt32 = 0xEDB8_8320

    for byte in data {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        if crc & 1 != 0 {
          crc = (crc >> 1) ^ polynomial
        } else {
          crc >>= 1
        }
      }
    }

    return ~crc
  }

  /// Export point cloud as USDZ
  func exportPointCloudUSDZ(filename: String = "pointcloud") async throws -> URL {
    guard !frames.isEmpty else {
      throw MeshRecorderError.noFramesRecorded
    }

    let exportDir = getExportDirectory()
    let usdaURL = exportDir.appendingPathComponent("\(filename).usda")
    let usdzURL = exportDir.appendingPathComponent("\(filename).usdz")

    // Capture frames data for background processing
    let capturedFrames = self.frames
    let fps = self.targetFPS

    // Run heavy work on background thread
    return try await Task.detached(priority: .userInitiated) {
      // Generate point cloud USDA content on background thread
      let usdaContent = Self.generatePointCloudUSDAContentStatic(
        frames: capturedFrames, targetFPS: fps)
      try usdaContent.write(to: usdaURL, atomically: true, encoding: .utf8)

      // Convert to USDZ
      try Self.createUSDZStatic(from: usdaURL, to: usdzURL)

      // Clean up
      try? FileManager.default.removeItem(at: usdaURL)

      print("[MeshRecorder] Exported Point Cloud USDZ to: \(usdzURL.path)")
      return usdzURL
    }.value
  }

  /// Generate point cloud USDA content (static version for background thread)
  nonisolated private static func generatePointCloudUSDAContentStatic(
    frames: [RecordedFrame], targetFPS: Double
  ) -> String {
    // Pre-calculate capacity
    let estimatedSize = frames.count * (frames.first?.vertices.count ?? 0) * 50 + 5000
    var usda = ""
    usda.reserveCapacity(estimatedSize)

    usda += """
      #usda 1.0
      (
          defaultPrim = "Root"
          metersPerUnit = 1
          upAxis = "Y"
          startTimeCode = 0
          endTimeCode = \(frames.count - 1)
          timeCodesPerSecond = \(targetFPS)
      )

      def Xform "Root"
      {
          def Points "AnimatedPoints"
          {
              point3f[] points.timeSamples = {

      """

    for (index, frame) in frames.enumerated() {
      usda += "            \(index): ["
      var isFirst = true
      for vertex in frame.vertices {
        if !isFirst {
          usda += ", "
        }
        isFirst = false
        usda += "(\(vertex.x), \(vertex.y), \(vertex.z))"
      }
      usda += "],\n"
    }

    usda += """
              }
              color3f[] primvars:displayColor = [(1.0, 0.8, 0.0)]
              float[] widths = [0.01]
          }
      }
      """

    return usda
  }

  /// Generate USDA content with animation
  private func generateUSDAContent() -> String {
    guard let firstFrame = frames.first else { return "" }

    var usda = """
      #usda 1.0
      (
          defaultPrim = "Root"
          metersPerUnit = 1
          upAxis = "Y"
          startTimeCode = 0
          endTimeCode = \(frames.count - 1)
          timeCodesPerSecond = \(targetFPS)
      )

      def Xform "Root" (
          kind = "component"
      )
      {
          def Mesh "AnimatedMesh"
          {
              uniform bool doubleSided = true

      """

    // Add animated vertex positions
    usda += "        point3f[] points.timeSamples = {\n"
    for (index, frame) in frames.enumerated() {
      let pointsStr = frame.vertices.map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: ", ")
      usda += "            \(index): [\(pointsStr)],\n"
    }
    usda += "        }\n\n"

    // Add face indices based on topology
    let faceVertexCounts: String
    let faceVertexIndices: String

    switch firstFrame.topology {
    case .triangles:
      let triangleCount = firstFrame.indices.count / 3
      faceVertexCounts = Array(repeating: "3", count: triangleCount).joined(separator: ", ")
      faceVertexIndices = firstFrame.indices.map { String($0) }.joined(separator: ", ")

    case .lines, .lineStrip:
      // For lines, we need to create thin triangles to represent them
      // USDZ doesn't support line primitives directly, so we'll use the points
      let lineSegmentCount = firstFrame.indices.count / 2
      faceVertexCounts = Array(repeating: "2", count: lineSegmentCount).joined(separator: ", ")
      faceVertexIndices = firstFrame.indices.map { String($0) }.joined(separator: ", ")

    case .points:
      // Points topology - create degenerate triangles
      faceVertexCounts = Array(repeating: "1", count: firstFrame.vertices.count).joined(
        separator: ", ")
      faceVertexIndices = (0..<firstFrame.vertices.count).map { String($0) }.joined(separator: ", ")
    }

    usda += """
              int[] faceVertexCounts = [\(faceVertexCounts)]
              int[] faceVertexIndices = [\(faceVertexIndices)]

              color3f[] primvars:displayColor = [(1.0, 0.8, 0.0)]
              uniform token subdivisionScheme = "none"
          }
      }
      """

    return usda
  }

  /// Generate USDA content with animation (static version for background thread)
  nonisolated private static func generateUSDAContentStatic(
    frames: [RecordedFrame], targetFPS: Double
  ) -> String {
    guard let firstFrame = frames.first else { return "" }

    // Pre-calculate capacity to avoid reallocations
    // Estimate: ~50 bytes per vertex per frame + overhead
    let estimatedSize = frames.count * firstFrame.vertices.count * 50 + 10000
    var usda = ""
    usda.reserveCapacity(estimatedSize)

    usda += """
      #usda 1.0
      (
          defaultPrim = "Root"
          metersPerUnit = 1
          upAxis = "Y"
          startTimeCode = 0
          endTimeCode = \(frames.count - 1)
          timeCodesPerSecond = \(targetFPS)
      )

      def Xform "Root" (
          kind = "component"
      )
      {
          def Mesh "AnimatedMesh"
          {
              uniform bool doubleSided = true

      """

    // Add animated vertex positions - optimized version
    usda += "        point3f[] points.timeSamples = {\n"
    for (index, frame) in frames.enumerated() {
      usda += "            \(index): ["
      // Build points string more efficiently
      var isFirst = true
      for vertex in frame.vertices {
        if !isFirst {
          usda += ", "
        }
        isFirst = false
        usda += "(\(vertex.x), \(vertex.y), \(vertex.z))"
      }
      usda += "],\n"
    }
    usda += "        }\n\n"

    // Add face indices based on topology
    let faceVertexCounts: String
    let faceVertexIndices: String

    switch firstFrame.topology {
    case .triangles:
      let triangleCount = firstFrame.indices.count / 3
      faceVertexCounts = String(repeating: "3, ", count: max(0, triangleCount - 1)) + "3"
      faceVertexIndices = firstFrame.indices.map { String($0) }.joined(separator: ", ")

    case .lines, .lineStrip:
      let lineSegmentCount = firstFrame.indices.count / 2
      faceVertexCounts = String(repeating: "2, ", count: max(0, lineSegmentCount - 1)) + "2"
      faceVertexIndices = firstFrame.indices.map { String($0) }.joined(separator: ", ")

    case .points:
      let count = firstFrame.vertices.count
      faceVertexCounts = String(repeating: "1, ", count: max(0, count - 1)) + "1"
      faceVertexIndices = (0..<count).map { String($0) }.joined(separator: ", ")
    }

    usda += """
              int[] faceVertexCounts = [\(faceVertexCounts)]
              int[] faceVertexIndices = [\(faceVertexIndices)]

              color3f[] primvars:displayColor = [(1.0, 0.8, 0.0)]
              uniform token subdivisionScheme = "none"
          }
      }
      """

    return usda
  }

  /// Get recorded frames for custom processing
  func getRecordedFrames() -> [RecordedFrame] {
    return frames
  }

  /// Clear recorded frames
  func clearRecording() {
    print("[MeshRecorder] clearRecording() called - clearing \(frames.count) frames")
    frames.removeAll()
    recordedFrameCount = 0
    recordingProgress = 0
  }
}

/// Errors for MeshRecorder
enum MeshRecorderError: Error, LocalizedError {
  case noFramesRecorded
  case exportFailed(String)

  var errorDescription: String? {
    switch self {
    case .noFramesRecorded:
      return "No frames were recorded"
    case .exportFailed(let message):
      return "Export failed: \(message)"
    }
  }
}
