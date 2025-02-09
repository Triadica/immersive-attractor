
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
  float rotate;
};


// a Metal function of lorenz
float3 lorenzLineIteration(float3 p, float dt) {
  float tau = 10.0;
  float rou = 28.0;
  float beta = 8.0 / 3.0;

  float dx = tau * (p.y - p.x);
  float dy = p.x * (rou - p.z) - p.y;
  float dz = p.x * p.y - beta * p.z;
  float3 d = float3(dx, dy, dz) * dt;
  return p + d;
}


// a Metal function of fourwing
float3 fourwingLineIteration(float3 p, float dt) {
  float a = 0.2;
  float b = 0.01;
  float c = -0.4;
  float x = p.x;
  float y = p.y;
  float z = p.z;
  float dx = a * x + y * z;
  float dy = b * x + c * y - x * z;
  float dz = -z - x * y;
  float3 d = float3(dx, dy, dz) * dt;
  return p + d;
}

kernel void updateAttractorLineBase(
                           device CubeBase *codeBaseList [[buffer(0)]],
                           device CubeBase *outputCodeBaseList [[buffer(1)]],
                           constant MovingAttractorLineParams &params [[buffer(2)]],
                           uint id [[thread_position_in_grid]])
{
  CubeBase base = codeBaseList[id];
  outputCodeBaseList[id].position = fourwingLineIteration(base.position, params.dt);
}


kernel void updateAttractorLineVertexes(
                               device CubeBase *codeBaseList [[buffer(0)]],
                               device VertexData *outputVertices [[buffer(1)]],
                               device VertexData *previousVertices [[buffer(2)]],
                               constant MovingAttractorLineParams &params [[buffer(3)]],
                               uint id [[thread_position_in_grid]])
{
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  if (cellInnerIdx == 0) {
    CubeBase base = codeBaseList[cellIdx];
    outputVertices[id].position = float3(base.position.x, base.position.y, base.position.z-4.) * 0.2;
  } else {
    outputVertices[id].position = previousVertices[id-1].position;
  }

}

