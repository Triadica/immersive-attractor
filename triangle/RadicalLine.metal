
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
    // float3 normal;
    // float2 uv;
};

struct MovingRadicalLineParams {
  int vertexPerCell;
  float dt;
};

struct CellBase {
  float3 position;
  float size;
  float3 velocity;
  float rotate;
};


  // a Metal function of lorenz
float3 radical_lorenzLineIteration(float3 p, float dt) {
  float tau = 10.0;
  float rou = 28.0;
  float beta = 8.0 / 3.0;

  float dx = tau * (p.y - p.x);
  float dy = p.x * (rou - p.z) - p.y;
  float dz = p.x * p.y - beta * p.z;
  float3 d = float3(dx, dy, dz) * dt;
  return p + d;
}

kernel void updateRadicalLineBase(
                                    device CellBase *codeBaseList [[buffer(0)]],
                                    device CellBase *outputCodeBaseList [[buffer(1)]],
                                    constant MovingRadicalLineParams &params [[buffer(2)]],
                                    uint id [[thread_position_in_grid]])
{
  if (id < 1) {
    outputCodeBaseList[id].position = float3(0., 0., 0.);
    return;
  }
  CellBase base = codeBaseList[id];
  float3 accerlation = -base.position * 20 / pow(length(base.position), 2);
  float3 v = base.velocity;
  float3 vNext = v + accerlation * params.dt;
  outputCodeBaseList[id].position = base.position + v * params.dt;
  outputCodeBaseList[id].velocity = vNext;
}


kernel void updateRadicalLineVertexes(
                                        device CellBase *codeBaseList [[buffer(0)]],
                                        device VertexData *outputVertices [[buffer(1)]],
                                        device VertexData *previousVertices [[buffer(2)]],
                                        constant MovingRadicalLineParams &params [[buffer(3)]],
                                        uint id [[thread_position_in_grid]])
{
  if (id < 1) {
    outputVertices[id].position = float3(0., 0., -4.);
    return;
  }
  outputVertices[id].position = codeBaseList[id].position + float3(0., 0., -4.);
}

