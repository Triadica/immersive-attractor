
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  float3 originalPosition;
  float3 normal;
  float2 uv;
  bool atSide;
};

struct MovingLorenzParams {
  float width;
  float stripScale;
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


kernel void updateMovingLorenz(
  device VertexData* vertices [[buffer(0)]],
  constant MovingLorenzParams& params [[buffer(1)]],
  uint id [[thread_position_in_grid]])
{
  float3 basePosition = vertices[id].originalPosition;
  float3 nextPosition = fourwingIteration(basePosition, params.dt);
  vertices[id].originalPosition = nextPosition;
  if (vertices[id].atSide) {
    vertices[id].position = nextPosition * params.stripScale + float3(params.width, 0., 0.);
  } else {
    vertices[id].position = nextPosition * params.stripScale;
  }

}

