
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
};

struct SnowflakeBase {
  float3 position;
  float size;
  float3 axis;
  float rotate;
  float3 velocity;
};

/// divide by 6, each branch has 3 lines(6 vertexes), a main branch and 2 sub
/// branches, this is a snowflake, so the branch is a hexagon
static float3 getBranchVertex(uint verticeIdx) {
  uint groupIdx = verticeIdx / 6;
  uint branchIdx = verticeIdx % 6;
  float3 p = float3(0.0, 0.0, 0.0);
  switch (branchIdx) {
  case 0:
    p = float3(0.0, 0.0, 0.0);
    break;
  case 1:
    p = float3(1., 0, 0.0);
    break;
  case 2:
    p = float3(0.6, 0, 0.0);
    break;
  case 3:
    p = float3(0.6, 0, 0.0) + float3(0.5, 0.866, 0.0) * 0.5;
    break;
  case 4:
    p = float3(0.6, 0, 0.0);
    break;
  case 5:
    p = float3(0.6, 0, 0.0) + float3(0.5, -0.866, 0.0) * 0.5;
    break;
  default:
    break;
  }

  const float M_PI = 3.14159265358979323846;

  // rotate
  float angle = groupIdx * (M_PI / 3.0); // 60 degrees in radians
  float cosAngle = cos(angle);
  float sinAngle = sin(angle);
  float3 rotatedP = float3(
      p.x * cosAngle - p.y * sinAngle, p.x * sinAngle + p.y * cosAngle, p.z);

  return rotatedP;
}

kernel void updateSnowflakeBase(
    device SnowflakeBase *codeBaseList [[buffer(0)]],
    device SnowflakeBase *outputCodeBaseList [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  SnowflakeBase base = codeBaseList[id];
  device SnowflakeBase &output = outputCodeBaseList[id];

  if (base.position.y < -10.0) {
    output.position = base.position;
    output.position.y = 10.0;
  } else {
    output.position = base.position + base.velocity * 0.2 * params.dt;
  }

  output.rotate = base.rotate + 0.01;
  output.axis = base.axis;
  output.size = base.size;
  output.velocity = base.velocity;
}

// Rodrigues' rotation formula
static float3 rotate3D(float3 p, float3 axis, float angle) {
  float3 axisN = normalize(axis);
  float cosAngle = cos(angle);
  float sinAngle = sin(angle);
  float3 vAlongAxis = axisN * dot(axisN, p);
  float3 vOnPlane = p - vAlongAxis;
  float3 rotatedP =
      vOnPlane * cosAngle + cross(axisN, vOnPlane) * sinAngle + vAlongAxis;
  return rotatedP;
}

kernel void updateSnowflakeVertexes(
    device SnowflakeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  uint shapeVertexCount = 36;
  uint groupIdx = id / shapeVertexCount;
  SnowflakeBase base = codeBaseList[groupIdx];
  // vertice
  uint verticeIdx = id % shapeVertexCount;
  float3 vertice = getBranchVertex(verticeIdx);

  vertice = rotate3D(vertice, base.axis, base.rotate);

  float3 position = base.position + vertice * 0.1 * base.size;

  outputVertices[id].position = position;
}
