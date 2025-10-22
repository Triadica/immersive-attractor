#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
};

struct SphereLineParams {
  int vertexPerCell;
  float dt;
  float sphereRadius;
  float3 controlPoint1;
  float3 controlPoint2;
  float3 controlPoint3;
  float3 controlPoint4;
};

struct SphereLineBase {
  float3 position;
  float size;
  float rotate;
};

// 计算点到控制点的2.4次方衰减速度
float calculateRotationSpeed(float3 position, float3 controlPoint, float baseFactor) {
  float3 diff = position - controlPoint;
  float distanceSquared = dot(diff, diff);
  float distance = sqrt(distanceSquared);
  // 避免除零，添加小的常数
  float distancePower2_ = pow(distance + 0.001, 2.0);
  float speed = baseFactor / distancePower2_;
  // 限制最大速度
  return min(speed, 20.0);
}

// 绕轴旋转函数
float3 rotateAroundAxis(float3 point, float3 axis, float angle) {
  // 确保轴向量是单位向量
  axis = normalize(axis);

  // 使用罗德里格旋转公式
  float cosAngle = cos(angle);
  float sinAngle = sin(angle);

  return point * cosAngle +
         cross(axis, point) * sinAngle +
         axis * dot(axis, point) * (1.0 - cosAngle);
}

// 将点投影到球面上
float3 projectToSphere(float3 point, float radius) {
  return normalize(point) * radius;
}

kernel void updateSphereLineBase(
    device SphereLineBase *currentBases [[buffer(0)]],
    device SphereLineBase *nextBases [[buffer(1)]],
    constant SphereLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {

  SphereLineBase current = currentBases[id];

  float baseSpeed = 0.008;
  // 计算到四个控制点的旋转速度
  float speed1 = calculateRotationSpeed(current.position, params.controlPoint1, baseSpeed);
  float speed2 = calculateRotationSpeed(current.position, params.controlPoint2, baseSpeed);
  float speed3 = calculateRotationSpeed(current.position, params.controlPoint3, baseSpeed);
  float speed4 = calculateRotationSpeed(current.position, params.controlPoint4, baseSpeed);

  // 计算旋转轴（从球心到控制点的方向）
  float3 axis1 = normalize(params.controlPoint1);
  float3 axis2 = normalize(params.controlPoint2);
  float3 axis3 = normalize(params.controlPoint3);
  float3 axis4 = normalize(params.controlPoint4);

  // 计算旋转角度
  float angle1 = speed1 * params.dt;
  float angle2 = speed2 * params.dt;
  float angle3 = speed3 * params.dt;
  float angle4 = speed4 * params.dt;

  // 分别绕四个轴旋转
  float3 newPosition = current.position;
  newPosition = rotateAroundAxis(newPosition, axis1, angle1);
  newPosition = rotateAroundAxis(newPosition, axis2, angle2);
  newPosition = rotateAroundAxis(newPosition, axis3, angle3);
  newPosition = rotateAroundAxis(newPosition, axis4, angle4);

  // 确保点仍在球面上
  newPosition = projectToSphere(newPosition, params.sphereRadius);

  // 更新旋转角度（用于其他可能的用途）
  float totalRotation = current.rotate + angle1 + angle2 + angle3 + angle4;

  nextBases[id] = SphereLineBase{
    .position = newPosition,
    .size = current.size,
    .rotate = totalRotation
  };
}

kernel void updateSphereLineVertexes(
    device SphereLineBase *sphereLineBases [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant SphereLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {

  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  if (cellInnerIdx == 0) {
    // 第一个顶点：线段起点，位于球面上
    SphereLineBase base = sphereLineBases[cellIdx];
    outputVertices[id].position = base.position;
  } else {
    // 其他顶点：从前一个顶点的位置继承，形成轨迹
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}