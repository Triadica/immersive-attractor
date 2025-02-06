//
//  CubesMoving.metal
//  triangle
//
//  Created by chen on 2025/2/6.
//


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

struct MovingCubesParams {
  float width;
  float dt;
};


  // a Metal function of fourwing
float3 fourwingIterationOld(float3 p, float dt) {
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

kernel void updateMovingCubes(
                               device VertexData* vertices [[buffer(0)]],
                               device VertexData *outputVertices [[buffer(1)]],
                               constant MovingCubesParams& params [[buffer(2)]],
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
      float3 nextPosition = fourwingIterationOld(basePosition, params.dt);
      outputVertices[id].position = nextPosition;
      outputVertices[id].position = nextPosition + float3(params.width, 0., 0.);
    } else {
      float3 basePosition = vertices[id].position;
      float3 nextPosition = fourwingIterationOld(basePosition, params.dt);

      outputVertices[id].position = nextPosition;
    }
  } else {
    outputVertices[id].position = vertices[id - 4].position;
    return;
  }

}

