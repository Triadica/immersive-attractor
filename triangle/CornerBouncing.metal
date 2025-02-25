
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingAttractorLineParams {
  int vertexPerCell;
  float dt;
};

struct CubeBase {
  float3 position;
  float3 velocity;
};

kernel void updateCornerBouncingBase(
    device CubeBase *codeBaseList [[buffer(0)]],
    device CubeBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];
  float3 position = base.position;
  float3 velocity = base.velocity;
  float3 acceleration = float3(0., -0.4, 0.);
  float3 positionNext = position + velocity * params.dt;
  float3 velocityNext = velocity + acceleration * params.dt;

  // first plane, perpendicular to line from original point and (1, -1, 1)
  float3 normal1 = normalize(float3(1., -1.04, 0.));
  float shadow1 = dot(positionNext, normal1);
  if (shadow1 > 0) {
    float3 vParallel = dot(velocityNext, normal1) * normal1;
    float3 vPerpendicular = velocityNext - vParallel;
    outputCodeBaseList[id].velocity = vPerpendicular - vParallel * 0.94;
    outputCodeBaseList[id].position = position;
    return;
  }

  float3 normal2 = normalize(float3(-0.5, -1.04, 0.86602540378));
  float shadow2 = dot(positionNext, normal2);
  if (shadow2 >= 0) {
    float3 vParallel = dot(velocityNext, normal2) * normal2;
    float3 vPerpendicular = velocityNext - vParallel;
    outputCodeBaseList[id].velocity = vPerpendicular - vParallel * 0.94;
    outputCodeBaseList[id].position = position;
    return;
  }

  float3 normal3 = normalize(float3(-0.5, -1.04, -0.86602540378));
  float shadow3 = dot(positionNext, normal3);
  if (shadow3 >= 0) {
    float3 vParallel = dot(velocityNext, normal3) * normal3;
    float3 vPerpendicular = velocityNext - vParallel;
    outputCodeBaseList[id].velocity = vPerpendicular - vParallel * 0.94;
    outputCodeBaseList[id].position = position;
    return;
  }

  outputCodeBaseList[id].velocity = velocityNext;
  outputCodeBaseList[id].position = positionNext;
}

kernel void updateCornerBouncingVertexes(
    device CubeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  if (cellInnerIdx == 0) {
    CubeBase base = codeBaseList[cellIdx];
    outputVertices[id].position =
        float3(base.position.x, base.position.y, base.position.z - 0.2) * 0.32 -
        float3(0., 1., 0.);
  } else {
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}
