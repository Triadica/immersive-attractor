//
//  triangleApp.swift
//  triangle
//
//  Created by chen on 2024/8/18.
//

import SwiftUI

@main
struct triangleApp: App {
    var body: some Scene {
        WindowGroup {
//            ContentView()
            MorphingSphereMetalView()
        }.windowStyle(.volumetric)

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
            MorphingSphereMetalView()
        }.immersionStyle(selection: .constant(.full), in: .full)
    }
}
