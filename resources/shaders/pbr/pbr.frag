#version 440

#define INCLUDE_FRAG_UTILS

#include "pbr/tonemap.glsl"
#include "pbr/pbr_util.glsl"
#include "pbr/geom_util.glsl"

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


in vec3 position;
in vec3 geomNormal;
in vec2 texCoords;
in vec3 cameraPosition;
in mat3 transView;
out vec4 Colour;

#ifdef CONTAINS_TANGENT
in mat3 TBN;
#else
mat3 TBN = calculateTBN(position, texCoords, geomNormal);
#endif


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
layout(binding = 0) uniform sampler2D SSAOBlur;
layout(binding = 0) uniform sampler2D SSAOBlurredBentNormal;

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
uniform uint lightingSettings;

uniform uvec2 ScreenOutputResolution;


bool checkBitMask(uint mask, int bitPosition) {
    return (mask & uint(1 << bitPosition)) != 0;
}

float getAperature(vec3 AN) {
    return PI * 0.5 * (1.0 - max(0.0, 2.0 * length(AN) - 1.0));
}

float getAperature(float ao) {
    return acos(sqrt(1.0 - ao));
}

float calculatePartialConeIntersection(float r_p, float r_l, float d) {
    float LHS = 2.0 * PI * (1.0 - cos(min(r_p, r_l)));
    float k = 1.0 - (d - abs(r_p - r_l)) / (r_p + r_l - abs(r_p - r_l));
    return LHS * smoothstep(0.0, 1.0, k);
}

float calculateFullConeIntersection(float r_p, float r_l) {
    return 2.0 * PI * (1.0 - cos(min(r_p, r_l)));
}

float convertSolidAngleToRadians(float angle) {
    return acos((-angle) / (2.0 * PI) + 1.0);
}

// WIP
float calculateSpecularOcclusion(vec3 BN, vec3 R, float roughness, float ao) {

    //float aperture = getAperature(BN);
    float aperture = getAperature(ao);
    float omega_s = roughness;

    float r_p = aperture;
    float r_l = convertSolidAngleToRadians(omega_s);
    float d = acos(clamp(dot(normalize(BN), R), 0.0, 1.0));
    // Light source vector V_l = R, radius r_l = reflection cone angle
    // d = similarity
    // r_p = bent cone aperture -> spherical cap radius

    // Find the area of intersection of specular (R) and visibility (BN) cones
    // calculate SO = omega_i / omega_s (reflection/specular cone angle])

    // Find intersection area
    // if min(r_p, r_l) <= max(r_p, r_l) - d, then 2pi(1 - cos(min(r_p, r_l)))
    // if r_p + r_l <= d, then 0
    // otherwise, L(d, r_p, r_l)
    // L defines partial intersection, and has a large trig-based identity in the paper
    // They find an optimized approximation:
    // L(d, r_p, r_l) = (2pi - 2picos(min_rp, r_l))) *
    //  smoothstep(0, 1, 1 - (d - abs(r_p - r_l)) / (r_+p + r_l - abs(r_p - r_l)))

    bool fullIntersection = bool(min(r_p, r_l) <= max(r_p, r_l) - d);
    bool noIntersection = bool((r_p + r_l) <= d);
    bool partialIntersection = !noIntersection && !fullIntersection;
    float omega_i = float(fullIntersection) * calculateFullConeIntersection(r_p, r_l) +
            float(partialIntersection) * calculatePartialConeIntersection(r_p, r_l, d);

    return omega_i / omega_s;
}

vec3 IBLAmbientTerm(vec3 N, vec3 geomNormal, vec3 AN, vec3 V, vec3 fresnelRoughness, vec3 albedo, float roughness, float metallic, const bool clearcoat, float specular, vec3 specularColour, float ao) {
    const float MAX_REFLECTION_LOD = 4.0;
    vec3 R = reflect(-V, N);  // World space
    // vec3 RWorld = normalize(transpose(TBN) * R);  // Since tbn is orthogonal it is transitive across the reflect operation *from when R was tangent space
    vec3 radiance = textureLod(prefilterMap, R, roughness * MAX_REFLECTION_LOD).rgb;
    vec3 irradiance = texture(irradianceMap, normalize(AN)).rgb;

    float so = 1.0;
    if (checkBitMask(lightingSettings, 3)) {
        so = calculateSpecularOcclusion(AN, reflect(-V, N), roughness, ao);
    }

    vec2 f_ab = texture(brdfLUT, vec2(max(dot(N, V), 0.0), roughness)).rg;

    // Clearcoat -> No metallic or diffuse effects
    if (clearcoat) return (fresnelRoughness * f_ab.x + f_ab.y) * radiance;

    const bool multiScatter = false;
    if (multiScatter) {
        // Multiple scattering https://www.jcgt.org/published/0008/01/03/paper.pdf
        // Could use interped F0 instead of two BRDF calculations
        vec3 metalBRDF = IBLMultiScatterBRDF(N, V, radiance, irradiance, albedo, f_ab, roughness, false, 1.0, vec3(1.0));
        vec3 dielectricBRDF = IBLMultiScatterBRDF(N, V, radiance, irradiance, albedo, f_ab, roughness, true, specular, specularColour);
        return mix(dielectricBRDF, metalBRDF, metallic);
    }
    else {
        // Single scatter
        vec3 kS = fresnelRoughness;
        vec3 specular = (kS * f_ab.x + f_ab.y) * radiance;

        vec3 kD = 1.0 - kS;
        kD *= 1.0 - metallic;
        vec3 diffuse = irradiance * albedo;
        return kD * diffuse * ao + specular * so;
    }
}

