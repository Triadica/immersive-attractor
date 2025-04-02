
#include <metal_stdlib>
using namespace metal;

struct VertexData {
  float3 position;
  // float3 normal;
  // float2 uv;
};

struct MovingAttractorLineParams {
  int vertexPerCell;
  float dt;
  int cellSize;
};

struct CubeBase {
  float3 position;
  float3 velocity;
};

kernel void updateNebulaBase(
    device CubeBase *codeBaseList [[buffer(0)]],
    device CubeBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CubeBase base = codeBaseList[id];
  float3 position = base.position;
  float3 velocity = base.velocity;
  // Total number of particles in the simulation
  uint particleCount = params.cellSize;

  float3 acceleration = float3(0.0, 0.0, 0.0);

  for (uint otherIdx = 0; otherIdx < particleCount; otherIdx++) {
    if (otherIdx == id) {
      continue;
    }

    CubeBase otherParticle = codeBaseList[otherIdx];
    float3 displacement = otherParticle.position - position;
    float distance = length(displacement);
    float3 direction = normalize(displacement);

    // Improved collision response with energy dissipation
    if (distance > 0.022) {
      float s = distance * 1000;
      // Conservative gravity force
      float3 gravityForce = direction * 2.0 / (s * s);
      acceleration += gravityForce;
    } else {
      // Calculate collision damping (energy loss)
      float collisionDamping = 0.99; // some loss of energy
      float overlapDistance = 0.1 - distance;

      // Apply repulsive force based on penetration depth
      // acceleration -= direction * overlapDistance * 10.0;

      // Apply velocity damping in the direction of collision
      float relativeVelocityMagnitude =
          dot(velocity - otherParticle.velocity, direction) * 0.18;
      if (relativeVelocityMagnitude < 0) {
        acceleration -=
            direction * relativeVelocityMagnitude * collisionDamping;
      }
    }
  }

  float3 positionNext = position + velocity * params.dt;
  float3 velocityNext = velocity + acceleration * params.dt;

  outputCodeBaseList[id].position = positionNext;
  outputCodeBaseList[id].velocity = velocityNext;
}

kernel void updateNebulaVertexes(
    device CubeBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  if (cellInnerIdx == 0) {
    CubeBase base = codeBaseList[cellIdx];
    outputVertices[id].position = base.position * 0.4 - float3(0.0, 0.0, 1.0);
  } else {
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}
