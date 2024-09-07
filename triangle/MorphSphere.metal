#include <metal_stdlib>
using namespace metal;

struct VertexData {
    float3 position;
    float3 normal;
    float2 uv;
};

struct MorphingSphereParams {
    int32_t latitudeBands;
    int32_t longitudeBands;
    float radius;
    float morphAmount;
    float morphPhase;
};

// Smooth noise function
float smoothNoise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    // Generate pseudo-random values for the four corners of the containing unit square
    float a = sin(dot(i, float2(12.9898, 78.233)) * 43758.5453);
    float b = sin(dot(i + float2(1.0, 0.0), float2(12.9898, 78.233)) * 43758.5453);
    float c = sin(dot(i + float2(0.0, 1.0), float2(12.9898, 78.233)) * 43758.5453);
    float d = sin(dot(i + float2(1.0, 1.0), float2(12.9898, 78.233)) * 43758.5453);

    // Compute smooth interpolation weights
    float2 u = f * f * (3.0 - 2.0 * f);

    // Interpolate between corner values
    return mix(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}

// Fractal Brownian Motion
float fbm(float2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    // Reduce octaves for smoother effect
    for (int i = 0; i < 4; ++i) {
        value += amplitude * smoothNoise(st * frequency);
        st = st * 2.0 + float2(3.14, 2.71);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

kernel void updateMorphingSphere(device VertexData* vertices [[buffer(0)]],
                                 constant MorphingSphereParams& params [[buffer(1)]],
                                 uint id [[thread_position_in_grid]])
{
    int x = id % (params.longitudeBands + 1);
    int y = id / (params.longitudeBands + 1);

    if (x > params.longitudeBands || y > params.latitudeBands) return;

    float lat = float(y) / float(params.latitudeBands);
    float lon = float(x) / float(params.longitudeBands);
    float theta = (1.0 - lat) * M_PI_F;
    float phi = lon * 2 * M_PI_F;

    float sinTheta = sin(theta);
    float cosTheta = cos(theta);
    float sinPhi = sin(phi);
    float cosPhi = cos(phi);

    float3 basePosition = float3(cosPhi * sinTheta, cosTheta, sinPhi * sinTheta);

    // Use a very low frequency for the noise
    float2 noiseCoord = float2(theta, phi) + params.morphPhase * 10000;
    float noiseValue = fbm(noiseCoord) * 2.0 - 1.0;

    // Apply a sine wave to create a more organic, wave-like motion
    float waveEffect = sin(params.morphPhase + theta * 6.0 + phi * 2.0) * 0.5 + 0.5;

    // Combine noise and wave effect
    float combinedEffect = mix(noiseValue, waveEffect, 0.5);

    // Reduce the overall morphing amount for subtler effect
    float morphScale = 0.15 * params.morphAmount;

    float3 offset = basePosition * (combinedEffect * morphScale);

    float3 position = (basePosition + offset) * params.radius;
    float3 normal = normalize(position);

    vertices[id].position = position;
    vertices[id].normal = normal;
    vertices[id].uv = float2(lon, lat);
}