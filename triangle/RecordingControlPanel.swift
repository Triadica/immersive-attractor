import Combine
import SwiftUI

/// Global recorder state manager
@MainActor
class RecorderState: ObservableObject {
  static let shared = RecorderState()

  @Published var recorder = MeshRecorder()
  @Published var exportedFileURL: URL?
  @Published var showExportAlert = false
  @Published var showShareSheet = false
  @Published var exportError: String?
  @Published var recordingDuration: Double = 5.0
  @Published var exportFPS: Double = 30.0
  @Published var isExporting = false
  @Published var exportStatus: String = ""

  private var cancellables = Set<AnyCancellable>()

  private init() {
    print("[RecorderState] Initialized singleton instance")
    // Forward recorder's objectWillChange to our own
    recorder.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }.store(in: &cancellables)
  }

  func startRecording() {
    print(
      "[RecorderState] startRecording() called - duration: \(recordingDuration)s, fps: \(exportFPS)"
    )
    print("[RecorderState] Current isRecording state before: \(recorder.isRecording)")
    recorder.startRecording(duration: recordingDuration, fps: exportFPS)
    print("[RecorderState] Current isRecording state after: \(recorder.isRecording)")
    objectWillChange.send()  // Force UI update
  }

  func stopRecording() {
    print("[RecorderState] stopRecording() called")
    recorder.stopRecording()
    objectWillChange.send()  // Force UI update
  }

  /// Stop recording and automatically export to USDA (more compatible)
  func stopAndExport(filename: String) async {
    print("[RecorderState] stopAndExport() called")
    recorder.stopRecording()
    objectWillChange.send()

    // Check if we have frames to export
    guard recorder.recordedFrameCount > 0 else {
      print("[RecorderState] No frames recorded, skipping export")
      exportError = "No frames were recorded"
      showExportAlert = true
      return
    }

    // Start export
    isExporting = true
    exportStatus = "Exporting \(recorder.recordedFrameCount) frames..."
    objectWillChange.send()

    do {
      // Export as USDA (text format, more compatible)
      let url = try await recorder.exportToUSDA(filename: filename)
      exportedFileURL = url
      exportError = nil
      isExporting = false
      exportStatus = "Export complete!"
      showShareSheet = true
      print("[RecorderState] Auto-export successful: \(url.path)")
    } catch {
      exportError = error.localizedDescription
      isExporting = false
      exportStatus = "Export failed"
      showExportAlert = true
      print("[RecorderState] Auto-export failed: \(error.localizedDescription)")
    }
    objectWillChange.send()
  }

  func exportToUSDA(filename: String) async {
    print("[RecorderState] exportToUSDA() called with filename: \(filename)")
    do {
      let url = try await recorder.exportToUSDZ(filename: filename)
      exportedFileURL = url
      exportError = nil
      showShareSheet = true
      print("[RecorderState] Export successful: \(url.path)")
    } catch {
      exportError = error.localizedDescription
      showExportAlert = true
      print("[RecorderState] Export failed: \(error.localizedDescription)")
    }
  }

  func exportAsPointCloud(filename: String) async {
    print("[RecorderState] exportAsPointCloud() called with filename: \(filename)")
    do {
      let url = try await recorder.exportPointCloudUSDZ(filename: filename)
      exportedFileURL = url
      exportError = nil
      showShareSheet = true
      print("[RecorderState] Point cloud export successful: \(url.path)")
    } catch {
      exportError = error.localizedDescription
      showExportAlert = true
      print("[RecorderState] Point cloud export failed: \(error.localizedDescription)")
    }
  }
}

/// Share sheet for exporting files
struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Recording control panel view
struct RecordingControlPanel: View {
  @ObservedObject var state = RecorderState.shared
  @State private var filename = "animation"
  @State private var showRecordingComplete = false
  @State private var blinkOpacity: Double = 1.0
  @State private var lastAction: String = "None"
  @State private var lastActionTime: Date = Date()

