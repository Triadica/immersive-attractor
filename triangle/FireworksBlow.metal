
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
  // when lifetime is 0, it will be reset
  float lifeValue;
  // make a bounce effect
  float bounceChance;
};

static float simpleRand(float seed) { return fract(sin(seed) * 43758.5453123); }

static float3 fiboGridN(float n, float total) {
  float z = (2.0 * n - 1.0) / total - 1.0;
  float t = sqrt(1.0 - z * z);
  float t2 = 2.0 * 3.14159265359 * 1.61803398875 * n;
  float x = t * cos(t2);
  float y = t * sin(t2);
  return float3(x, y, z);
}

kernel void updateFireworksBlowBase(
    device CellBase *codeBaseList [[buffer(0)]],
    device CellBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CellBase base = codeBaseList[id];
  device CellBase &output = outputCodeBaseList[id];
  float idf = float(id);

  if (base.lifeValue <= 0.0) {
    // reset the position and velocity
    output.position = float3(0., 1.5, 0.);
    float a1 = simpleRand(idf - 1.2 * params.timestamp);
    float a2 = simpleRand(1.3 * params.timestamp);
    float a3 = simpleRand(1.4 * params.timestamp);
    float a4 = simpleRand(2.5 * params.timestamp);
    float directions = (0.02 + simpleRand(3.6 * params.timestamp)) * 200;
    float3 v = fiboGridN(round(a1 * directions), directions);
    output.velocity = float3(0., 0.5, 0.) + v * (0.5 + a4 * 0.2);
    output.lifeValue = 4. * (0.1 + a2);
    output.step = 0.0;
    output.bounceChance = output.lifeValue - 1.2 * (a3 + 0.1);
  } else if (base.position.y <= 0.0) {
    output.velocity =
        float3(base.velocity.x, -base.velocity.y * 0.3, base.velocity.z);
    output.lifeValue = base.lifeValue - params.dt * 0.4;
    output.position.y = 0.001;
    output.step = base.step + 1.0;
    output.bounceChance = base.bounceChance;
  } else if (base.lifeValue <= base.bounceChance) {
    float a1 = simpleRand(idf - 2.2 * params.timestamp);
    float a2 = simpleRand(idf - 3.3 * params.timestamp);
    float directions = (0.5 + simpleRand(3.6 * params.timestamp)) * 600;
    float3 v = fiboGridN(a1 * directions, directions);
    output.velocity = 0.5 * base.velocity + v * (0.1 + a2 * 0.6);
    output.lifeValue = base.lifeValue - params.dt * 0.4;
    output.step = base.step + 1.0;
    output.bounceChance = -1.;
    output.position = base.position + base.velocity * params.dt;
  } else {
    float v = length(base.velocity);
    output.position = base.position + base.velocity * params.dt;
    output.velocity = base.velocity + float3(0., -0.2, 0.) * params.dt;
    output.lifeValue = base.lifeValue - params.dt * 0.4;
    output.step = base.step + 1.0;
    output.bounceChance = base.bounceChance;
  }
}

kernel void updateFireworksBlowVertexes(
    device CellBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint leadingIdx = cellIdx * vertexPerCell;
  uint cellInnerIdx = id - leadingIdx;

  CellBase base = codeBaseList[cellIdx];

  if (base.step <= 4 || cellInnerIdx == 0) {
    outputVertices[id].position =
        float3(base.position.x, base.position.y - 1, base.position.z - 1.);
  } else {
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}
