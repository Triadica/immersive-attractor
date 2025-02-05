//
//  triangleApp.swift
//  triangle
//
//  Created by chen on 2024/8/18.
//

import SwiftUI

@main
struct triangleApp: App {
  @Environment(\.openImmersiveSpace) private var openImmersiveSpace
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

  var body: some Scene {
    WindowGroup {
      // ContentView()
      // MorphingSphereMetalView()
      // AttractorView()
      // MovingLorenzView()
      Button("Show Space") {
        Task {
          let result = await openImmersiveSpace(id: "ImmersiveSpace")
          if case .error = result {
            print("An error occurred")
          }
        }
      }
      Button("Dismiss") {
        Task {
          await dismissImmersiveSpace()
        }
      }

    }.windowStyle(.volumetric).defaultSize(width: 10, height: 10, depth: 10, in: .meters)

    ImmersiveSpace(id: "ImmersiveSpace") {
      // ImmersiveView()
      MovingLorenzView()
      // MorphingSphereMetalView()
    }.immersionStyle(selection: .constant(.full), in: .full)
  }
}
