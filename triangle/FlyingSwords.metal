
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  float3 color;
};

struct FlyingSwordsParams {
  float time;
  float dt;
};

struct SwordBase {
  float angle;     // Current angle in the circle (radians)
  float radius;    // Distance from center in XY plane
  float zOffset;   // Z offset (unused, all on same plane)
  float tiltAngle; // Unused, direction calculated to target
  int layer;       // Which layer (0, 1, 2, 3)
  float speed;     // Rotation speed multiplier
};

// Sword dimensions (越王勾践剑 style - 1.5m total length)
constant float bladeLength = 1.2;      // 剑身长度
constant float bladeWidthBase = 0.05;  // 剑身根部宽度
constant float bladeWidthMid = 0.04;   // 剑身中部宽度
constant float bladeWidthTip = 0.025;  // 剑身尖端宽度
constant float bladeThickness = 0.012; // 剑身厚度
constant float ridgeHeight = 0.016;    // 剑脊高度

constant float guardWidth = 0.09;      // 剑格宽度 (Y direction)
constant float guardLength = 0.03;     // 剑格长度 (X direction)
constant float guardThickness = 0.02;  // 剑格厚度 (Z direction)

constant float handleLength = 0.22;       // 剑柄长度
constant float handleWidthStart = 0.024;  // 剑柄起始宽度
constant float handleWidthEnd = 0.02;     // 剑柄末端宽度

constant float pommelRadius = 0.03;  // 剑首半径
constant float pommelLength = 0.03;  // 剑首长度

// 40 vertices for detailed sword with fully closed geometry
// Layout matches Swift swordTriangles indices:
//   0 = tip
//   1-4 = near-tip quad (top-left, top-right, bottom-left, bottom-right)
//   5-8 = mid-blade quad
//   9-14 = blade base (top-left, top-ridge, top-right, bot-left, bot-ridge, bot-right)
//   15-22 = guard (8 vertices: front TL,TR,BL,BR + back TL,TR,BL,BR)
//   23-30 = handle (8 vertices: front TL,TR,BL,BR + back TL,TR,BL,BR)
//   31-39 = pommel (8 octagonal + 1 center)
constant float3 swordVertices[40] = {
    // === BLADE ===
    // Tip (vertex 0)
    float3(bladeLength, 0.0, 0.0),
    
    // Near-tip quad (vertices 1-4): TL, TR, BL, BR
    float3(bladeLength * 0.75, bladeWidthTip * 0.5, bladeThickness * 0.5),   // 1
    float3(bladeLength * 0.75, bladeWidthTip * 0.5, -bladeThickness * 0.5),  // 2
    float3(bladeLength * 0.75, -bladeWidthTip * 0.5, bladeThickness * 0.5),  // 3
    float3(bladeLength * 0.75, -bladeWidthTip * 0.5, -bladeThickness * 0.5), // 4
    
    // Mid-blade quad (vertices 5-8): TL, TR, BL, BR
    float3(bladeLength * 0.4, bladeWidthMid * 0.5, bladeThickness * 0.5),    // 5
    float3(bladeLength * 0.4, bladeWidthMid * 0.5, -bladeThickness * 0.5),   // 6
    float3(bladeLength * 0.4, -bladeWidthMid * 0.5, bladeThickness * 0.5),   // 7
    float3(bladeLength * 0.4, -bladeWidthMid * 0.5, -bladeThickness * 0.5),  // 8
    
    // Blade base with ridges (vertices 9-14)
    float3(0.0, bladeWidthBase * 0.5, bladeThickness * 0.5),     // 9: top-left
    float3(0.0, 0.0, ridgeHeight),                                // 10: top-ridge
    float3(0.0, bladeWidthBase * 0.5, -bladeThickness * 0.5),    // 11: top-right
    float3(0.0, -bladeWidthBase * 0.5, bladeThickness * 0.5),    // 12: bottom-left
    float3(0.0, 0.0, -ridgeHeight),                               // 13: bottom-ridge
    float3(0.0, -bladeWidthBase * 0.5, -bladeThickness * 0.5),   // 14: bottom-right
    
    // === GUARD (剑格) - closed box (vertices 15-22) ===
    // Front face (at blade base position, X=0)
    float3(0.0, guardWidth * 0.5, guardThickness * 0.5),           // 15: front TL
    float3(0.0, -guardWidth * 0.5, guardThickness * 0.5),          // 16: front TR
    float3(0.0, guardWidth * 0.5, -guardThickness * 0.5),          // 17: front BL
    float3(0.0, -guardWidth * 0.5, -guardThickness * 0.5),         // 18: front BR
    // Back face (X = -guardLength)
    float3(-guardLength, guardWidth * 0.5, guardThickness * 0.5),   // 19: back TL
    float3(-guardLength, -guardWidth * 0.5, guardThickness * 0.5),  // 20: back TR
    float3(-guardLength, guardWidth * 0.5, -guardThickness * 0.5),  // 21: back BL
    float3(-guardLength, -guardWidth * 0.5, -guardThickness * 0.5), // 22: back BR
    
    // === HANDLE (剑柄) - tapered rectangular prism (vertices 23-30) ===
    // Front face (connected to guard back)
    float3(-guardLength, handleWidthStart * 0.5, handleWidthStart * 0.5),   // 23
    float3(-guardLength, -handleWidthStart * 0.5, handleWidthStart * 0.5),  // 24
    float3(-guardLength, handleWidthStart * 0.5, -handleWidthStart * 0.5),  // 25
    float3(-guardLength, -handleWidthStart * 0.5, -handleWidthStart * 0.5), // 26
    // Back face (tapered smaller)
    float3(-guardLength - handleLength, handleWidthEnd * 0.5, handleWidthEnd * 0.5),   // 27
    float3(-guardLength - handleLength, -handleWidthEnd * 0.5, handleWidthEnd * 0.5),  // 28
    float3(-guardLength - handleLength, handleWidthEnd * 0.5, -handleWidthEnd * 0.5),  // 29
    float3(-guardLength - handleLength, -handleWidthEnd * 0.5, -handleWidthEnd * 0.5), // 30
    
    // === POMMEL (剑首) - octagonal cap with center (vertices 31-39) ===
    float3(-guardLength - handleLength - pommelLength, pommelRadius, 0.0),                          // 31: +Y
    float3(-guardLength - handleLength - pommelLength, pommelRadius * 0.707, pommelRadius * 0.707), // 32
    float3(-guardLength - handleLength - pommelLength, 0.0, pommelRadius),                          // 33: +Z
    float3(-guardLength - handleLength - pommelLength, -pommelRadius * 0.707, pommelRadius * 0.707),// 34
    float3(-guardLength - handleLength - pommelLength, -pommelRadius, 0.0),                         // 35: -Y
    float3(-guardLength - handleLength - pommelLength, -pommelRadius * 0.707, -pommelRadius * 0.707),//36
    float3(-guardLength - handleLength - pommelLength, 0.0, -pommelRadius),                         // 37: -Z
    float3(-guardLength - handleLength - pommelLength, pommelRadius * 0.707, -pommelRadius * 0.707),// 38
    float3(-guardLength - handleLength - pommelLength, 0.0, 0.0),                                   // 39: center
};

