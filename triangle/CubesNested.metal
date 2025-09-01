
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
  float time;
};

struct CubeBase {
  float3 center;
  float size;
  float3 rotationAxis;
  float rotationSpeed;
};

constant float3 cubeVertices[] = {
    float3(-1.0, -1.0, 1.0),
    float3(1.0, -1.0, 1.0),
    float3(1.0, -1.0, -1.0),
    float3(-1.0, -1.0, -1.0),
    float3(-1.0, 1.0, 1.0),
    float3(1.0, 1.0, 1.0),
    float3(1.0, 1.0, -1.0),
    float3(-1.0, 1.0, -1.0),
};

float3x3 rotationMatrix(float3 axis, float angle) {
  axis = normalize(axis);
  float s = sin(angle);
  float c = cos(angle);
  float oc = 1.0 - c;

  return float3x3(
      oc * axis.x * axis.x + c,
      oc * axis.x * axis.y - axis.z * s,
      oc * axis.z * axis.x + axis.y * s,
      oc * axis.x * axis.y + axis.z * s,
      oc * axis.y * axis.y + c,
      oc * axis.y * axis.z - axis.x * s,
      oc * axis.z * axis.x - axis.y * s,
      oc * axis.y * axis.z + axis.x * s,
      oc * axis.z * axis.z + c);
}

kernel void updateCubeNestedBase(
    device CubeBase *codeBaseList [[buffer(0)]],
    device CubeBase *outputCodeBaseList [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {

  // 保持立方体基础属性不变，只更新旋转角度通过时间处理
  outputCodeBaseList[id] = codeBaseList[id];
}

kernel void updateCubeNestedVertexes(
    device CubeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  uint cubeIdx = id / 8;
  CubeBase base = codeBaseList[cubeIdx];

  // 计算当前旋转角度
  float currentAngle = params.time * base.rotationSpeed;
  float3x3 rotation = rotationMatrix(base.rotationAxis, currentAngle);

  // 顶点索引
  uint verticeIdx = id % 8;
  float3 vertice = cubeVertices[verticeIdx];

  // 应用大小缩放
  vertice = vertice * base.size * 0.5; // 0.5 是为了让 size 代表边长的一半

  // 应用旋转
  vertice = rotation * vertice;

  // 添加中心位置
  float3 position = base.center + vertice;

  outputVertices[id].position = position;
}
