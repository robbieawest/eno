#version 440

in vec2 texCoords;

uniform sampler2D gbDepth;
uniform sampler2D gbNormal;
uniform sampler2D SSAONoiseTex;

#ifndef MAX_SSAO_SAMPLES
#define MAX_SSAO_SAMPLES 128
#endif
uniform vec3 SSAOKernelSamples[MAX_SSAO_SAMPLES];
uniform uint SSAONumSamplesInKernel;

out float Colour;

void main() {
    vec3 normal = texture(gbNormal, texCoords).rgb;
    Colour = (normal.r + normal.g + normal.b) / SSAONumSamplesInKernel / 8 * length(SSAOKernelSamples[0]);
}