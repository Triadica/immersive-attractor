
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
  float angle;        // Current angle in the circle (radians)
  float radius;       // Distance from center in XY plane
  float zOffset;      // Z offset (unused, all on same plane)
  float tiltAngle;    // Unused, direction calculated to target
  int layer;          // Which layer (0, 1, 2, 3)
  float speed;        // Rotation speed multiplier
  
  // Launch state
  float launchDelay;   // Random delay before launching (0~0.4s)
  float launchSpeed;   // Speed toward target (2~4 m/s)
  float launchTime;    // Time when launch was triggered (-1 = not launched)
  float3 launchStartPos; // Position when launch started
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

// Circle elevation above target height
constant float circleYOffset = 4.0;

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

// Generate golden mesh pattern for blade
float bladeGoldenMesh(float3 localPos, float time, int swordIdx) {
  // Diamond/rhombus mesh pattern along blade
  float bladeX = localPos.x; // Position along blade length
  float bladeY = localPos.y; // Position across blade width
  
  // Create diamond mesh grid
  float freq = 25.0; // Diamond frequency
  float diagonal1 = sin((bladeX + bladeY) * freq);
  float diagonal2 = sin((bladeX - bladeY) * freq);
  
  // Combine to create mesh intersections
  float mesh = max(diagonal1, diagonal2);
  mesh = smoothstep(0.7, 0.95, mesh); // Thin lines
  
  // Fade pattern near tip and edges
  float tipFade = smoothstep(0.0, 0.3, bladeX); // Fade near tip
  float edgeFade = 1.0 - smoothstep(0.02, 0.04, abs(bladeY)); // Stronger near center
  
  return mesh * tipFade * (0.5 + edgeFade * 0.5);
}

