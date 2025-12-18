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
uniform uint SSAONoiseW;
uniform uint SSAOW;
uniform uint SSAOH;

vec2 noiseScale = vec2(float(SSAOW) / float(SSAONoiseW), float(SSAOH) / float(SSAONoiseW));
uniform float SSAOSampleRadius;
uniform float SSAOBias;

uniform bool SSAOEvaluateBentNormal;

layout(location = 0) out float Colour;
layout(location = 1) out vec3 BentNormal;


in mat4 m_Project;
in mat4 m_ProjectInv;

// Could be incorrect
vec3 reconstructFragPos(vec2 UV, float depth) {
    vec4 clip = vec4(vec3(UV, depth) * 2.0 - 1.0, 1.0);
    vec4 view = m_ProjectInv * clip;
    view /= view.w;

    return view.xyz;
}

void main() {
    float depth = texture(gbDepth, texCoords).r;
    vec3 fragPos = reconstructFragPos(texCoords, depth);
    vec3 normal = normalize(texture(gbNormal, texCoords).rgb * 2.0 - 1.0);
    BentNormal = normal;

    vec3 noise = normalize(texture(SSAONoiseTex, texCoords * noiseScale).xyz);

    vec3 tangent = normalize(noise - normal * dot(noise, normal));
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);

    vec3 bentNormal = vec3(0.0);

    float occlusion = 0.0;
    float unocclusion = 0.0;
    for(int i = 0; i < SSAONumSamplesInKernel; i++) {
        vec3 sampleT = vec3(SSAOKernelSamples[i]);
        vec3 sampleV = TBN * sampleT;
        vec3 samplePos = fragPos + sampleV * SSAOSampleRadius;

        vec4 sampleUV = vec4(samplePos, 1.0);
        sampleUV = m_Project * sampleUV;
        sampleUV.xyz /= sampleUV.w;
        sampleUV.xyz = sampleUV.xyz * 0.5 + 0.5;

        float sampleDepth = texture(gbDepth, sampleUV.st).r;
        sampleDepth = reconstructFragPos(sampleUV.st, sampleDepth).z;

        float rangeCheck = smoothstep(0.0, 1.0, SSAOSampleRadius / abs(fragPos.z - sampleDepth));
        float occluded = (sampleDepth >= samplePos.z + SSAOBias ? 1.0 : 0.0) * rangeCheck;

        float sampleValid = float(all(equal(sampleUV.st, clamp(sampleUV.st, vec2(0.0), vec2(1.0)))));
        occluded *= sampleValid;
        float unoccluded = 1.0 - occluded;

        occlusion += occluded;
        unocclusion += unoccluded;

        if (SSAOEvaluateBentNormal) bentNormal += sampleV * unoccluded;
    }
    if (SSAOEvaluateBentNormal) BentNormal = normalize(bentNormal);
    BentNormal = (BentNormal + 1.0) * 0.5;

    Colour = 1.0 - (occlusion / SSAONumSamplesInKernel);
}