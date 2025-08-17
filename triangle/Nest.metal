
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

// 4D 连续随机噪声实现（时间维度变化缓慢）
float hash(float4 p) {
  // 使用简单但有效的哈希函数，针对4个维度都产生随机值
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * p.w * (p.x + p.y + p.z + p.w));
}

float noise4d(float4 p) {
  // 获取整数部分和小数部分
  float4 i = floor(p);
  float4 f = fract(p);

  // 使用smoothstep进行插值以确保连续性
  f = f * f * (3.0 - 2.0 * f);

  // 计算4D超立方体的16个角的哈希值
  float n0000 = hash(i + float4(0.0, 0.0, 0.0, 0.0));
  float n1000 = hash(i + float4(1.0, 0.0, 0.0, 0.0));
  float n0100 = hash(i + float4(0.0, 1.0, 0.0, 0.0));
  float n1100 = hash(i + float4(1.0, 1.0, 0.0, 0.0));
  float n0010 = hash(i + float4(0.0, 0.0, 1.0, 0.0));
  float n1010 = hash(i + float4(1.0, 0.0, 1.0, 0.0));
  float n0110 = hash(i + float4(0.0, 1.0, 1.0, 0.0));
  float n1110 = hash(i + float4(1.0, 1.0, 1.0, 0.0));
  float n0001 = hash(i + float4(0.0, 0.0, 0.0, 1.0));
  float n1001 = hash(i + float4(1.0, 0.0, 0.0, 1.0));
  float n0101 = hash(i + float4(0.0, 1.0, 0.0, 1.0));
  float n1101 = hash(i + float4(1.0, 1.0, 0.0, 1.0));
  float n0011 = hash(i + float4(0.0, 0.0, 1.0, 1.0));
  float n1011 = hash(i + float4(1.0, 0.0, 1.0, 1.0));
  float n0111 = hash(i + float4(0.0, 1.0, 1.0, 1.0));
  float n1111 = hash(i + float4(1.0, 1.0, 1.0, 1.0));

  // 4D线性插值 - 先在x方向插值
  float nx000 = mix(n0000, n1000, f.x);
  float nx100 = mix(n0100, n1100, f.x);
  float nx010 = mix(n0010, n1010, f.x);
  float nx110 = mix(n0110, n1110, f.x);
  float nx001 = mix(n0001, n1001, f.x);
  float nx101 = mix(n0101, n1101, f.x);
  float nx011 = mix(n0011, n1011, f.x);
  float nx111 = mix(n0111, n1111, f.x);

  // 再在y方向插值
  float nxy00 = mix(nx000, nx100, f.y);
  float nxy10 = mix(nx010, nx110, f.y);
  float nxy01 = mix(nx001, nx101, f.y);
  float nxy11 = mix(nx011, nx111, f.y);

  // 在z方向插值
  float nxyz0 = mix(nxy00, nxy10, f.z);
  float nxyz1 = mix(nxy01, nxy11, f.z);

  // 最后在时间维度（w）插值
  return mix(nxyz0, nxyz1, f.w);
}

// 分层噪声函数，为时间维度设置较慢的变化频率
float fractalNoise(float4 p) {
  float result = 0.0;
  float amplitude = 1.0;
  float maxValue = 0.0;

  // 3个八度的噪声叠加，时间维度使用较低的频率
  for (int i = 0; i < 3; i++) {
    float4 freq = float4(
        1.0, 1.0, 1.0, 0.8); // 时间维度频率提高到0.8，保持缓慢但可见的变化
    freq *= pow(2.0, float(i));

    result += amplitude * noise4d(p * freq);
    maxValue += amplitude;
    amplitude *= 0.5;
  }

  // 归一化到 [0, 1] 范围
  return result / maxValue;
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
  float spatialFreq = 0.1;
  // 提高时间变化频率，因为fractalNoise内部已经有时间缓慢控制
  float timeFreq = 0.5;

  float4 noisePos = float4(
      base.position.x * spatialFreq,
      base.position.y * spatialFreq,
      base.position.z * spatialFreq,
      params.timestamp * timeFreq);

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
  float lineLength = base.noiseValue * maxLineLength;

  // 计算最终位置：中心位置 + 顶点偏移 * 线段长度
  float3 position = base.position + vertice * lineLength;

  outputVertices[id].position = position;
}
