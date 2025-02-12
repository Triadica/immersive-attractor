
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingCubesParams {
  float width;
  float dt;
  float timestamp;
};

struct CubeBase {
  float3 position;
  float size;
  float rotate;
};

constant float3 cubeVertices[] = {
  float3( 1.0, 0.0, 0.0),
  float3( 0.0, 1.0, 0.0),
  float3(-1.0, 0.0, 0.0),
  float3( 0.0,-1.0, 0.0),
};

kernel void updatePolygonWallBase(
                            device CubeBase *codeBaseList [[buffer(0)]],
                            device CubeBase *outputCodeBaseList [[buffer(1)]],
                            constant MovingCubesParams &params [[buffer(2)]],
                            uint id [[thread_position_in_grid]])
{
  CubeBase base = codeBaseList[id];
  outputCodeBaseList[id].position.z = 0.2 * sin(base.rotate * params.timestamp * 0.4) - 0.6;

}


kernel void updatePolygonWallVertexes(
                               device CubeBase *codeBaseList [[buffer(0)]],
                               device VertexData *outputVertices [[buffer(1)]],
                               constant MovingCubesParams &params [[buffer(2)]],
                               uint id [[thread_position_in_grid]])
{
  uint cubeIdx = id / 4;
  CubeBase base = codeBaseList[cubeIdx];
  // vertice
  uint verticeIdx = id % 4;
  float3 vertice = cubeVertices[verticeIdx];

  float3 position = base.position + vertice * 2. * base.size;

  outputVertices[id].position = position;
}