#define BaseColourFactor 0
bool baseColourFactorSet = checkBitMask(materialUsages, BaseColourFactor);
#define BaseColourTexture 1
bool baseColourTextureSet = checkBitMask(materialUsages, BaseColourTexture);
#define PBRMetallicFactor 2
bool PBRMetallicFactorSet = checkBitMask(materialUsages, PBRMetallicFactor);
#define PBRRoughnessFactor 3
bool PBRRoughnessFactorSet = checkBitMask(materialUsages, PBRRoughnessFactor);
#define PBRMetallicRoughnessTexture 4
bool PBRMetallicRoughnessTextureSet = checkBitMask(materialUsages, PBRMetallicRoughnessTexture);
#define EmissiveFactor 5
bool emissiveFactorSet = checkBitMask(materialUsages, EmissiveFactor);
#define EmissiveTexture 6
bool emissiveTextureSet = checkBitMask(materialUsages, EmissiveTexture);
#define OcclusionTexture 7
bool occlusionTextureSet = checkBitMask(materialUsages, OcclusionTexture);
#define NormalTexture 8
bool normalTextureSet = checkBitMask(materialUsages, NormalTexture);
#define ClearcoatFactor 9
bool clearcoatFactorSet = checkBitMask(materialUsages, ClearcoatFactor);
#define ClearcoatTexture 10
bool clearcoatTextureSet = checkBitMask(materialUsages, ClearcoatTexture);
#define ClearcoatRoughnessFactor 11
bool clearcoatRoughnessFactorSet = checkBitMask(materialUsages, ClearcoatRoughnessFactor);
#define ClearcoatRoughnessTexture 12
bool clearcoatRoughnessTextureSet = checkBitMask(materialUsages, ClearcoatRoughnessTexture);
#define ClearcoatNormalTexture 13
bool clearcoatNormalTextureSet = checkBitMask(materialUsages, ClearcoatNormalTexture);
#define SpecularFactor 14
bool specularFactorSet = checkBitMask(materialUsages, SpecularFactor);
#define SpecularTexture 15
bool specularTextureSet = checkBitMask(materialUsages, SpecularTexture);
#define SpecularColourFactor 16
bool specularColourFactorSet = checkBitMask(materialUsages, SpecularColourFactor);
#define SpecularColourTexture 17
bool specularColourTextureSet = checkBitMask(materialUsages, SpecularColourTexture);

vec4 getBaseColour() {
    vec4 baseColour = vec4(vec3(0.0), 1.0);
    if (baseColourFactorSet) {
        baseColour = baseColourFactor.rgba;
    }
    if (baseColourTextureSet) {
        vec4 baseColourTextureVal = texture(baseColourTexture, texCoords).rgba;
        if (baseColourFactorSet) baseColour *= baseColourTextureVal;
        else baseColour = baseColourTextureVal;
    }
    if (enableBaseColourOverride) baseColour = vec4(baseColourOverride, baseColour.a);
    return baseColour;
}

struct MetallicRoughness  {
    float metallic;
    float roughness;
};
MetallicRoughness getMetallicRoughness() {
    MetallicRoughness metallicRoughness;
    metallicRoughness.metallic = 1.0;
    metallicRoughness.roughness = 1.0;
    if (PBRMetallicFactorSet) metallicRoughness.metallic *= metallicFactor;
    if (PBRRoughnessFactorSet) metallicRoughness.roughness *= roughnessFactor;

    if (PBRMetallicRoughnessTextureSet) {
        vec2 metallicRoughnessTextureVal = texture(pbrMetallicRoughness, texCoords).gb;
        if (PBRRoughnessFactorSet) metallicRoughness.roughness *= metallicRoughnessTextureVal.x;
        else metallicRoughness.roughness = metallicRoughnessTextureVal.x;

        if (PBRMetallicFactorSet) metallicRoughness.metallic *= metallicRoughnessTextureVal.y;
        else metallicRoughness.metallic = metallicRoughnessTextureVal.y;
    }

    return metallicRoughness;
}

