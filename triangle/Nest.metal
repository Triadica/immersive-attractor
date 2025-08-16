
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingNestParams {
  float width;
  float dt;
  float timestamp;
};

struct NestBase {
  float3 position;
  float size;
  float noiseValue; // 0~1之间的值，控制线段长度
};

// 4D Simplex噪声函数（包含时间维度）
float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }

float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }

float4 taylorInvSqrt(float4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

float4 grad4(float j, float4 ip) {
  const float4 ones = float4(1.0, 1.0, 1.0, -1.0);
  float4 p, s;

  p.xyz = floor(fract(float3(j) * ip.xyz) * 7.0) * ip.z - 1.0;
  p.w = 1.5 - dot(abs(p.xyz), ones.xyz);
  s = float4(step(0.0, p));
  p.xyz = p.xyz + (s.xyz * 2.0 - 1.0) * s.www;

  return p;
}

float noise4d(float4 v) {
  const float2 C = float2(0.138196601125011, 0.276393202250021);

  // First corner
  float4 i = floor(v + dot(v, float4(0.309016994374947451)));
  float4 x0 = v - i + dot(i, C.xxxx);

  // Other corners
  float4 i0;
  float3 isX = step(x0.yzw, x0.xxx);
  float3 isYZ = step(x0.zww, x0.yyz);
  i0.x = isX.x + isX.y + isX.z;
  i0.yzw = 1.0 - isX;
  i0.y += isYZ.x + isYZ.y;
  i0.zw += 1.0 - isYZ.xy;
  i0.z += isYZ.z;
  i0.w += 1.0 - isYZ.z;

  // i0 now contains the unique values 0,1,2,3 in each channel
  float4 i3 = clamp(i0, 0.0, 1.0);
  float4 i2 = clamp(i0 - 1.0, 0.0, 1.0);
  float4 i1 = clamp(i0 - 2.0, 0.0, 1.0);

  float4 x1 = x0 - i1 + C.xxxx;
  float4 x2 = x0 - i2 + 2.0 * C.xxxx;
  float4 x3 = x0 - i3 + 3.0 * C.xxxx;
  float4 x4 = x0 - 1.0 + 4.0 * C.xxxx;

  // Permutations
  i = mod289(i);
  float j0 = permute(permute(permute(permute(i.w) + i.z) + i.y) + i.x).x;
  float4 j1 = permute(
      permute(
          permute(
              permute(i.w + float4(i1.w, i2.w, i3.w, 1.0)) + i.z +
              float4(i1.z, i2.z, i3.z, 1.0)) +
          i.y + float4(i1.y, i2.y, i3.y, 1.0)) +
      i.x + float4(i1.x, i2.x, i3.x, 1.0));

  // Gradients: 7x7x6 points over a cube, mapped onto a 4-cross polytope
  float4 ip = float4(1.0 / 294.0, 1.0 / 49.0, 1.0 / 7.0, 0.0);

  float4 p0 = grad4(j0, ip);
  float4 p1 = grad4(j1.x, ip);
  float4 p2 = grad4(j1.y, ip);
  float4 p3 = grad4(j1.z, ip);
  float4 p4 = grad4(j1.w, ip);

  // Normalise gradients
  float4 norm =
      taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;
  p4 *= taylorInvSqrt(dot(p4, p4));

  // Mix contributions from the five corners
  float3 m0 = max(0.6 - float3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
  float2 m1 = max(0.6 - float2(dot(x3, x3), dot(x4, x4)), 0.0);
  m0 = m0 * m0;
  m1 = m1 * m1;

  return 49.0 * (dot(m0 * m0, float3(dot(p0, x0), dot(p1, x1), dot(p2, x2))) +
                 dot(m1 * m1, float2(dot(p3, x3), dot(p4, x4))));
}

// 分层Simplex噪声函数，提供更丰富的变化
float fractalNoise(float4 p) {
  float result = 0.0;
  float amplitude = 1.0;
  float frequency = 1.0;

  // 3个八度的Simplex噪声叠加
  for (int i = 0; i < 3; i++) {
    result += amplitude * noise4d(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }

  // 将噪声值从 [-1, 1] 映射到 [0, 1]
  return (result + 1.0) * 0.5;
}
// 定义立方体中心的7条线段的14个顶点
// 3条轴向线段 + 4条对角线段
constant float3 nestVertices[] = {
    // X axis line (2 vertices)
    float3(-1.0, 0.0, 0.0), // 0
    float3(1.0, 0.0, 0.0),  // 1
    // Y axis line (2 vertices)
    float3(0.0, -1.0, 0.0), // 2
    float3(0.0, 1.0, 0.0),  // 3
    // Z axis line (2 vertices)
    float3(0.0, 0.0, -1.0), // 4
    float3(0.0, 0.0, 1.0),  // 5
    // Diagonal line 1 (2 vertices)
    float3(-1.0, -1.0, -1.0), // 6
    float3(1.0, 1.0, 1.0),    // 7
    // Diagonal line 2 (2 vertices)
    float3(1.0, -1.0, -1.0), // 8
    float3(-1.0, 1.0, 1.0),  // 9
    // Diagonal line 3 (2 vertices)
    float3(-1.0, 1.0, -1.0), // 10
    float3(1.0, -1.0, 1.0),  // 11
    // Diagonal line 4 (2 vertices)
    float3(1.0, 1.0, -1.0), // 12
    float3(-1.0, -1.0, 1.0) // 13
};

kernel void updateNestBase(
    device NestBase *nestBaseList [[buffer(0)]],
    device NestBase *outputNestBaseList [[buffer(1)]],
    constant MovingNestParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  NestBase base = nestBaseList[id];

  // 保持网格位置不变
  outputNestBaseList[id].position = base.position;
  outputNestBaseList[id].size = base.size;

  // 使用4D噪声（3D位置 + 1D时间）
  // 调整空间频率以在米级尺度上产生明显变化
  float spatialFreq = 100.0; // 每0.1米一个噪声周期
  float timeFreq = 1.;       // 时间变化频率（缓慢变化）

  float4 noisePos = float4(
      base.position.x * spatialFreq,
      base.position.y * spatialFreq,
      base.position.z * spatialFreq,
      params.dt * params.timestamp);

  outputNestBaseList[id].noiseValue = fractalNoise(noisePos);
}

kernel void updateNestVertexes(
    device NestBase *nestBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant MovingNestParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  uint nestIdx = id / 14; // 每个nest现在有14个顶点
  NestBase base = nestBaseList[nestIdx];

  // 获取当前顶点在nest中的索引
  uint verticeIdx = id % 14;
  float3 vertice = nestVertices[verticeIdx];

  // 根据噪声值调整线段长度
  // 网格间距是0.5米，所以最大线段长度应该是0.25米（半个网格间距）
  // 这样当noiseValue=1时，线段从中心延伸0.25米，刚好填满网格空间
  // 当noiseValue=0时，线段长度为0（不显示）
  float maxLineLength = 0.25; // 网格间距的一半
  float lineLength = base.noiseValue * maxLineLength * 0.25;

  // 计算最终位置：中心位置 + 顶点偏移 * 线段长度
  float3 position = base.position + vertice * lineLength;

  outputVertices[id].position = position;
}
