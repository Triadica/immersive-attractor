//
//  MorphSphere.metal
//  triangle
//
//  Created by chen on 2024/8/19.
//

#include <metal_stdlib>
using namespace metal;

struct VertexData {
    float3 position;
    float3 normal;
    float2 uv;
    // float segmentIdx;
};

struct MorphingSphereParams {
    int32_t latitudeBands;
    int32_t longitudeBands;
    float radius;
    float morphAmount;
    float morphPhase;
};


kernel void updateMorphingSphere(device VertexData* vertices [[buffer(0)]],
                                 constant MorphingSphereParams& params [[buffer(1)]],
                                 uint id [[thread_position_in_grid]])
{
    int x = id % (params.longitudeBands + 1);
    int y = id / (params.longitudeBands + 1);

    float3 basePosition = float3(x * .01, 0., y * .01);
    float3 up = float3(0., 1., 0.);
//    
//    vertices[id].position = basePosition;
//    vertices[id].normal = up;
//    vertices[id].uv = float2(x, y);
}