// Determine vertex color based on part of sword
float3 getSwordColor(uint vertexIdx, float3 localPos, float time, int swordIdx) {
  // Base emerald green for blade
  float3 bladeBase = float3(0.15, 0.85, 0.35);
  // Gold color for blade mesh pattern
  float3 bladeGold = float3(0.9, 0.75, 0.25);
  
  // Deep teal/jade green for hilt parts (darker, more blue-green)
  float3 guardBase = float3(0.05, 0.25, 0.2);   // Deep teal for guard
  float3 handleBase = float3(0.03, 0.18, 0.15); // Darker teal for handle
  float3 pommelBase = float3(0.06, 0.28, 0.22); // Slightly lighter for pommel
  
  // Turquoise gold accent for hilt patterns
  float3 hiltAccent = float3(0.4, 0.7, 0.5);    // Jade green highlight
  float3 goldAccent = float3(0.7, 0.6, 0.25);   // Muted gold
  
  // Blade vertices (0-14)
  if (vertexIdx <= 14) {
    // Add golden mesh pattern to blade
    float meshPattern = bladeGoldenMesh(localPos, time, swordIdx);
    return mix(bladeBase, bladeGold, meshPattern * 0.8);
  }
  // Guard vertices (15-22)
  else if (vertexIdx <= 22) {
    float pattern = goldenPattern(localPos, time, swordIdx);
    // Add decorative edge lines on guard
    float edgeGlow = smoothstep(0.03, 0.04, abs(localPos.y));
    pattern = max(pattern, 1.0 - edgeGlow);
    // Geometric pattern
    float geo = sin(localPos.y * 80.0) * sin(localPos.z * 80.0);
    geo = smoothstep(0.3, 0.7, geo * 0.5 + 0.5);
    pattern = max(pattern * 0.6, geo * 0.4);
    return mix(guardBase, hiltAccent, pattern * 0.5);
  }
  // Handle vertices (23-30)
  else if (vertexIdx <= 30) {
    // Spiral wrap pattern along handle
    float handleX = -localPos.x - guardLength;
    float spiral = sin(handleX * 50.0 + atan2(localPos.y, localPos.z) * 4.0);
    spiral = smoothstep(0.4, 0.8, spiral * 0.5 + 0.5);
    // Cross-hatch pattern
    float crossA = sin(handleX * 30.0 + localPos.y * 100.0);
    float crossB = sin(handleX * 30.0 - localPos.y * 100.0);
    float cross = max(crossA, crossB);
    cross = smoothstep(0.6, 0.9, cross * 0.5 + 0.5);
    float pattern = max(spiral * 0.7, cross * 0.5);
    return mix(handleBase, mix(hiltAccent, goldAccent, 0.3), pattern * 0.45);
  }
  // Pommel vertices (31-39)
  else {
    // Radial sunburst pattern on pommel
    float angle = atan2(localPos.y, localPos.z);
    float radial = sin(angle * 12.0);
    radial = smoothstep(0.2, 0.7, radial * 0.5 + 0.5);
    // Concentric rings
    float dist = length(float2(localPos.y, localPos.z));
    float rings = sin(dist * 150.0);
    rings = smoothstep(0.5, 0.9, rings * 0.5 + 0.5);
    float pattern = max(radial * 0.6, rings * 0.4);
    return mix(pommelBase, hiltAccent, pattern * 0.5);
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

  // Calculate current rotation angle based on time (very slow)
  float currentAngle = sword.angle + params.time * sword.speed;

  // Default circling position on the XY plane (elevated by circleYOffset)
  float3 circlePos = float3(
      cos(currentAngle) * sword.radius, 
      sin(currentAngle) * sword.radius + circleYOffset, 
      0.0);
  
  // Target position for aiming (center of target area)
  float3 targetPos = float3(0.0, 0.0, -12.0);
  
  // Calculate direction from current circle position to target (for aiming while circling)
  float3 aimDirection = normalize(targetPos - circlePos);
  
  // Create rotation matrix to point sword toward target
  float3 up = float3(0, 1, 0);
  float3 aimRight = normalize(cross(up, aimDirection));
  float3 aimUp = cross(aimDirection, aimRight);
  
  // Transform local position: X axis (sword length) points toward target
  float3 rotatedToTarget = localPos.x * aimDirection + localPos.y * aimUp + localPos.z * aimRight;
  
  float3 finalPos;
  
  // Check if sword is in launch mode
  if (sword.launchTime >= 0.0) {
    float timeSinceLaunch = params.time - sword.launchTime;
    float effectiveTime = timeSinceLaunch - sword.launchDelay;
    
    if (effectiveTime > 0.0) {
      // Sword is actively flying
      // Target position with slight perturbation based on sword index for spread effect
      float perturbX = sin(float(swordIdx) * 1.7) * 0.0625;  // +/- 0.0625m spread in X
      float perturbY = cos(float(swordIdx) * 2.3) * 0.0625;  // +/- 0.0625m spread in Y
      float3 flyTargetPos = float3(perturbX, perturbY, -12.0);
      
      // Calculate direction from start to target
      float3 startPos = sword.launchStartPos;
      float3 direction = normalize(flyTargetPos - startPos);
      
      // Move toward target
      float distance = effectiveTime * sword.launchSpeed;
      float3 newPos = startPos + direction * distance;
      
      // Rotate sword to point toward target (tip forward)
      float3 flyRight = normalize(cross(up, direction));
      float3 flyUp = cross(direction, flyRight);
      
      // Transform local position to world orientation
      float3 rotatedPos = localPos.x * direction + localPos.y * flyUp + localPos.z * flyRight;
      
      finalPos = newPos + rotatedPos;
    } else {
      // Still waiting for delay - aim toward target
      finalPos = circlePos + rotatedToTarget;
    }
  } else {
    // Normal circling mode - aim toward target
    finalPos = circlePos + rotatedToTarget;
  }

  outputVertices[id].position = finalPos;
  outputVertices[id].color = vertexColor;
}

// Helper function to calculate sword position (shared between blade and hilt kernels)
float3 calculateSwordPosition(SwordBase sword, float3 localPos, float time, int swordIdx) {
  // Calculate current rotation angle based on time
  float currentAngle = sword.angle + time * sword.speed;
  
  // Default circling position on the XY plane (elevated by circleYOffset)
  float3 circlePos = float3(
      cos(currentAngle) * sword.radius, 
      sin(currentAngle) * sword.radius + circleYOffset, 
      0.0);
  
  // Target position for aiming (center of target area)
  float3 targetPos = float3(0.0, 0.0, -12.0);
  
  // Calculate direction from current circle position to target (for aiming while circling)
  float3 aimDirection = normalize(targetPos - circlePos);
  
  // Create rotation matrix to point sword toward target
  float3 up = float3(0, 1, 0);
  float3 aimRight = normalize(cross(up, aimDirection));
  float3 aimUp = cross(aimDirection, aimRight);
  
  // Transform local position: X axis (sword length) points toward target
  float3 rotatedToTarget = localPos.x * aimDirection + localPos.y * aimUp + localPos.z * aimRight;
  
  float3 finalPos;
  
  // Check if sword is in launch mode
  if (sword.launchTime >= 0.0) {
    float timeSinceLaunch = time - sword.launchTime;
    float effectiveTime = timeSinceLaunch - sword.launchDelay;
    
    if (effectiveTime > 0.0) {
      // Target position with minimal perturbation
      float perturbX = sin(float(swordIdx) * 1.7) * 0.0625;
      float perturbY = cos(float(swordIdx) * 2.3) * 0.0625;
      float3 flyTargetPos = float3(perturbX, perturbY, -12.0);
      
      float3 startPos = sword.launchStartPos;
      float3 direction = normalize(flyTargetPos - startPos);
      
      float distance = effectiveTime * sword.launchSpeed;
      float3 newPos = startPos + direction * distance;
      
      // Rotate sword to point toward target
      float3 flyRight = normalize(cross(up, direction));
      float3 flyUp = cross(direction, flyRight);
      
      float3 rotatedPos = localPos.x * direction + localPos.y * flyUp + localPos.z * flyRight;
      finalPos = newPos + rotatedPos;
    } else {
      // Still waiting for delay - aim toward target
      finalPos = circlePos + rotatedToTarget;
    }
  } else {
    // Normal circling mode - aim toward target
    finalPos = circlePos + rotatedToTarget;
  }
  
  return finalPos;
}

// Kernel for blade vertices only (vertices 0-14)
// 15 vertices per sword for the blade
kernel void updateBladeVertexes(
    device SwordBase *swordList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant FlyingSwordsParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {

  uint swordIdx = id / 15; // 15 vertices per sword blade
  uint vertexIdx = id % 15;
  
  SwordBase sword = swordList[swordIdx];
  float3 localPos = swordVertices[vertexIdx];
  
  float3 finalPos = calculateSwordPosition(sword, localPos, params.time, int(swordIdx));
  
  // Calculate blade color with golden mesh pattern
  float3 vertexColor = getSwordColor(vertexIdx, localPos, params.time, int(swordIdx));
  
  outputVertices[id].position = finalPos;
  outputVertices[id].color = vertexColor;
}

// Kernel for hilt vertices only (vertices 15-39)
// 25 vertices per sword for the hilt (guard + handle + pommel)
kernel void updateHiltVertexes(
    device SwordBase *swordList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    constant FlyingSwordsParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {

  uint swordIdx = id / 25; // 25 vertices per sword hilt
  uint vertexIdx = id % 25;
  uint globalVertexIdx = vertexIdx + 15; // Offset by 15 to get to hilt vertices
  
  SwordBase sword = swordList[swordIdx];
  float3 localPos = swordVertices[globalVertexIdx];
  
  float3 finalPos = calculateSwordPosition(sword, localPos, params.time, int(swordIdx));
  
  // Calculate golden pattern color for hilt
  float3 vertexColor = getSwordColor(globalVertexIdx, localPos, params.time, int(swordIdx));
  
  outputVertices[id].position = finalPos;
  outputVertices[id].color = vertexColor;
}
