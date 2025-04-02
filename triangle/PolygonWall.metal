
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingCubesParams {
  float width;
  float dt;
  float timestamp;
};

struct CubeBase {
  float3 position;
  float size;
  float rotate;
};

constant float3 squareVertices[] = {
    float3(1.0, 0.0, 0.0),
    float3(0.0, 1.0, 0.0),
    float3(-1.0, 0.0, 0.0),
    float3(0.0, -1.0, 0.0),
};

kernel void updatePolygonWallBase(
    device CubeBase *codeBaseList [[buffer(0)]],
    device CubeBase *outputCodeBaseList [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];
  // outputCodeBaseList[id].position.z = 0.2 * sin(base.rotate *
  // params.timestamp * 0.4) - 0.6;
  outputCodeBaseList[id].position.z = -base.size * 1.2;
}

static float2 complexMul(float2 a, float2 b) {
  return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

kernel void updatePolygonWallVertexes(
    device CubeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  uint cubeIdx = id / 4;
  CubeBase base = codeBaseList[cubeIdx];
  // vertice
  uint verticeIdx = id % 4;
  float3 vertice = squareVertices[verticeIdx];
  float2 xy = vertice.xy;
  float angle = params.timestamp * base.rotate * 0.2;
  float2 rot = float2(cos(angle), sin(angle));
  vertice.xy = complexMul(xy, rot) * base.size * 2;
  vertice.z += 0.0;

  float3 position = base.position + vertice;

  outputVertices[id].position = position;
}
