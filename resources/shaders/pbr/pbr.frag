#version 440

#define INCLUDE_FRAG_UTILS

#include "pbr/material.glsl"
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
    vec3 position; // World space
    float _pad;
};

LightSourceInformation getLightSourceInformation(uint index) {
    LightSourceInformation lightInformation;
    lightInformation.colour.r = Lights.lightdata[index];
    lightInformation.colour.g = Lights.lightdata[index + 1];
    lightInformation.colour.b = Lights.lightdata[index + 2];
    lightInformation.intensity = Lights.lightdata[index + 3];
    return lightInformation;
}

SpotLight getSpotLight(uint index) {
    SpotLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.direction.x = Lights.lightdata[index + 4];
    light.direction.y = Lights.lightdata[index + 5];
    light.direction.z = Lights.lightdata[index + 6];
    light.innerConeAngle = Lights.lightdata[index + 7];
    light.outerConeAngle = Lights.lightdata[index + 8];
    return light;
}

DirectionalLight getDirectionalLight(uint index) {
    DirectionalLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.direction.x = Lights.lightdata[index + 4];
    light.direction.y = Lights.lightdata[index + 5];
    light.direction.z = Lights.lightdata[index + 6];
    return light;
}

PointLight getPointLight(uint index) {
    PointLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.position.x = Lights.lightdata[index + 4];
    light.position.y = Lights.lightdata[index + 5];
    light.position.z = Lights.lightdata[index + 6];
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

uniform uint lightingSettings;
uniform uvec2 ScreenOutputResolution;

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

float calculateSpecularOcclusion(float NdotV, vec3 BN, vec3 N, vec3 R, float roughness, float ao) {

    float aperture = getAperature(BN);
    //float aperture = getAperature(ao);

    float r_p = aperture;
    float d = acos(dot(normalize(BN), R));
    float r_l = convertSolidAngleToRadians(roughness);

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
    // Can just be replaced with calculatePartialConeIntersection(...)
    float omega_i = float(fullIntersection) * calculateFullConeIntersection(r_p, r_l) +
            float(partialIntersection) * calculatePartialConeIntersection(r_p, r_l, d);


    const bool experimental = false;

    float so = omega_i / roughness;

    if (experimental) {
        // Addition: Check intersection of specular cone with perfect visibility hemisphere
        // This is not accounted for in the GTAO paper, but it seems that when bent normals/AO have artefacts, aperture is underestimated
        //  and grazing angles create fake occlusion. This solves some of the issue, which comes from the specular cone overlapping past the
        //  perfect visibility hemisphere, which is unreachable by visibility samples.
        float hemisphere_overlap = clamp(calculatePartialConeIntersection(PI * 0.5, r_l, acos(NdotV)), 0.0, 1.0);
        float so_min = 0.05 * (1.0 - NdotV * hemisphere_overlap);
        return clamp(mix(so_min, 1.0, so) / hemisphere_overlap, 0.0, 1.0);
    }
    else return so;
}

vec3 IBLAmbientTerm(vec3 N, vec3 BN, vec3 V, vec3 fresnelRoughness, vec3 albedo, float roughness, float metallic, const bool clearcoat, float specular, vec3 specularColour, float ao) {
    const float MAX_REFLECTION_LOD = 4.0;
    vec3 R = reflect(-V, N);  // World space
    // vec3 RWorld = normalize(transpose(TBN) * R);  // Since tbn is orthogonal it is transitive across the reflect operation *from when R was tangent space
    vec3 radiance = textureLod(prefilterMap, R, roughness * MAX_REFLECTION_LOD).rgb;
    vec3 irradiance = texture(irradianceMap, normalize(N)).rgb;  // Use BN later when higher accuracy is available

    float so = 1.0;
    if (checkBitMask(lightingSettings, 3)) {
        so = calculateSpecularOcclusion(dot(N, V), BN, N, reflect(-V, N), roughness, ao);
    }

    vec2 f_ab = texture(brdfLUT, vec2(max(dot(N, V), 0.0), roughness)).rg;

    // Clearcoat -> No metallic or diffuse effects
    if (clearcoat) return (fresnelRoughness * f_ab.x + f_ab.y) * radiance;

    const bool multiScatter = false;
    if (multiScatter) {
        // Multiple scattering https://www.jcgt.org/published/0008/01/03/paper.pdf
        // Could use interped F0 instead of two BRDF calculations
        vec3 metalBRDF = IBLMultiScatterBRDF(N, V, radiance, irradiance, albedo, f_ab, roughness, false, 1.0, vec3(1.0), so);
        vec3 dielectricBRDF = IBLMultiScatterBRDF(N, V, radiance, irradiance, albedo, f_ab, roughness, true, specular, specularColour, so);
        return mix(dielectricBRDF, metalBRDF, metallic) * ao;
    }
    else {
        // Single scatter
        vec3 kS = fresnelRoughness;
        vec3 specular = (kS * f_ab.x + f_ab.y) * radiance;

        vec3 kD = 1.0 - kS;
        kD *= 1.0 - metallic;
        vec3 diffuse = irradiance * albedo * orenNayarFujii(N, V, R, roughness);
        return (kD * diffuse + specular * so) * ao;
    }
}

bool baseColourFactorSet = checkBitMask(materialUsages, BaseColourFactor);
bool baseColourTextureSet = checkBitMask(materialUsages, BaseColourTexture);
bool PBRMetallicFactorSet = checkBitMask(materialUsages, PBRMetallicFactor);
bool PBRRoughnessFactorSet = checkBitMask(materialUsages, PBRRoughnessFactor);
bool PBRMetallicRoughnessTextureSet = checkBitMask(materialUsages, PBRMetallicRoughnessTexture);
bool emissiveFactorSet = checkBitMask(materialUsages, EmissiveFactor);
bool emissiveTextureSet = checkBitMask(materialUsages, EmissiveTexture);
bool occlusionTextureSet = checkBitMask(materialUsages, OcclusionTexture);
bool normalTextureSet = checkBitMask(materialUsages, NormalTexture);
bool clearcoatFactorSet = checkBitMask(materialUsages, ClearcoatFactor);
bool clearcoatTextureSet = checkBitMask(materialUsages, ClearcoatTexture);
bool clearcoatRoughnessFactorSet = checkBitMask(materialUsages, ClearcoatRoughnessFactor);
bool clearcoatRoughnessTextureSet = checkBitMask(materialUsages, ClearcoatRoughnessTexture);
bool clearcoatNormalTextureSet = checkBitMask(materialUsages, ClearcoatNormalTexture);
bool specularFactorSet = checkBitMask(materialUsages, SpecularFactor);
bool specularTextureSet = checkBitMask(materialUsages, SpecularTexture);
bool specularColourFactorSet = checkBitMask(materialUsages, SpecularColourFactor);
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


float getOcclusion() {
    float occlusion = 1.0;
    if (occlusionTextureSet) occlusion *= texture(occlusionTexture, texCoords).r;
    return occlusion;
}

vec4 getAmbientOcclusion(vec2 screenUV, vec3 normal) {
    float occlusion = 1.0;
    vec3 bentNormal = vec3(0.0);
    if (checkBitMask(lightingSettings, 2)) {
        vec4 ssao_output = texture(SSAOFilteredOut, screenUV).rgba;
        occlusion *= ssao_output.a;

        if (checkBitMask(lightingSettings, 3)) {
            bentNormal = ssao_output.rgb * 2.0 - 1.0;  // View space
            bentNormal = transView * bentNormal;
        }
    }

    return vec4(bentNormal, occlusion);
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

vec3 calculateDirectReflectance(vec3 radiance, vec3 N, vec3 V, vec3 L, vec3 albedo, float roughness, float metallic, vec3 baseFresnelIncidence, float specular, bool clearcoatActive, float clearcoat, float clearcoatRoughness) {
    vec3 H = normalize(V + L);

    vec3 BRDF = calculateBRDF(N, V, L, H, albedo, roughness, metallic, baseFresnelIncidence, specular);
    if (clearcoatActive) {
        vec3 clearcoatFresnel = FresnelSchlick(V, H, vec3(0.04)) * clearcoat;
        BRDF *= (1.0 - clearcoatFresnel);
        BRDF += calculateClearcoatBRDF(N, L, H, clearcoatRoughness, clearcoatFresnel);
    }

    return calculateReflectance(BRDF, N, L, radiance);
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
    vec4 ao_bn = getAmbientOcclusion(screenUV, normal);
    float ao = ao_bn.a * occlusion;
    vec3 bentNormal = ao_bn.rgb;

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

    uint spotLightSize = 12;
    uint directionalLightSize = 8;
    uint pointLightSize = 8;
    if (directLightingEnabled) {

        uint bufIndex = 0;
        for (uint i = 0; i < Lights.numSpotLights; i++) {
            // Todo
            bufIndex += spotLightSize;
        }

        for (uint i = 0; i < Lights.numDirectionalLights; i++) {
            DirectionalLight light = getDirectionalLight(bufIndex);
            vec3 lightDir = normalize(-light.direction);
            vec3 halfVec = normalize(lightDir + viewDir);
            vec3 radiance = light.lightInformation.intensity * light.lightInformation.colour;

            lightOutputted += calculateDirectReflectance(radiance, normal, viewDir, lightDir, albedo, roughness, metallic, baseFresnelIncidence, specular, clearcoatActive, clearcoat, clearcoatRoughness);
            bufIndex += directionalLightSize;
        }

        for (uint i = 0; i < Lights.numPointLights; i++) {
            PointLight light = getPointLight(bufIndex);
            vec3 lightDir = normalize(light.position - position);
            vec3 radiance = light.lightInformation.intensity * light.lightInformation.colour / (pow(length(lightDir), 2));

            lightOutputted += calculateDirectReflectance(radiance, normal, viewDir, lightDir, albedo, roughness, metallic, baseFresnelIncidence, specular, clearcoatActive, clearcoat, clearcoatRoughness);

            bufIndex += pointLightSize;
        }

    }

    vec3 ambient = vec3(0.0);
    vec3 Fc = vec3(0.0);
    vec3 ambientNormal = normal;
    if (bentNormalsEnabled) ambientNormal = bentNormal;

    if (iblEnabled) {
        vec3 F = FresnelSchlickRoughness(normal, viewDir, baseFresnelIncidence, roughness);
        ambient = IBLAmbientTerm(normal, ambientNormal, viewDir, F, albedo, roughness, metallic, false, specular, specularColour, ao);

        if (clearcoatActive) {
            // Fresnel at incidence for clearcoat is 0.04/4% at IOR=1.5
            Fc = FresnelSchlickRoughness(clearcoatNormal, viewDir, vec3(0.04), clearcoatRoughness);
            ambient *= (1.0 - Fc);
            ambient += IBLAmbientTerm(clearcoatNormal, clearcoatNormal, viewDir, Fc, vec3(0.0), clearcoatRoughness, 0.0, true, specular, specularColour, ao);
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
