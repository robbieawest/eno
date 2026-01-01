
bool checkBitMask(uint mask, int bitPosition) {
    return (mask & uint(1 << bitPosition)) != 0;
}

layout(binding = 0) uniform sampler2D baseColourTexture;
layout(binding = 0) uniform sampler2D emissiveTexture;
layout(binding = 0) uniform sampler2D occlusionTexture;
layout(binding = 0) uniform sampler2D normalTexture;
layout(binding = 0) uniform sampler2D pbrMetallicRoughness;
layout(binding = 0) uniform sampler2D clearcoatTexture;
layout(binding = 0) uniform sampler2D clearcoatRoughnessTexture;
layout(binding = 0) uniform sampler2D clearcoatNormalTexture;
layout(binding = 0) uniform sampler2D brdfLUT;
layout(binding = 1) uniform samplerCube irradianceMap;
layout(binding = 1) uniform samplerCube prefilterMap;
layout(binding = 0) uniform sampler2D specularTexture;
layout(binding = 0) uniform sampler2D specularColourTexture;
layout(binding = 0) uniform sampler2D SSAOFilteredOut;

uniform vec4 baseColourFactor;
uniform float metallicFactor;
uniform float roughnessFactor;
uniform vec3 emissiveFactor;
uniform float clearcoatFactor;
uniform float clearcoatRoughnessFactor;
uniform bool enableAlphaCutoff;
uniform float alphaCutoff;
uniform float specularFactor;
uniform vec3 specularColourFactor;
uniform bool enableBaseColourOverride;
uniform vec3 baseColourOverride;
uniform bool unlit;

uniform uint materialUsages;

bool materialIsUsed(int material) {
    return checkBitMask(materialUsages, material);
}

#define BaseColourFactor 0
#define BaseColourTexture 1
#define PBRMetallicFactor 2
#define PBRRoughnessFactor 3
#define PBRMetallicRoughnessTexture 4
#define EmissiveFactor 5
#define EmissiveTexture 6
#define OcclusionTexture 7
#define NormalTexture 8
#define ClearcoatFactor 9
#define ClearcoatTexture 10
#define ClearcoatRoughnessFactor 11
#define ClearcoatRoughnessTexture 12
#define ClearcoatNormalTexture 13
#define SpecularFactor 14
#define SpecularTexture 15
#define SpecularColourFactor 16
#define SpecularColourTexture 17