  var body: some View {
    VStack(spacing: 12) {
      // Recording status with blinking indicator
      HStack {
        Circle()
          .fill(state.recorder.isRecording ? Color.red : Color.gray)
          .frame(width: 12, height: 12)
          .opacity(state.recorder.isRecording ? blinkOpacity : 1.0)
        Text(state.recorder.isRecording ? "🔴 Recording..." : "⚪ Ready")
          .font(.headline)
          .foregroundColor(state.recorder.isRecording ? .red : .primary)
      }
      .animation(
        .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
        value: state.recorder.isRecording
      )
      .onChange(of: state.recorder.isRecording) { oldValue, newValue in
        if newValue {
          // Started recording - start blinking
          withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            blinkOpacity = 0.3
          }
        } else {
          // Stopped recording
          blinkOpacity = 1.0
          if oldValue && state.recorder.recordedFrameCount > 0 {
            // Recording just finished with frames captured
            showRecordingComplete = true
          }
        }
      }

      // Progress bar during recording
      if state.recorder.isRecording {
        VStack {
          ProgressView(value: state.recorder.recordingProgress)
            .progressViewStyle(.linear)
            .tint(.red)
          HStack {
            Text("\(state.recorder.recordedFrameCount) frames")
              .font(.caption)
            Spacer()
            Text(
              "\(Int(state.recorder.recordingProgress * state.recordingDuration))s / \(Int(state.recordingDuration))s"
            )
            .font(.caption)
          }
          if state.recorder.recordedFrameCount == 0 {
            Text("⚠️ Waiting for mesh data...")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }
      }

      // Debug info
      VStack(alignment: .leading, spacing: 4) {
        Text("Last action: \(lastAction)")
          .font(.caption2)
          .foregroundColor(.secondary)
        Text("isRecording: \(state.recorder.isRecording ? "YES" : "NO")")
          .font(.caption2)
          .foregroundColor(state.recorder.isRecording ? .green : .secondary)
        Text("Frames: \(state.recorder.recordedFrameCount)")
          .font(.caption2)
          .foregroundColor(.secondary)
        if state.isExporting {
          Text("⏳ \(state.exportStatus)")
            .font(.caption2)
            .foregroundColor(.blue)
        } else if !state.exportStatus.isEmpty {
          Text(state.exportStatus)
            .font(.caption2)
            .foregroundColor(.green)
        }
      }
      .padding(8)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(8)

      // Duration slider
      VStack(alignment: .leading) {
        Text("Duration: \(Int(state.recordingDuration))s")
          .font(.caption)
        Slider(value: $state.recordingDuration, in: 1...30, step: 1)
          .disabled(state.recorder.isRecording)
      }

      // FPS slider
      VStack(alignment: .leading) {
        Text("Export FPS: \(Int(state.exportFPS))")
          .font(.caption)
        Slider(value: $state.exportFPS, in: 10...60, step: 5)
          .disabled(state.recorder.isRecording)
      }

      // Filename input
      TextField("Filename", text: $filename)
        .textFieldStyle(.roundedBorder)
        .disabled(state.recorder.isRecording)

      // Control buttons
      HStack(spacing: 12) {
        if state.recorder.isRecording {
          Button(action: {
            print("[RecordingControlPanel] Stop button tapped - will auto-export")
            lastAction = "Stop & Export @ \(Date().formatted(date: .omitted, time: .standard))"
            lastActionTime = Date()
            Task {
              await state.stopAndExport(filename: filename)
            }
          }) {
            Label("Stop & Export", systemImage: "stop.fill")
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .disabled(state.isExporting)
        } else if state.isExporting {
          ProgressView()
            .progressViewStyle(.circular)
          Text("Exporting...")
            .font(.caption)
        } else {
          Button(action: {
            print("[RecordingControlPanel] Record button tapped")
            lastAction = "Record @ \(Date().formatted(date: .omitted, time: .standard))"
            lastActionTime = Date()
            state.startRecording()
          }) {
            Label("Record", systemImage: "record.circle")
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .disabled(state.recorder.isRecording)
        }
      }

      // Export buttons (only show when we have frames)
      if state.recorder.recordedFrameCount > 0 && !state.recorder.isRecording {
        Divider()

        Text("\(state.recorder.recordedFrameCount) frames recorded")
          .font(.caption)
          .foregroundColor(.secondary)

        HStack(spacing: 12) {
          Button(action: {
            print("[RecordingControlPanel] Export USDZ button tapped")
            Task {
              await state.exportToUSDA(filename: filename)
            }
          }) {
            Label("Export USDZ", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.bordered)

          Button(action: {
            print("[RecordingControlPanel] Point Cloud button tapped")
            Task {
              await state.exportAsPointCloud(filename: "\(filename)_points")
            }
          }) {
            Label("Point Cloud", systemImage: "circle.grid.3x3")
          }
          .buttonStyle(.bordered)
        }

        Button(action: {
          print("[RecordingControlPanel] Clear button tapped")
          state.recorder.clearRecording()
        }) {
          Label("Clear", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .tint(.orange)
      }
    }
    .padding()
    .frame(width: 300)
    .sheet(isPresented: $state.showShareSheet) {
      if let url = state.exportedFileURL {
        ShareSheet(items: [url])
      }
    }
    .alert("Export Error", isPresented: $state.showExportAlert) {
      Button("OK") {}
    } message: {
      if let error = state.exportError {
        Text("Error: \(error)")
      }
    }
    .alert("Recording Complete", isPresented: $showRecordingComplete) {
      Button("OK") {}
    } message: {
      Text(
        "✅ Captured \(state.recorder.recordedFrameCount) frames!\n\nYou can now export the animation."
      )
    }
  }
}

#Preview {
  RecordingControlPanel()
}
