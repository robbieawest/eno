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

out float Colour;

vec2 noiseScale = vec2(float(SSAOW) / float(SSAONoiseW), float(SSAOH) / float(SSAONoiseW));
float radius = 0.5;
float bias = 0.025;

in mat4 m_Project;
in mat4 m_ProjectInv;

// Could be incorrect
vec3 reconstructFragPos(float depth) {
    vec4 clip = vec4(vec3(texCoords, depth) * 2.0 - 1.0, 1.0);
    vec4 view = m_ProjectInv * clip;
    view /= view.w;

    return view.xyz;
}

void main() {
    float depth = texture(gbDepth, texCoords).r;
    vec3 fragPos = reconstructFragPos(depth);
    vec3 normal = normalize(texture(gbNormal, texCoords).rgb);
    vec3 noise = normalize(texture(SSAONoiseTex, texCoords * noiseScale).xyz);

    vec3 tangent = normalize(noise - normal * dot(noise, normal));
    vec3 bitangent = cross(normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, normal);

    float occlusion = 0.0;
    for(int i = 0; i < SSAONumSamplesInKernel; i++) {
        vec3 samplePos = TBN * vec3(SSAOKernelSamples[i]);
        samplePos = fragPos + samplePos * radius;

        vec4 sampleNDC = vec4(samplePos, 1.0);
        sampleNDC = m_Project * sampleNDC;
        sampleNDC.xyz /= sampleNDC.w;
        sampleNDC.xyz = sampleNDC.xyz * 0.5 + 0.5;
        if (sampleNDC.st != clamp(sampleNDC.st, vec2(0.0), vec2(1.0))) continue;

        float sampleDepth = texture(gbDepth, sampleNDC.st).r;
        sampleDepth = reconstructFragPos(sampleDepth).z;

        float rangeCheck = smoothstep(0.0, 1.0, radius / abs(fragPos.z - sampleDepth));
        occlusion += (sampleDepth >= samplePos.z + bias ? 1.0 : 0.0) * rangeCheck;
    }
    occlusion = 1.0 - (occlusion / SSAONumSamplesInKernel);

    Colour = occlusion;
}