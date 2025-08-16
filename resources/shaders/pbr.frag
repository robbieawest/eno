#version 440

layout(std430, binding = 1) buffer LightBuf {
    uint numSpotLights;
    uint numDirectionalLights;
    uint numPointLights;
    uint _pad;
    float lightdata[];  // Raw buffer of light data
} Lights;

struct LightSourceInformation {
    vec3 colour;
    float _pad;
    vec3 position;  // World space
    float intensity;
};

struct SpotLight {
    LightSourceInformation lightInformation;
    vec3 direction;
    float innerConeAngle;
    float outerConeAngle;
    vec3 _pad;
};

struct DirectionalLight {
    LightSourceInformation lightInformation;
    vec3 direction;
    float _pad;
};

struct PointLight {
    LightSourceInformation lightInformation;
};

LightSourceInformation getLightSourceInformation(uint index) {
    LightSourceInformation lightInformation;
    lightInformation.colour.r = Lights.lightdata[index];
    lightInformation.colour.g = Lights.lightdata[index + 1];
    lightInformation.colour.b = Lights.lightdata[index + 2];
    lightInformation.position.x = Lights.lightdata[index + 4];
    lightInformation.position.y = Lights.lightdata[index + 5];
    lightInformation.position.z = Lights.lightdata[index + 6];
    lightInformation.intensity = Lights.lightdata[index + 7];
    return lightInformation;
}

SpotLight getSpotLight(uint index) {
    SpotLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.direction.x = Lights.lightdata[index + 8];
    light.direction.y = Lights.lightdata[index + 9];
    light.direction.z = Lights.lightdata[index + 10];
    light.innerConeAngle = Lights.lightdata[index + 11];
    light.outerConeAngle = Lights.lightdata[index + 12];
    return light;
}

DirectionalLight getDirectionalLight(uint index) {
    DirectionalLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.direction.x = Lights.lightdata[index + 8];
    light.direction.y = Lights.lightdata[index + 9];
    light.direction.z = Lights.lightdata[index + 10];
    return light;
}

PointLight getPointLight(uint index) {
    PointLight light;
    light.lightInformation = getLightSourceInformation(index);
    return light;
}


in vec3 position;  // Tangent space
in vec3 geomNormal;  // Tangent space
in vec2 texCoords;
in vec3 cameraPosition;  // Tangent space
in mat3 TBN;
out vec4 Colour;

layout(binding = 0) uniform sampler2D baseColourTexture;
layout(binding = 1) uniform sampler2D emissiveTexture;
layout(binding = 2) uniform sampler2D occlusionTexture;
layout(binding = 3) uniform sampler2D normalTexture;
layout(binding = 4) uniform sampler2D pbrMetallicRoughness;
layout(binding = 5) uniform sampler2D clearcoatTexture;
layout(binding = 6) uniform sampler2D clearcoatRoughnessTexture;
layout(binding = 7) uniform sampler2D clearcoatNormalTexture;
layout(binding = 8) uniform sampler2D brdfLUT;
layout(binding = 9) uniform samplerCube irradianceMap;
layout(binding = 10) uniform samplerCube prefilterMap;

uniform vec4 baseColourFactor;
uniform float metallicFactor;
uniform float roughnessFactor;
uniform vec3 emissiveFactor;
uniform float clearcoatFactor;
uniform float clearcoatRoughnessFactor;

uniform uint materialUsages;

float PI = 3.14159265358979323;

vec3 ReinhardTonemapping(vec3 colour) {
    return colour / (colour + vec3(1.0));
}

// https://www.khronos.org/news/press/khronos-pbr-neutral-tone-mapper-released-for-true-to-life-color-rendering-of-3d-products
vec3 KhronosNeutralTonemapping(vec3 colour) {
    const float startCompression = 0.8 - 0.04;
    const float desaturation = 0.15;

    float x = min(colour.r, min(colour.g, colour.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    colour -= offset;

    float peak = max(colour.r, max(colour.g, colour.b));
    if (peak < startCompression) return colour;

    const float d = 1. - startCompression;
    float newPeak = 1. - d * d / (peak + d - startCompression);
    colour *= newPeak / peak;

    float g = 1. - 1. / (desaturation * (peak - newPeak) + 1.);
    return mix(colour, newPeak * vec3(1, 1, 1), g);
}

vec3 convertToTangentSpace(vec3 v) {
    return TBN * v;
}

float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float GeomSchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeomSmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeomSchlickGGX(NdotV, roughness);
    float ggx1 = GeomSchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 FresnelSchlick(vec3 V, vec3 H, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - max(dot(H, V), 0.0), 0.0, 1.0), 5.0);
}

vec3 FresnelSchlickRoughness(vec3 N, vec3 V, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - max(dot(N, V), 0.0), 0.0, 1.0), 5.0);
}

vec3 calculateBRDF(vec3 N, vec3 V, vec3 L, vec3 H, vec3 albedo, float roughness, float metallic, vec3 F0) {
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeomSmith(N, V, L, roughness);
    vec3 fresnel = FresnelSchlick(H, V, F0);

    // Cook-torrence
    vec3 num = NDF * G * fresnel;
    float denom = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = num / denom;

    vec3 diffuseShare = (vec3(1.0) - fresnel) * (1 - metallic);
    vec3 lambertian = albedo / PI;
    return diffuseShare * lambertian + specular;
}

