
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
};

struct MovingCubesParams {
  float width;
  float dt;
  float timestamp;
};

struct CubeBase {
  float2 xy;
};

constant float3 squareVertices[] = {
    float3(1.0, 0.0, 0.0),
    float3(0.0, 1.0, 0.0),
    float3(-1.0, 0.0, 0.0),
    float3(0.0, -1.0, 0.0),
};

float3 hyperbolicHelicoid(float2 uv, float tau) {
  float u = uv.x;
  float v = uv.y;

  float divident = 1 + cosh(u) * cosh(v);
  float x = sinh(v) * cos(tau * u) / divident;
  float y = sinh(v) * sin(tau * u) / divident;
  float z = cosh(v) * sinh(u) / divident;
  return float3(x, y, z);
}

// Mobius transformation generated from:
// https://gist.github.com/Dan-Piker/f7d790b3967d41bff8b0291f4cf7bd9e
// https://www.desmos.com/3d/gl6fnutnck
// (I don't have a understanding of the math behind this transformation yet)
float3 mobiusTransformation(float3 pt, float t) {
  // Initial point coordinates
  float xa = pt.x;
  float ya = pt.y;
  float za = pt.z;

  // Constants for rotation
  float p = 0.0;
  float q = 1.0;

  // Reverse stereographic projection to hypersphere
  float denom = 1.0 + xa * xa + ya * ya + za * za;
  float xb = 2.0 * xa / denom;
  float yb = 2.0 * ya / denom;
  float zb = 2.0 * za / denom;
  float wb = (-1.0 + xa * xa + ya * ya + za * za) / denom;

  // Rotate hypersphere
  float xc = xb * cos(p * t) + yb * sin(p * t);
  float yc = -xb * sin(p * t) + yb * cos(p * t);
  float zc = zb * cos(q * t) - wb * sin(q * t);
  float wc = zb * sin(q * t) + wb * cos(q * t);

  // Project stereographically back to 3D
  float xd = xc / (1.0 - wc);
  float yd = yc / (1.0 - wc);
  float zd = zc / (1.0 - wc);

  return float3(xd, yd, zd);
}

kernel void updateHyperbolicHelicoidVertexes(
    device CubeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];
  float3 position = hyperbolicHelicoid(
      base.xy, 7.0 * sin(params.timestamp * 0.7)
      // 2.
  );
  position = mobiusTransformation(
      position.xzy, sin(params.timestamp * 0.2) * 1.3
      // -1.2
  );

  outputVertices[id].position = position * 0.4;
}
