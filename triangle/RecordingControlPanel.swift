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

  private init() {}

  func startRecording() {
    recorder.startRecording(duration: recordingDuration, fps: exportFPS)
  }

  func stopRecording() {
    recorder.stopRecording()
  }

  func exportToUSDA(filename: String) async {
    do {
      let url = try await recorder.exportToUSDZ(filename: filename)
      exportedFileURL = url
      exportError = nil
      showShareSheet = true
    } catch {
      exportError = error.localizedDescription
      showExportAlert = true
    }
  }

  func exportAsPointCloud(filename: String) async {
    do {
      let url = try await recorder.exportPointCloudUSDZ(filename: filename)
      exportedFileURL = url
      exportError = nil
      showShareSheet = true
    } catch {
      exportError = error.localizedDescription
      showExportAlert = true
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

  var body: some View {
    VStack(spacing: 16) {
      // Recording status with blinking indicator
      HStack {
        Circle()
          .fill(state.recorder.isRecording ? Color.red : Color.gray)
          .frame(width: 12, height: 12)
          .opacity(state.recorder.isRecording ? blinkOpacity : 1.0)
        Text(state.recorder.isRecording ? "🔴 Recording..." : "Ready")
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
        }
      }

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
            state.stopRecording()
          }) {
            Label("Stop", systemImage: "stop.fill")
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
        } else {
          Button(action: {
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
            Task {
              await state.exportToUSDA(filename: filename)
            }
          }) {
            Label("Export USDZ", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(.bordered)

          Button(action: {
            Task {
              await state.exportAsPointCloud(filename: "\(filename)_points")
            }
          }) {
            Label("Point Cloud", systemImage: "circle.grid.3x3")
          }
          .buttonStyle(.bordered)
        }

        Button(action: {
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
