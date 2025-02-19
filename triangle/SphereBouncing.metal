
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
  float size;
  float3 velocity;
        float rotate;
};

kernel void updateSphereBouncingBase(device CubeBase *codeBaseList
                                     [[buffer(0)]],
                                     device CubeBase *outputCodeBaseList
                                     [[buffer(1)]],
                                     constant MovingAttractorLineParams &params
                                     [[buffer(2)]],
                                     uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];
  float3 position = base.position;
  float3 velocity = base.velocity;
  float3 acceleration = float3(0., -0.2, 0.);
  float3 positionNext = position + velocity * params.dt;
  float3 velocityNext = velocity + acceleration * params.dt;

  float3 areaCenter = float3(0., 0.5, 0.);
  float d = distance(positionNext, areaCenter);
  if (d < 1.2) {
    outputCodeBaseList[id].velocity = velocityNext;
    outputCodeBaseList[id].position = positionNext;
  } else {
    // reverse the velocity in the direction of the areaCenter
    float3 unit = normalize(areaCenter - positionNext);
    float3 vToCenter = dot(velocity, unit) * unit;
    float3 vPerp = velocity - vToCenter;
    float3 vVerticalReversed = vPerp - vToCenter * 0.98;
    outputCodeBaseList[id].velocity =
        vVerticalReversed + acceleration * params.dt;
  }
}

kernel void
updateSphereBouncingVertexes(device CubeBase *codeBaseList [[buffer(0)]],
                             device VertexData *outputVertices [[buffer(1)]],
                             device VertexData *previousVertices [[buffer(2)]],
                             constant MovingAttractorLineParams &params
                             [[buffer(3)]],
                             uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  if (cellInnerIdx == 0) {
    CubeBase base = codeBaseList[cellIdx];
    outputVertices[id].position =
        float3(base.position.x, base.position.y, base.position.z - 0.2) * 0.4;
  } else {
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}
