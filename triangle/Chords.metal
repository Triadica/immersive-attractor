
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

struct CellBase {
  float3 position;
  float3 center;
  float radius;
  float angle;
};

kernel void updateChordsBase(
    device CellBase *cellBaseList [[buffer(0)]],
    device CellBase *outputCellBaseList [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CellBase base = cellBaseList[id];
  float3 p0 = float3(0.0, 0.5, 0.0);
  float r0 = length(p0 - base.position);
  float3 p1 = p0 + float3(0.0, 0.0, -r0) * sin(params.timestamp * 0.2);

  float3 v_base_1 = p1 - base.position;
  float3 v_base_0 = p0 - base.position;
  float3 v_base_1_unit = normalize(v_base_1);
  float footOfPerpCoefficient = dot(v_base_0, v_base_1_unit);
  float3 footOfPerp = base.position + footOfPerpCoefficient * v_base_1_unit;
  float verticalDistance = length(footOfPerp - p0);
  float centersDistance = r0 * r0 / verticalDistance;
  float3 nextCenter = p0 + normalize(footOfPerp - p0) * centersDistance;
  float nextRadius = length(nextCenter - base.position);

  outputCellBaseList[id].center = nextCenter;
  outputCellBaseList[id].radius = nextRadius;
  outputCellBaseList[id].angle = atan2(r0, nextRadius);
}

kernel void updateChordsVertexes(
    device CellBase *cellBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingCubesParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  uint count = 21;
  float3 p0 = float3(0.0, 0.5, 0.0);

  uint cellIdx = id / count;
  uint groupIdx = id % count;
  CellBase base = cellBaseList[cellIdx];
  float arcAngle = 2.0 * base.angle;
  float radius = base.radius;

  float angle = arcAngle / float(count - 1) * float(groupIdx);
  float3 xAxis = normalize(base.position - base.center) * radius;
  float3 yAxis = normalize(p0 - base.position) * radius;
  float3 p = base.center + xAxis * cos(angle) + yAxis * sin(angle);

  outputVertices[id].position = p;
}
