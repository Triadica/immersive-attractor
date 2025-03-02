
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingAttractorLineParams {
  float dt;
  float timestamp;
};

struct CellBase {
  float3 position;
  float seed;
};

// Mobius transformation generated from:
// https://gist.github.com/Dan-Piker/f7d790b3967d41bff8b0291f4cf7bd9e
// https://www.desmos.com/3d/gl6fnutnck
// (I don't have a understanding of the math behind this transformation yet)
static float3 mobiusTransformation(float3 pt, float t) {
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

kernel void updateMobiusBubblesVertexes(
    device CellBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {

  float3 p = codeBaseList[id].position;
  float seed = codeBaseList[id].seed;
  float t = params.timestamp * 0.1 - seed;
  // float t = 0;
  float3 position = mobiusTransformation(p, t);
  // float3 position = p;

  position = position.xzy;
  position.z -= 2.0;
  position.y = -position.y;

  outputVertices[id].position = position;
}
