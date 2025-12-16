import Foundation
import RealityKit

/// Extension to help views record mesh frames easily
extension MeshRecorder {
  /// Record a frame from LowLevelMesh if recording is active
  /// Call this in your timer callback after updating the mesh
  @MainActor
  func recordIfActive(mesh: LowLevelMesh?, topology: MeshTopology = .lines) {
    guard isRecording else { return }
    guard let mesh = mesh else {
      print("[MeshRecorder] recordIfActive: mesh is nil")
      return
    }
    recordFrame(mesh: mesh, topology: topology)
  }
}

/// A helper function to record mesh if the global recorder is active
@MainActor
func recordMeshIfActive(mesh: LowLevelMesh?, topology: MeshTopology = .lines) {
  RecorderState.shared.recorder.recordIfActive(mesh: mesh, topology: topology)
}
