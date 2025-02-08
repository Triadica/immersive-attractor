//
//  Iterate.swift
//  triangle
//
//  Created by chen on 2025/2/6.
//

private func fakeIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
  let d = SIMD3<Float>(0.1, 0.1, -0.1) * dt
  return p + d
}

private func lorenzIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
  let tau: Float = 10.0
  let rou: Float = 28.0
  let beta: Float = 8.0 / 3.0

  let dx = tau * (p.y - p.x)
  let dy = p.x * (rou - p.z) - p.y
  let dz = p.x * p.y - beta * p.z
  let d = SIMD3<Float>(dx, dy, dz) * dt
  return p + d
}

private func fourwingIteration(p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
  let a: Float = 0.2
  let b: Float = 0.01
  let c: Float = -0.4
  let x = p.x
  let y = p.y
  let z = p.z
  let dx = a * x + y * z
  let dy = b * x + c * y - x * z
  let dz = -z - x * y
  let d = SIMD3<Float>(dx, dy, dz) * dt
  return p + d

}

func randomPosition(r: Float) -> SIMD3<Float> {
  let x = Float.random(in: -r...r)
  let y = Float.random(in: -r...r)
  let z = Float.random(in: -r...r)
  return SIMD3<Float>(x, y, z)
}
