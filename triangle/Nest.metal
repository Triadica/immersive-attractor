
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingNestParams {
  float width;
  float dt;
};

struct NestBase {
  float3 position;
  float size;
  float rotate;
};

constant float3 nestVertices[] = {
    float3(-1.0, -1.0, 1.0),
    float3(1.0, -1.0, 1.0),
    float3(1.0, -1.0, -1.0),
    float3(-1.0, -1.0, -1.0),
    float3(-1.0, 1.0, 1.0),
    float3(1.0, 1.0, 1.0),
    float3(1.0, 1.0, -1.0),
    float3(-1.0, 1.0, -1.0),
};

kernel void updateNestBase(
    device NestBase *nestBaseList [[buffer(0)]],
    device NestBase *outputNestBaseList [[buffer(1)]],
    constant MovingNestParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  NestBase base = nestBaseList[id];

  if (base.position.y < -20.0) {
    outputNestBaseList[id].position.y = 20.0;
  } else {
    outputNestBaseList[id].position.y = base.position.y - 0.002 * base.size;
  }
}

kernel void updateNestVertexes(
    device NestBase *nestBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingNestParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  uint nestIdx = id / 8;
  NestBase base = nestBaseList[nestIdx];
  // vertice
  uint verticeIdx = id % 8;
  float3 vertice = nestVertices[verticeIdx];

  float3 position = base.position + vertice * 0.1 * base.size;

  outputVertices[id].position = position;
}
