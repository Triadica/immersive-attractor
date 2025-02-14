
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
  float3( 1.0, 0.0, 0.0),
  float3( 0.0, 1.0, 0.0),
  float3(-1.0, 0.0, 0.0),
  float3( 0.0,-1.0, 0.0),
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

float2 hyperComplexMul(float2 a, float2 b) {
  return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

kernel void updateHyperbolicHelicoidVertexes(
                                      device CubeBase *codeBaseList [[buffer(0)]],
                                      device VertexData *outputVertices [[buffer(1)]],
                                      constant MovingCubesParams &params [[buffer(2)]],
                                      uint id [[thread_position_in_grid]])
{
  CubeBase base = codeBaseList[id];
  float3 position = hyperbolicHelicoid(base.xy, 6.0 * sin(params.timestamp * 0.3));

  outputVertices[id].position = position.xzy * 0.4;
}

