//
//  MobisTrail.swift
//  triangle
//
//  Created by chen on 2025/3/2.
//

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
  float timestamp;
};

struct CellBase {
  float3 original;
  float3 position;
  float velocity;
};

// Mobius transformation generated from:
// https://gist.github.com/Dan-Piker/f7d790b3967d41bff8b0291f4cf7bd9e
// https://www.desmos.com/3d/gl6fnutnck
// (I don't have a understanding of the math behind this transformation yet)
static float3 mobiusTransformation(float3 pt, float t) {
  // Initial point coordinates
  float xa = pt.x;
  float ya = pt.y;
  float za = pt.z;

  // Constants for rotation
  float p = 0.0;
  float q = 1.0;

  // Reverse stereographic projection to hypersphere
  float denom = 1.0 + xa * xa + ya * ya + za * za;
  float xb = 2.0 * xa / denom;
  float yb = 2.0 * ya / denom;
  float zb = 2.0 * za / denom;
  float wb = (-1.0 + xa * xa + ya * ya + za * za) / denom;

  // Rotate hypersphere
  float xc = xb * cos(p * t) + yb * sin(p * t);
  float yc = -xb * sin(p * t) + yb * cos(p * t);
  float zc = zb * cos(q * t) - wb * sin(q * t);
  float wc = zb * sin(q * t) + wb * cos(q * t);

  // Project stereographically back to 3D
  float xd = xc / (1.0 - wc);
  float yd = yc / (1.0 - wc);
  float zd = zc / (1.0 - wc);

  return float3(xd, yd, zd);
}

kernel void updateMobiusTrailBase(
    device CellBase *codeBaseList [[buffer(0)]],
    device CellBase *outputCodeBaseList [[buffer(1)]],
    constant MovingAttractorLineParams &params [[buffer(2)]],
    uint id [[thread_position_in_grid]]) {
  CellBase base = codeBaseList[id];
  float3 original = base.original;
  float t = params.timestamp * base.velocity;
  // outputCodeBaseList[id].original = original;
  float3 p = mobiusTransformation(original, t);
  p = p.xzy;
  p.z -= 2.0;
  outputCodeBaseList[id].position = p;
}

kernel void updateMobiusTrailVertexes(
    device CellBase *codeBaseList [[buffer(0)]],
    device VertexData *outputVertices [[buffer(1)]],
    device VertexData *previousVertices [[buffer(2)]],
    constant MovingAttractorLineParams &params [[buffer(3)]],
    uint id [[thread_position_in_grid]]) {
  uint vertexPerCell = params.vertexPerCell;
  uint cellIdx = id / vertexPerCell;
  uint cellInnerIdx = id % vertexPerCell;

  if (cellInnerIdx == 0) {
    CellBase base = codeBaseList[cellIdx];
    outputVertices[id].position =
        float3(base.position.x, base.position.y, base.position.z - 0.2) * 2.;
  } else {
    outputVertices[id].position = previousVertices[id - 1].position;
  }
}
