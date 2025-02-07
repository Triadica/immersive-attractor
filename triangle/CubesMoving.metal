
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  float3 normal;
  float2 uv;
  bool atSide;
  bool leading;
  bool secondary;
};

struct MovingCubesParams {
  float width;
  float dt;
};

struct CubeBase {
  float3 position;
  float size;
  float rotate;
};

constant float3 cubeVertices[] = {
  float3(-1.0, -1.0,  1.0),
  float3( 1.0, -1.0,  1.0),
  float3( 1.0, -1.0, -1.0),
  float3(-1.0, -1.0, -1.0),
  float3(-1.0,  1.0,  1.0),
  float3( 1.0,  1.0,  1.0),
  float3( 1.0,  1.0, -1.0),
  float3(-1.0,  1.0, -1.0),
};

kernel void updateCubeBase(
                            device CubeBase *codeBaseList [[buffer(0)]],
                            device CubeBase *outputCodeBaseList [[buffer(1)]],
                            constant MovingCubesParams &params [[buffer(2)]],
                            uint id [[thread_position_in_grid]])
{
  CubeBase base = codeBaseList[id];

  outputCodeBaseList[id].position.y = base.position.y + 0.001;
}


kernel void updateCubeVertexes(
                               device CubeBase *codeBaseList [[buffer(0)]],
                               device VertexData *outputVertices [[buffer(1)]],
                               constant MovingCubesParams &params [[buffer(2)]],
                               uint id [[thread_position_in_grid]])
{
  CubeBase base = codeBaseList[0];
  // vertice
  uint verticeIdx = id % 8;
  float3 vertice = cubeVertices[verticeIdx];

  float3 position = base.position + vertice * 0.2;

  outputVertices[id].position = position;
}