vec3 calculateReflectance(vec3 BRDF, vec3 N, vec3 L, vec3 radiance) {
    return BRDF * radiance * max(dot(N, L), 0.0);
}

vec3 IBLAmbientTerm(vec3 normal, vec3 viewDir, vec3 fresnelIncidence, vec3 albedo, float roughness, float metallic) {
    vec3 F = FresnelSchlickRoughness(normal, viewDir, fresnelIncidence, roughness);

    const float MAX_REFLECTION_LOD = 4.0;
    vec3 R = reflect(-viewDir, normal);  // Tangent space
    vec3 RWorld = normalize(transpose(TBN) * R);  // Since tbn is orthogonal it is transitive across the reflect operation
    vec3 radiance = textureLod(prefilterMap, RWorld, roughness * MAX_REFLECTION_LOD).rgb;
    vec3 irradiance = texture(irradianceMap, normal).rgb;

    vec2 f_ab = texture(brdfLUT, vec2(max(dot(normal, viewDir), 0.0), roughness)).rg;

    const bool multiScatter = false;
    vec3 ambient;
    if (multiScatter) {
        // Multiple scattering https://www.jcgt.org/published/0008/01/03/paper.pdf
        float Ess = f_ab.x + f_ab.y;
        vec3 FssEss = F * f_ab.x + f_ab.y;
        float Ems = 1 - Ess;
        vec3 Favg = fresnelIncidence + (1.0 - fresnelIncidence) / 21.0;
        vec3 Fms = FssEss * Favg / (1.0 - (1.0 - Ess) * Favg);

        vec3 Edss = 1.0 - (FssEss + Fms * Ems);
        vec3 kD = albedo * Edss;

        ambient = FssEss * radiance + (Fms * Ems + kD) * irradiance;
    }
    else {
        // Single scatter
        vec3 kD = 1.0 - F;
        kD *= 1.0 - metallic;
        vec3 specular = radiance * (F * f_ab.x + f_ab.y);
        vec3 diffuse = irradiance * albedo;

        ambient = kD * diffuse + specular;
    }

    return ambient;
}

bool checkBitMask(int bitPosition) {
    return (materialUsages & uint(1 << bitPosition)) != 0;
}

void main() {
    vec3 albedo = baseColourFactor.rgb;

    if (checkBitMask(1)) {
        albedo *= texture(baseColourTexture, texCoords).rgb;
    }

    float roughness = roughnessFactor;
    float metallic = metallicFactor;
    if (checkBitMask(0)) {
        vec2 metallicRoughness = texture(pbrMetallicRoughness, texCoords).gb;
        roughness *= metallicRoughness.x;
        metallic *= metallicRoughness.y;
    }

    vec3 normal = vec3(1.0);
    if (checkBitMask(4)) {
        normal = texture(normalTexture, texCoords).rgb * 2.0 - 1.0;
    }
    else normal = geomNormal;
    normal = normalize(normal);

    vec3 occlusion;
    if (checkBitMask(3)) {
        occlusion = texture(occlusionTexture, texCoords).rgb;
    }
    else occlusion = vec3(1.0);

    vec3 viewDir = normalize(cameraPosition - position);

    vec3 fresnelIncidence = mix(vec3(0.04), albedo, metallic);

    uint spotLightSize = 16;
    uint directionalLightSize = 12;
    uint pointLightSize = 8;

    vec3 lightOutputted = vec3(0.0);

    // Calculate for point lights
    uint bufIndex = Lights.numSpotLights * spotLightSize + Lights.numDirectionalLights * directionalLightSize;
    for (uint i = 0; i < Lights.numPointLights; i++) {
        PointLight light = getPointLight(bufIndex);
        vec3 lightPos = convertToTangentSpace(light.lightInformation.position);
        vec3 lightDir = normalize(lightPos - position);
        float lightDist = length(lightDir);

        vec3 halfVec = normalize(lightDir + viewDir);

        vec3 radiance = light.lightInformation.intensity * light.lightInformation.colour / (lightDist * lightDist);

        vec3 BRDF = calculateBRDF(normal, viewDir, lightDir, halfVec, albedo, roughness * roughnessFactor, metallic * metallicFactor, fresnelIncidence);
        vec3 reflectance = calculateReflectance(BRDF, normal, lightDir, radiance);
        lightOutputted += reflectance;

        bufIndex += pointLightSize;
    }

    vec3 ambient = IBLAmbientTerm(normal, viewDir, fresnelIncidence, albedo, roughness, metallic);
    vec3 colour = ambient * occlusion + lightOutputted;
    // vec3 colour = lightOutputted + vec3(0.01) * albedo;

    // HDR
    colour = KhronosNeutralTonemapping(colour);
    // colour = ReinhardTonemapping(colour);

    // Gamma
    float gamma = 2.2;
    const bool srgb = false;
    if (srgb) colour = pow(colour, vec3(gamma));
    else colour = pow(colour, vec3(1.0 / gamma));

    Colour = vec4(colour, 1.0);
}