vec3 getNormal() {
    vec3 normal;

    if (normalTextureSet) {
        normal = texture(normalTexture, texCoords).rgb * 2.0 - 1.0;
        normal = TBN * normal;
    }
    else normal = geomNormal;
    normal = normalize(normal);

    if (!gl_FrontFacing) {
        normal = -normal;
    }

    return normal;
}

// Averages with the usual normal if normal mapping is set
vec3 getBentNormal(vec2 screenUV, vec3 normal) {
    vec3 bentNormal = vec3(0.0);
    if (checkBitMask(lightingSettings, 3)) {
        bentNormal = texture(SSAOBlurredBentNormal, screenUV).rgb * 2.0 - 1.0;  // View space
        bentNormal = transView * bentNormal;
    }
    if (normalTextureSet) bentNormal += normal;
    return bentNormal;
}

float getOcclusion() {
    float occlusion = 1.0;
    if (occlusionTextureSet) occlusion *= texture(occlusionTexture, texCoords).r;
    return occlusion;
}

float getAmbientOcclusion(vec2 screenUV) {
    float occlusion = 1.0;
    if (checkBitMask(lightingSettings, 2)) occlusion *= texture(SSAOBlur, screenUV).r;
    return occlusion;
}

vec2 getScreenUV() {
    return gl_FragCoord.xy / ScreenOutputResolution.xy;
}

struct Clearcoat {
    float clearcoat;
    float clearcoatRoughness;
    vec3 clearcoatNormal;
};
Clearcoat getClearcoat(vec3 eNormal) {
    Clearcoat clearcoat;
    clearcoat.clearcoat = 0.0;
    clearcoat.clearcoatRoughness = 0.0;
    clearcoat.clearcoatNormal = eNormal;

    if (clearcoatFactorSet) {
        clearcoat.clearcoat = clearcoatFactor;
    }
    if (clearcoatRoughnessFactorSet) {
        clearcoat.clearcoatRoughness = clearcoatRoughnessFactor;
    }

    if (clearcoatTextureSet) {
        float clearcoatTextureVal = texture(clearcoatTexture, texCoords).r;
        if (clearcoatFactorSet) clearcoat.clearcoat *= clearcoatTextureVal;
        else clearcoat.clearcoat = clearcoatTextureVal;
    }
    if (clearcoatRoughnessTextureSet) {
        float clearcoatRoughTextureVal = texture(clearcoatRoughnessTexture, texCoords).r;
        if (clearcoatRoughnessFactorSet) clearcoat.clearcoatRoughness *= clearcoatRoughTextureVal;
        else clearcoat.clearcoatRoughness = clearcoatRoughTextureVal;
    }
    if (clearcoatNormalTextureSet) {
        clearcoat.clearcoatNormal = texture(clearcoatNormalTexture, texCoords).rgb * 2.0 - 1.0;
        #ifndef CONTAINS_TANGENT
        clearcoat.clearcoatNormal = normalize(TBN * clearcoat.clearcoatNormal);
        #endif
    }

    return clearcoat;
}

vec3 getEmissive() {
    vec3 emissive = vec3(0.0);
    if (emissiveFactorSet) {
        emissive = emissiveFactor;
    }

    if (emissiveTextureSet) {
        vec3 emissiveTextureVal = texture(emissiveTexture, texCoords).rgb;
        if (emissiveFactorSet) emissive *= emissiveTextureVal;
        else emissive = emissiveTextureVal;
    }

    return emissive;
}

struct Specular {
    float specular;
    vec3 specularColour;
};
Specular getSpecular() {
    Specular specular;
    specular.specular = 1.0;
    specular.specularColour = vec3(1.0);
    if (specularFactorSet) specular.specular = specularFactor;
    if (specularColourFactorSet) specular.specularColour = specularColourFactor;

    if (specularTextureSet) {
        float specularTextureVal = texture(specularTexture, texCoords).a;
        if (specularFactorSet) specular.specular *= specularTextureVal;
        else specular.specular = specularTextureVal;
    }

    if (specularColourTextureSet) {
        vec3 specularColourTextureVal = texture(specularColourTexture, texCoords).rgb;
        if (specularColourFactorSet) specular.specularColour *= specularColourTextureVal;
        else specular.specularColour = specularColourTextureVal;
    }

    return specular;
}

