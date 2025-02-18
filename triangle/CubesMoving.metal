
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
};

struct CubeBase {
  float3 position;
  float size;
  float rotate;
};

constant float3 cubeVertices[] = {
    float3(-1.0, -1.0, 1.0),  float3(1.0, -1.0, 1.0),  float3(1.0, -1.0, -1.0),
    float3(-1.0, -1.0, -1.0), float3(-1.0, 1.0, 1.0),  float3(1.0, 1.0, 1.0),
    float3(1.0, 1.0, -1.0),   float3(-1.0, 1.0, -1.0),
};

kernel void updateCubeBase(device CubeBase *codeBaseList [[buffer(0)]],
                           device CubeBase *outputCodeBaseList [[buffer(1)]],
                           constant MovingCubesParams &params [[buffer(2)]],
                           uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];

  if (base.position.y < -20.0) {
    outputCodeBaseList[id].position.y = 20.0;
  } else {
    outputCodeBaseList[id].position.y = base.position.y - 0.002 * base.size;
  }
}

kernel void updateCubeVertexes(device CubeBase *codeBaseList [[buffer(0)]],
                               device VertexData *outputVertices [[buffer(1)]],
                               constant MovingCubesParams &params [[buffer(2)]],
                               uint id [[thread_position_in_grid]]) {
  uint cubeIdx = id / 8;
  CubeBase base = codeBaseList[cubeIdx];
  // vertice
  uint verticeIdx = id % 8;
  float3 vertice = cubeVertices[verticeIdx];

  float3 position = base.position + vertice * 0.1 * base.size;

  outputVertices[id].position = position;
}
