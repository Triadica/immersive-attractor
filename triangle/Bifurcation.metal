
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
  int cellSize;
};

struct CubeBase {
  float3 position;
};

static float2 bifurcation(float a, float x, float y) {
  float beta = 0.25;

  // x ← a – y(β x + (1 – β) y)
  float x2 = a - y * (beta * x + (1.0 - beta) * y);
  // y ←x + y²/100
  float y2 = x + y * y / 100.0;

  return float2(x2, y2);
}

kernel void updateBifurcationBase(
    device CubeBase *codeBaseList [[buffer(0)]],
    device CubeBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];
  float3 position = base.position;

  float a = position.y * 0.1;
  float x = position.x * 0.2;
  float y = position.z * 0.2;

  float2 positionNext = bifurcation(a, x, y);

  outputCodeBaseList[id].position.x = positionNext.x * 5.0;
  outputCodeBaseList[id].position.z = positionNext.y * 5.0;
}

kernel void updateBifurcationVertexes(
    device CubeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  CubeBase base = codeBaseList[cellIdx];

  if (cellInnerIdx == 0) {
    outputVertices[id].position = base.position * 0.1 + float3(0.0, -0.5, -0.5);
  } else {
    outputVertices[id].position =
        base.position * 0.1 + float3(0.002, -0.5, -0.5);
  }
}
