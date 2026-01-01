#version 440

#include "util/camera.glsl"

in vec2 texCoords;
out vec4 SSAOFilteredOut;

uniform sampler2D SSAOOut;
uniform sampler2D gbDepth;
uniform sampler2D gbNormal;

uniform bool filterDirection;

const int KERNEL_RADIUS = 4;
const float SHARPNESS = 40.0;

float GaussianWeight(float x, float sigma) {
    return exp(-pow(x, 2) / (2.0 * pow(sigma, 2)));
}

void accumulateNeighbour(
        inout float totalColour,
        inout float totalColourWeight,
        inout vec3 totalBNDir,
        inout float totalBNVar,
        inout float totalBNWeight,
        int i,
        vec2 texelSize,
        vec2 direction,
        float cDepth,
        vec3 cNormal
) {
    vec2 offsetUV = texCoords + (vec2(float(i)) * texelSize * direction);

    float sColour = texture(SSAOOut, offsetUV).a;
    vec3 sBentNormal = texture(SSAOOut, offsetUV).rgb * 2.0 - 1.0;
    float sDepth = linearizeDepth(texture(gbDepth, offsetUV).r);
    vec3 sNormal = normalize(texture(gbNormal, offsetUV).rgb * 2.0 - 1.0);

    vec3 sBNDir = normalize(sBentNormal);
    float sBNVar = length(sBentNormal);

    float wSpatial = GaussianWeight(float(i), float(KERNEL_RADIUS) * 0.5);

    float depthDiff = abs(cDepth - sDepth);
    float wDepth = exp(-depthDiff * SHARPNESS);

    float wNormal = max(0.0, dot(cNormal, sNormal));
    wNormal = pow(wNormal, 4.0);

    float colourWeight = wSpatial * wDepth;
    float bnWeight = colourWeight * wNormal;
    totalColour += sColour * colourWeight;
    totalColourWeight += colourWeight;
    totalBNVar += sBNVar * bnWeight;
    totalBNDir += sBNDir * bnWeight;
    totalBNWeight += bnWeight;
}

void main() {
    vec2 texelSize = 1.0 / vec2(textureSize(SSAOOut, 0));

    float cColour = texture(SSAOOut, texCoords).a;
    vec3 cBentNormal = texture(SSAOOut, texCoords).rgb * 2.0 - 1.0;
    float cDepth = linearizeDepth(texture(gbDepth, texCoords).r);
    vec3 cNormal = normalize(texture(gbNormal, texCoords).rgb * 2.0 - 1.0);

    vec2 direction = filterDirection ? vec2(1.0, 0.0) : vec2(0.0, 1.0);

    vec3 totalBNDir = normalize(cBentNormal);
    float totalBNVar = length(cBentNormal);
    float totalBNWeight = 1.0;
    float totalColour = cColour;
    float totalColourWeight = 1.0;

    for (int i = -KERNEL_RADIUS; i < 0; i++) {
        accumulateNeighbour(totalColour, totalColourWeight, totalBNDir, totalBNVar, totalBNWeight, i, texelSize, direction, cDepth, cNormal);
    }

    for (int i = 1; i <= KERNEL_RADIUS; i++) {
        accumulateNeighbour(totalColour, totalColourWeight, totalBNDir, totalBNVar, totalBNWeight, i, texelSize, direction, cDepth, cNormal);
    }

    vec3 SSAOBN = (normalize(totalBNDir) * (totalBNVar / totalBNWeight) + 1.0) * 0.5;
    float SSAOColour = totalColour / totalColourWeight;
    SSAOFilteredOut = vec4(SSAOBN, SSAOColour);
}
