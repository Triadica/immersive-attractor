
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
};

struct NestBase {
  float3 position;
  float size;
  float noiseValue; // 0~1之间的值，控制线段长度
};

// 改进的4D Perlin噪声函数（包含时间维度）
float hash(float4 p) {
  p = float4(
      dot(p, float4(127.1, 311.7, 74.7, 269.5)),
      dot(p, float4(269.5, 183.3, 246.1, 127.1)),
      dot(p, float4(113.5, 271.9, 124.6, 183.3)),
      dot(p, float4(74.7, 246.1, 311.7, 113.5)));
  return fract(sin(dot(p, float4(1.0, 57.0, 113.0, 43.0))) * 43758.5453123);
}

float noise4d(float4 p) {
  float4 i = floor(p);
  float4 f = fract(p);

  // 4D平滑插值
  f = f * f * (3.0 - 2.0 * f);

  // 16个超立方体角的哈希值
  float n0000 = hash(i + float4(0, 0, 0, 0));
  float n1000 = hash(i + float4(1, 0, 0, 0));
  float n0100 = hash(i + float4(0, 1, 0, 0));
  float n1100 = hash(i + float4(1, 1, 0, 0));
  float n0010 = hash(i + float4(0, 0, 1, 0));
  float n1010 = hash(i + float4(1, 0, 1, 0));
  float n0110 = hash(i + float4(0, 1, 1, 0));
  float n1110 = hash(i + float4(1, 1, 1, 0));
  float n0001 = hash(i + float4(0, 0, 0, 1));
  float n1001 = hash(i + float4(1, 0, 0, 1));
  float n0101 = hash(i + float4(0, 1, 0, 1));
  float n1101 = hash(i + float4(1, 1, 0, 1));
  float n0011 = hash(i + float4(0, 0, 1, 1));
  float n1011 = hash(i + float4(1, 0, 1, 1));
  float n0111 = hash(i + float4(0, 1, 1, 1));
  float n1111 = hash(i + float4(1, 1, 1, 1));

  // 4D线性插值
  float nx000 = mix(n0000, n1000, f.x);
  float nx100 = mix(n0100, n1100, f.x);
  float nx010 = mix(n0010, n1010, f.x);
  float nx110 = mix(n0110, n1110, f.x);
  float nx001 = mix(n0001, n1001, f.x);
  float nx101 = mix(n0101, n1101, f.x);
  float nx011 = mix(n0011, n1011, f.x);
  float nx111 = mix(n0111, n1111, f.x);

  float nxy00 = mix(nx000, nx100, f.y);
  float nxy10 = mix(nx010, nx110, f.y);
  float nxy01 = mix(nx001, nx101, f.y);
  float nxy11 = mix(nx011, nx111, f.y);

  float nxyz0 = mix(nxy00, nxy10, f.z);
  float nxyz1 = mix(nxy01, nxy11, f.z);

  return mix(nxyz0, nxyz1, f.w);
}

// 分层噪声函数，提供更丰富的变化
float fractalNoise(float4 p) {
  float result = 0.0;
  float amplitude = 1.0;
  float frequency = 1.0;

  // 3个八度的噪声叠加
  for (int i = 0; i < 3; i++) {
    result += amplitude * noise4d(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }

  return result;
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
  float timeFreq = 0.1;      // 时间变化频率（缓慢变化）

  float4 noisePos = float4(
      base.position.x * spatialFreq,
      base.position.y * spatialFreq,
      base.position.z * spatialFreq,
      params.dt * timeFreq // 时间维度
  );

  // 使用分层噪声获得更丰富的变化
  float rawNoise = fractalNoise(noisePos);

  // 将噪声值从 [-1, 1] 映射到 [0, 1]，然后应用非线性变换
  rawNoise = (rawNoise + 1.0) * 0.5;

  // 使用三次方变换增强对比度，让更多立方体接近0或1
  float enhancedNoise = rawNoise * rawNoise * rawNoise;

  // 进一步增强对比：低于0.3的变为接近0，高于0.7的变为接近1
  if (enhancedNoise < 0.3) {
    enhancedNoise = enhancedNoise * enhancedNoise; // 让小值更小
  } else if (enhancedNoise > 0.7) {
    enhancedNoise =
        1.0 - (1.0 - enhancedNoise) * (1.0 - enhancedNoise); // 让大值更大
  }

  outputNestBaseList[id].noiseValue = enhancedNoise;
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