void main() {
    bool iblEnabled = checkBitMask(lightingSettings, 0);
    bool directLightingEnabled = checkBitMask(lightingSettings, 1);
    bool bentNormalsEnabled = checkBitMask(lightingSettings, 3);

    vec4 baseColour = getBaseColour();
    if (enableAlphaCutoff && baseColour.a < alphaCutoff) discard;
    if (unlit || !(iblEnabled || directLightingEnabled)) {
        Colour = baseColour;
        return;
    }

    vec3 albedo = baseColour.rgb;

    MetallicRoughness metallicRoughness = getMetallicRoughness();
    float metallic = metallicRoughness.metallic;
    float roughness = metallicRoughness.roughness;

    vec2 screenUV = getScreenUV();
    vec3 normal = getNormal();
    vec3 bentNormal = getBentNormal(screenUV, normal);

    Clearcoat clearcoatResult = getClearcoat(normal);
    float clearcoat = clearcoatResult.clearcoat;
    float clearcoatRoughness = clearcoatResult.clearcoatRoughness;
    vec3 clearcoatNormal = clearcoatResult.clearcoatNormal;

    bool clearcoatActive = bool(clearcoat != 0.0);

    vec3 emissive = getEmissive();
    Specular specularTotal = getSpecular();
    float specular = specularTotal.specular;
    vec3 specularColour = specularTotal.specularColour;

    float occlusion = getOcclusion();
    float ao = getAmbientOcclusion(screenUV) * occlusion;

    // Clamp roughnesses, roughness at zero isn't great visually
    roughness = clamp(roughness, 0.089, 1.0);
    clearcoatRoughness = clamp(clearcoatRoughness, 0.089, 1.0);


    vec3 viewDir = normalize(cameraPosition - position);

    vec3 baseFresnelIncidence;
    baseFresnelIncidence = mix(vec3(0.04), albedo, metallic);
    if (clearcoatActive) {
        // Assumes clearcoat layer IOR of 1.5
        baseFresnelIncidence = pow((1.0 - 5.0 * sqrt(baseFresnelIncidence)) / (5.0 - sqrt(baseFresnelIncidence)), vec3(2.0));
    }

    vec3 lightOutputted = vec3(0.0);

    uint spotLightSize = 16;
    uint directionalLightSize = 12;
    uint pointLightSize = 8;
    if (directLightingEnabled) {

        // Calculate for point lights
        uint bufIndex = Lights.numSpotLights * spotLightSize + Lights.numDirectionalLights * directionalLightSize;
        for (uint i = 0; i < Lights.numPointLights; i++) {
            PointLight light = getPointLight(bufIndex);
            vec3 lightPos = light.lightInformation.position;
            vec3 lightDir = normalize(lightPos - position);
            float lightDist = length(lightDir);

            vec3 halfVec = normalize(lightDir + viewDir);

            vec3 radiance = light.lightInformation.intensity * light.lightInformation.colour / (lightDist * lightDist);

            vec3 BRDF = calculateBRDF(normal, viewDir, lightDir, halfVec, albedo, roughness * roughnessFactor, metallic * metallicFactor, baseFresnelIncidence, specular);
            if (clearcoatActive) {
                vec3 clearcoatFresnel = FresnelSchlick(viewDir, halfVec, vec3(0.04)) * clearcoat;
                BRDF *= (1.0 - clearcoatFresnel);
                BRDF += calculateClearcoatBRDF(normal, lightDir, halfVec, clearcoatRoughness, clearcoatFresnel);
            }

            vec3 reflectance = calculateReflectance(BRDF, normal, lightDir, radiance);
            lightOutputted += reflectance;

            bufIndex += pointLightSize;
        }
    }

    vec3 ambient = vec3(0.0);
    vec3 Fc = vec3(0.0);
    vec3 ambientNormal = normal;
    if (bentNormalsEnabled) ambientNormal = bentNormal;

    if (iblEnabled) {
        vec3 F = FresnelSchlickRoughness(normal, viewDir, baseFresnelIncidence, roughness);
        ambient = IBLAmbientTerm(normal, geomNormal, ambientNormal, viewDir, F, albedo, roughness, metallic, false, specular, specularColour, ao);

        if (clearcoatActive) {
            // Fresnel at incidence for clearcoat is 0.04/4% at IOR=1.5
            Fc = FresnelSchlickRoughness(clearcoatNormal, viewDir, vec3(0.04), clearcoatRoughness);
            ambient *= (1.0 - Fc);
            ambient += IBLAmbientTerm(clearcoatNormal, geomNormal, clearcoatNormal, viewDir, Fc, vec3(0.0), clearcoatRoughness, 0.0, true, specular, specularColour, ao);
        }
    }

    vec3 colour = (ambient + lightOutputted);
    colour += emissive * (1.0 - clearcoat * Fc);

    // HDR
    colour = KhronosNeutralTonemapping(colour);

    // Gamma
    float gamma = 2.2;
    const bool srgb = false;
    if (srgb) colour = pow(colour, vec3(gamma));
    else colour = pow(colour, vec3(1.0 / gamma));

    Colour = vec4(colour, baseColour.a);
}
