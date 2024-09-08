
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  float3 normal;
  float2 uv;
  bool atSide;
  bool leading;
  bool secondary;
  // float3 originalPosition;
};

struct MovingLorenzParams {
  float width;
  float dt;
};

// a Metal function of lorenz
float3 lorenzIteration(float3 p, float dt) {
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
float3 fourwingIteration(float3 p, float dt) {
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

// a metal function of aizawa
float3 aizawaIteration(float3 p, float dt) {
  float a = 0.95;
  float b = 0.7;
  float c = 0.6;
  float d0 = 3.5;
  float e = 0.25;
  float f = 0.1;

  float x = p.x;
  float y = p.y;
  float z = p.z;

  float dx = (z - b) * x - d0 * y;
  float dy = d0 * x + (z - b) * y;
  float dz = c + a * z - pow(z, 3.0) / 3.0 - (x * x + y * y) * (1. + e * z) + f * z * pow(x, 3.0);

  float3 d = float3(dx, dy, dz) * dt * 0.8;
  return p + d;
}

// a Metal function of dequan_li
float3 dequanLiIteration(float3 p, float dt) {
  float a = 40.0;
  float c = 11. / 6.;
  float d = 0.16;
  float e = 0.65;
  float k = 55.;
  float f = 20.;

  float x = p.x;
  float y = p.y;
  float z = p.z;

  float dx = a * (y - x) + d * x * z;
  x += dx * dt; // modification order is influential
  float dy = k * x + f * y - x * z;
  y += dy * dt;
  float dz = c * z + x * y - e * x * x;
  z += dz * dt;
  float3 dp = float3(dx, dy, dz) * dt;
  return p + dp;
}


kernel void updateMovingLorenz(
  device VertexData* vertices [[buffer(0)]],
  device VertexData *outputVertices [[buffer(1)]],
  constant MovingLorenzParams& params [[buffer(2)]],
  uint id [[thread_position_in_grid]])
{
  bool leading = vertices[id].leading;
  bool atSide = vertices[id].atSide;
  bool secondary = vertices[id].secondary;

  outputVertices[id].normal = vertices[id].normal;
  outputVertices[id].uv = vertices[id].uv;
  outputVertices[id].atSide = atSide;
  outputVertices[id].leading = leading;
  outputVertices[id].secondary = secondary;

  if (leading) {
    if (secondary) {
      outputVertices[id].position = vertices[id-2].position;
      return;
    }
    if (atSide) {
      float3 basePosition = vertices[id-1].position;
      // float3 nextPosition = fourwingIteration(basePosition, params.dt);
      float3 nextPosition = dequanLiIteration(basePosition, params.dt);
      outputVertices[id].position = nextPosition;
      outputVertices[id].position = nextPosition + float3(params.width, 0., 0.);
    } else {
      float3 basePosition = vertices[id].position;
      // float3 nextPosition = fourwingIteration(basePosition, params.dt);
      float3 nextPosition = dequanLiIteration(basePosition, params.dt);
      outputVertices[id].position = nextPosition;
    }
  } else {
    outputVertices[id].position = vertices[id - 4].position;
    return;
  }

}

