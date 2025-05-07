
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
  float timestamp;
};

struct CellBase {
  float3 position;
  float step;
  float3 velocity;
  float lifeValue;
};

static float simpleRand(float seed) { return fract(sin(seed) * 43758.5453123); }

static float randBalanced(float seed) { return simpleRand(seed) * 2.0 - 1.0; }

static float3 fiboGridN(float n, float total) {
  float z = (2.0 * n - 1.0) / total - 1.0;
  float t = sqrt(1.0 - z * z);
  float t2 = 2.0 * 3.14159265359 * 1.61803398875 * n;
  float x = t * cos(t2);
  float y = t * sin(t2);
  return float3(x, y, z);
}

kernel void updateFireworksBase(
    device CellBase *codeBaseList [[buffer(0)]],
    device CellBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CellBase base = codeBaseList[id];
  device CellBase &output = outputCodeBaseList[id];

  if (base.lifeValue <= 0.0) {
    // reset the position and velocity
    output.position = float3(0., 0.001, 0.);
    float a1 = simpleRand(float(id) + 1.2 * params.timestamp);
    float a2 = simpleRand(float(id) + 1.3 * params.timestamp);
    float3 v = fiboGridN(round(a1 * 9000), 9000);
    output.velocity = (float3(0., 2.4, 0.) + v * 0.2) * (0.5 + 0.5 * a2);
    output.lifeValue = 2.0 * (0.4 + simpleRand(float(id) + params.timestamp));
    output.step = 0.0;
  } else if (base.position.y <= 0.0) {
    output.velocity =
        float3(base.velocity.x, -base.velocity.y * 0.3, base.velocity.z);
    output.lifeValue = base.lifeValue - params.dt * 0.4;
    output.position.y = 0.001;
    output.step = base.step + 1.0;
  } else {
    output.position = base.position + base.velocity * params.dt;
    output.velocity = base.velocity + float3(0., -1.2, 0.) * params.dt;
    output.lifeValue = base.lifeValue - params.dt * 0.4;
    output.step = base.step + 1.0;
  }
}

kernel void updateFireworksVertexes(
    device CellBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  uint leadingIdx = cellIdx * vertexPerCell;
  // CellBase leadingBase = codeBaseList[leadingIdx];
  CellBase base = codeBaseList[cellIdx];

  if (cellInnerIdx == 0 || base.step <= 4) {
    outputVertices[id].position =
        float3(base.position.x, base.position.y, base.position.z - 1.) * 1. -
        float3(0., 1, 0.);
  } else {
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}
