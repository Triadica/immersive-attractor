
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

struct CellBase {
  float theta;
  float phi;
  float index;
};

// based on math from https://www.youtube.com/watch?v=dkyvZo68IoM&t=647s
// theta in 0..2pi, phi in 0..pi, alpha in 0..4pi
// in which alpha is the angle of the torus, phi is the angle of the circle
static float3 hopfFibration(float alpha, float phi, float theta) {
  float sinV = sin(theta * 0.5);
  float cosV = cos(theta * 0.5);
  float x0 = cos((alpha + phi) * 0.5) * sinV;
  float x1 = sin((alpha + phi) * 0.5) * sinV;
  float x2 = cos((alpha - phi) * 0.5) * cosV;
  float x3 = sin((alpha - phi) * 0.5) * cosV;
  float divisor = 1 / (1 - x3);
  return float3(x0 * divisor, x1 * divisor, x2 * divisor);
}

kernel void updateHopfFibrationBase(
    device CellBase *codeBaseList [[buffer(0)]],
    device CellBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CellBase base = codeBaseList[id];
  device CellBase &output = outputCodeBaseList[id];

  float dt = params.dt;
  float i = log(1.0 + base.index) * dt;
  output.theta = base.theta + i * 0.02 + 0.01;
  output.phi = base.phi + i * 0.1;
}

kernel void updateHopfFibrationVertexes(
    device CellBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  float PI = 3.14159265359;
  float alpha = cellInnerIdx * 4 * PI / vertexPerCell;

  float theta = codeBaseList[cellIdx].theta;
  float phi = codeBaseList[cellIdx].phi;

  outputVertices[id].position =
      hopfFibration(alpha, phi, theta).xzy * 0.2 + float3(0, 0, -1);
}