// Golden mesh pattern function
float goldenPattern(float3 pos, float time, int swordIdx) {
  // Create mesh/lattice pattern based on position
  float scale = 30.0;
  float px = pos.x * scale + float(swordIdx) * 1.7;
  float py = pos.y * scale;
  float pz = pos.z * scale;
  
  // Diamond/rhombus mesh pattern
  float pattern1 = sin(px + py * 2.0 + time * 0.5) * sin(pz * 3.0 - time * 0.3);
  float pattern2 = sin(px * 2.0 - py + time * 0.4) * cos(pz * 2.0 + time * 0.2);
  
  // Combine patterns for mesh-like appearance
  float mesh = max(pattern1, pattern2);
  mesh = smoothstep(0.3, 0.7, mesh);
  
  return mesh;
}

// Determine vertex color based on part of sword
float3 getSwordColor(uint vertexIdx, float3 localPos, float time, int swordIdx) {
  // Base emerald green for blade
  float3 bladeColor = float3(0.2, 1.0, 0.4);
  
  // Dark bronze/brown base for guard and handle
  float3 guardBase = float3(0.25, 0.15, 0.08);
  float3 handleBase = float3(0.18, 0.10, 0.05);
  float3 pommelBase = float3(0.3, 0.18, 0.1);
  
  // Gold color for patterns
  float3 goldColor = float3(1.0, 0.85, 0.3);
  float3 brightGold = float3(1.0, 0.95, 0.5);
  
  // Blade vertices (0-14)
  if (vertexIdx <= 14) {
    return bladeColor;
  }
  // Guard vertices (15-22)
  else if (vertexIdx <= 22) {
    float pattern = goldenPattern(localPos, time, swordIdx);
    // Add some decorative lines on guard
    float edgeGlow = smoothstep(0.03, 0.04, abs(localPos.y));
    pattern = max(pattern, 1.0 - edgeGlow);
    return mix(guardBase, goldColor, pattern * 0.7);
  }
  // Handle vertices (23-30)
  else if (vertexIdx <= 30) {
    float pattern = goldenPattern(localPos * 1.5, time, swordIdx);
    // Spiral pattern along handle length
    float handleX = -localPos.x - guardLength;
    float spiral = sin(handleX * 40.0 + atan2(localPos.y, localPos.z) * 3.0 + time * 0.5);
    spiral = smoothstep(0.2, 0.6, spiral * 0.5 + 0.5);
    pattern = max(pattern, spiral * 0.8);
    return mix(handleBase, brightGold, pattern * 0.6);
  }
  // Pommel vertices (31-39)
  else {
    float pattern = goldenPattern(localPos * 2.0, time, swordIdx);
    // Radial pattern on pommel
    float angle = atan2(localPos.y, localPos.z);
    float radial = sin(angle * 8.0 + time * 0.3);
    radial = smoothstep(0.0, 0.5, radial * 0.5 + 0.5);
    pattern = max(pattern, radial);
    return mix(pommelBase, goldColor, pattern * 0.65);
  }
}

kernel void updateSwordVertexes(
    device SwordBase *swordList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant FlyingSwordsParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {

  uint swordIdx = id / 40; // 40 vertices per sword
  uint vertexIdx = id % 40;

  SwordBase sword = swordList[swordIdx];

  // Get base vertex position (sword along +X, blade edge in Y)
  float3 localPos = swordVertices[vertexIdx];
  
  // Calculate color based on vertex position and part of sword
  float3 vertexColor = getSwordColor(vertexIdx, localPos, params.time, int(swordIdx));

  // Rotate sword to point forward (-Z direction)
  // Swap: X -> -Z, Y -> Y, Z -> X
  float3 rotatedToForward = float3(localPos.z, localPos.y, -localPos.x);

  // Calculate current rotation angle based on time (very slow)
  float currentAngle = sword.angle + params.time * sword.speed;

  // Position on the circle in XY plane (z=0 in local space)
  float3 circlePos = float3(
      cos(currentAngle) * sword.radius, sin(currentAngle) * sword.radius, 0.0);

  // Final position: circle position + rotated local position
  float3 finalPos = circlePos + rotatedToForward;

  outputVertices[id].position = finalPos;
  outputVertices[id].color = vertexColor;
}
