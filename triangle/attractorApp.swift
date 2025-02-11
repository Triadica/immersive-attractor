//
//  triangleApp.swift
//  triangle
//
//  Created by chen on 2024/8/18.
//

import SwiftUI

@main
struct AttractorApp: App {
  @Environment(\.openImmersiveSpace) private var openImmersiveSpace
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

  var body: some Scene {
    WindowGroup {
      Button("Show Space") {
        Task {
          let result = await openImmersiveSpace(id: "ImmersiveSpace")
          if case .error = result {
            print("An error occurred")
          }
        }
      }.padding(.bottom, 32)
      Button("Dismiss") {
        Task {
          await dismissImmersiveSpace()
        }
      }

    }.windowStyle(.volumetric).defaultSize(width: 10, height: 10, depth: 10, in: .meters)

    ImmersiveSpace(id: "ImmersiveSpace") {
      // CubesMovingView()
      // AttractorLineView()
      // MovingLorenzView()
      // RadicalLineView()
      SphereBouncingView()
    }.immersionStyle(selection: .constant(.full), in: .full)
  }
}
