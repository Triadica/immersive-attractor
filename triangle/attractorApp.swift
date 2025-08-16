//
//  triangleApp.swift
//  triangle
//
//  Created by chen on 2024/8/18.
//

import SwiftUI

private enum VisibilityDemo: String {
  case cubesMoving = "Cubes Moving"
  case attractorLine = "Attractor Line"
  case movingLorenz = "Moving Lorenz"
  case radicalLine = "Radical Line"
  case sphereBouncing = "Sphere Bouncing"
  case cornerBouncing = "Corner Bouncing"
  case polygonWall = "Polygon Wall"
  case hyperbolicHelicoid = "Hyperbolic Helicoid"
  case chords = "Chords"
  case fireworks = "Fireworks"
  case fireworksBlow = "Fireworks Blow"
  case hopfFibration = "Hopf Fibration"
  case hopfFibrationLayer = "Hopf Fibration Layer"
  case mobiusGird = "Mobius Gird"
  case mobiusTrail = "Mobius Trail"
  case mobiusBubbles = "Mobius Bubbles"
  case lotus = "Lotus"
  case nebula = "Nebula"
  case fractalBranches = "Fractal Branches"
  case fractalUmbrella = "Fractal Umbrella"
  case fractalTree = "Fractal Tree"
  case snowflake = "Snowflake"
  case mobiusSpheres = "Mobius Spheres"
  case bifurcation = "Bifurcation"
  case nest = "Nest"
}

@main
struct AttractorApp: App {
  @Environment(\.openImmersiveSpace) private var openImmersiveSpace
  @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

  @State private var selectedDemo: VisibilityDemo = .bifurcation

  @State private var isImmersionActive = false

  var body: some Scene {
    WindowGroup {

      HStack {
        Picker("Demo", selection: $selectedDemo) {
          Text("Cubes Moving").tag(VisibilityDemo.cubesMoving)
          Text("Attractor Line").tag(VisibilityDemo.attractorLine)
          Text("Moving Lorenz").tag(VisibilityDemo.movingLorenz)
          Text("Radical Line").tag(VisibilityDemo.radicalLine)
          Text("Sphere Bouncing").tag(VisibilityDemo.sphereBouncing)
          Text("Corner Bouncing").tag(VisibilityDemo.cornerBouncing)
          Text("Polygon Wall").tag(VisibilityDemo.polygonWall)
          Text("Hyperbolic Helicoid").tag(VisibilityDemo.hyperbolicHelicoid)
          Text("Chords").tag(VisibilityDemo.chords)
          Text("Fireworks").tag(VisibilityDemo.fireworks)
          Text("Fireworks Blow").tag(VisibilityDemo.fireworksBlow)
          Text("Hopf Fibration").tag(VisibilityDemo.hopfFibration)
          Text("Hopf Fibration Layer").tag(VisibilityDemo.hopfFibrationLayer)
          Text("Mobius Gird").tag(VisibilityDemo.mobiusGird)
          Text("Mobius Trail").tag(VisibilityDemo.mobiusTrail)
          Text("Mobius Bubbles").tag(VisibilityDemo.mobiusBubbles)
          Text("Lotus").tag(VisibilityDemo.lotus)
          Text("Nebula").tag(VisibilityDemo.nebula)
          Text("Fractal Branches").tag(VisibilityDemo.fractalBranches)
          Text("Fractal Umbrella").tag(VisibilityDemo.fractalUmbrella)
          Text("Fractal Tree").tag(VisibilityDemo.fractalTree)
          Text("Snowflake").tag(VisibilityDemo.snowflake)
          Text("Mobius Spheres").tag(VisibilityDemo.mobiusSpheres)
          Text("Bifurcation").tag(VisibilityDemo.bifurcation)
          Text("Nest").tag(VisibilityDemo.nest)
        }.pickerStyle(.wheel).padding(.bottom, 32).frame(
          width: 400,
          height: 600,
          alignment: .center
        )
        VStack {
          Button("Toggle Space") {
            Task {
              if isImmersionActive {
                await dismissImmersiveSpace()
                isImmersionActive = false
              } else {
                let result = await openImmersiveSpace(id: "ImmersiveSpace")
                if case .error = result {
                  print("An error occurred")
                }
                isImmersionActive = true
              }
            }
          }.padding(.bottom, 32)

          Text("Selected demo: \(selectedDemo.rawValue)").padding(.top, 32)
        }.frame(width: 400)
      }

    }.windowStyle(.volumetric).defaultSize(width: 10, height: 10, depth: 10, in: .meters)

    ImmersiveSpace(id: "ImmersiveSpace") {
      if let demo = VisibilityDemo(rawValue: selectedDemo.rawValue) {
        switch demo {
        case .cubesMoving:
          CubesMovingView()
        case .attractorLine:
          AttractorLineView()
        case .movingLorenz:
          MovingLorenzView()
        case .radicalLine:
          RadicalLineView()
        case .sphereBouncing:
          SphereBouncingView()
        case .cornerBouncing:
          CornerBouncingView()
        case .polygonWall:
          PolygonWallView()
        case .hyperbolicHelicoid:
          HyperbolicHelicoidView()
        case .chords:
          ChordsView()
        case .fireworks:
          FireworksView()
        case .fireworksBlow:
          FireworksBlowView()
        case .hopfFibration:
          HopfFibrationView()
        case .hopfFibrationLayer:
          HopfFibrationLayerView()
        case .mobiusGird:
          MobiusGirdView()
        case .mobiusTrail:
          MobiusTrailView()
        case .mobiusBubbles:
          MobiusBubblesView()
        case .lotus:
          LotusView()
        case .nebula:
          NebulaView()
        case .fractalBranches:
          FractalBranchesView()
        case .fractalUmbrella:
          FractalUmbrellaView()
        case .fractalTree:
          FractalTreeView()
        case .snowflake:
          SnowflakeView()
        case .mobiusSpheres:
          MobiusSpheresView()
        case .bifurcation:
          BifurcationView()
        case .nest:
          NestView()
        }
      }

    }.immersionStyle(selection: .constant(.full), in: .full)
  }
}
