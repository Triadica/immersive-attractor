import simd

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

/// Create a random position within a cube of side length `2r` centered at the origin.
/// - Parameter r: The half-length of the cube.
/// - Returns: A random position within the cube.
func randomPosition(r: Float) -> SIMD3<Float> {
  let x = Float.random(in: -r...r)
  let y = Float.random(in: -r...r)
  let z = Float.random(in: -r...r)
  return SIMD3<Float>(x, y, z)
}

// Alternative method: Spherical Coordinates - more efficient, avoids loops in rejection sampling
func randomPointInSphere2(radius: Double) -> SIMD3<Float> {

  // 1. Generate random spherical coordinates
  let u = Double.random(in: 0...1)
  let v = Double.random(in: 0...1)
  let theta = 2 * Double.pi * u  // longitude: 0 to 2π
  let phi = acos(2 * v - 1)  // latitude: 0 to π (note this isn't -π/2 to π/2)
  let r = radius * pow(Double.random(in: 0...1), 1.0 / 3.0)  // radius: 0 to radius (uniform distribution)

  // 2. Convert spherical coordinates to Cartesian coordinates
  let x = r * sin(phi) * cos(theta)
  let y = r * sin(phi) * sin(theta)
  let z = r * cos(phi)

  return SIMD3(Float(x), Float(y), Float(z))
}

struct Triangle {
  var a: SIMD3<Float>
  var b: SIMD3<Float>
  var c: SIMD3<Float>
}

private func makeSphereIterateInternal(
  triangles: [Triangle]
) -> [Triangle] {
  var newTriangles: [Triangle] = []

  for triangle in triangles {
    // Calculate midpoints
    let abN = (triangle.a + triangle.b) * 0.5
    let bcN = (triangle.b + triangle.c) * 0.5
    let caN = (triangle.c + triangle.a) * 0.5

    // Create four new triangles
    newTriangles.append(Triangle(a: triangle.a, b: abN, c: caN))
    newTriangles.append(Triangle(a: abN, b: triangle.b, c: bcN))
    newTriangles.append(Triangle(a: caN, b: bcN, c: triangle.c))
    newTriangles.append(Triangle(a: abN, b: bcN, c: caN))
  }

  return newTriangles
}

/// create regular octahedron first, then split each face into 4 triangles, and finally create sphere
func makeSphereWithIterate(times: Int) -> [SIMD3<Float>] {

  var triangles: [Triangle] = []

  // Create octahedron vertices
  let x1 = SIMD3<Float>(1, 0, 0)
  let x2 = SIMD3<Float>(-1, 0, 0)
  let y1 = SIMD3<Float>(0, 1, 0)
  let y2 = SIMD3<Float>(0, -1, 0)
  let z1 = SIMD3<Float>(0, 0, 1)
  let z2 = SIMD3<Float>(0, 0, -1)

  // Initial triangles (octahedron faces)
  triangles.append(Triangle(a: x1, b: y1, c: z1))
  triangles.append(Triangle(a: y1, b: z1, c: x2))
  triangles.append(Triangle(a: y1, b: x2, c: z2))
  triangles.append(Triangle(a: y1, b: z2, c: x1))
  triangles.append(Triangle(a: y2, b: z1, c: x1))
  triangles.append(Triangle(a: y2, b: x2, c: z1))
  triangles.append(Triangle(a: y2, b: z2, c: x2))
  triangles.append(Triangle(a: y2, b: x1, c: z2))

  // Perform subdivision
  for _ in 0..<times {
    triangles = makeSphereIterateInternal(triangles: triangles)
  }

  // for each triangle, project point with radius to sphere, and push 6 vertices
  var vertices: [SIMD3<Float>] = []

  for triangle in triangles {
    let a = simd.normalize(triangle.a)
    let b = simd.normalize(triangle.b)
    let c = simd.normalize(triangle.c)
    // let a = triangle.a
    // let b = triangle.b
    // let c = triangle.c

    vertices.append(a)
    vertices.append(b)
    // vertices.append(b)
    // vertices.append(a)

    vertices.append(b)
    vertices.append(c)
    // vertices.append(c)
    // vertices.append(b)

    vertices.append(c)
    vertices.append(a)
    // vertices.append(a)
    // vertices.append(c)
  }

  return vertices
}

/// `y` is the height, `x` and `z` are the horizontal plane
func fibonacciGrid(n: Float, total: Float) -> SIMD3<Float> {
  let z = (2.0 * n - 1.0) / total - 1.0
  let t = sqrt(1.0 - z * z)
  let t2 = 2.0 * 3.14159265359 * 1.61803398875 * n
  let x = t * cos(t2)
  let y = t * sin(t2)
  return SIMD3(x, z, y)
}

/// Performs one iteration of the generalized triangle map, transforming a point `p0`
/// based on the positions of three attractor points `p1`, `p2`, and `p3`, and a parameter `t`.
/// The parameter `t` controls the relative influence of each attractor point on the new position.
///
/// - Precondition: `p1`, `p2`, and `p3` should be distinct points to form a valid triangle.
///
/// - Parameters:
///   - p0: The point to transform.
///   - p1: The first attractor point.
///   - p2: The second attractor point.
///   - p3: The third attractor point.
///   - t: The parameter controlling the relative influence of the attractor points.
/// - Returns: The new position of the point `p0` after one iteration of the map.
func bezierCurve(p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, t: Float)
  -> SIMD3<Float>
{
  let t2 = t * t
  let t3 = t2 * t
  let mt = 1 - t
  let mt2 = mt * mt
  let mt3 = mt2 * mt
  let term1 = p0 * mt3
  let term2 = p1 * 3 * mt2 * t
  let term3 = p2 * 3 * mt * t2
  let term4 = p3 * t3
  return term1 + term2 + term3 + term4
}
