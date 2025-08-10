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
in vec3 normal;  // Tangent space
in vec2 texCoords;
in vec3 cameraPosition;  // Tangent space
in mat3 TBN;
out vec4 Colour;

uniform sampler2D brdfLUT;
uniform sampler2D baseColourTexture;
uniform vec4 baseColourFactor;
uniform sampler2D pbrMetallicRoughness;
uniform float metallicFactor;
uniform float roughnessFactor;
uniform sampler2D occlusionTexture;
uniform sampler2D normalTexture;
uniform sampler2D emissiveTexture;

uniform samplerCube irradianceMap;
uniform samplerCube prefilterMap;

float PI = 3.14159265358979323;

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

vec3 FresnelSchlickRoughness(vec3 V, vec3 H, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - max(dot(H, V), 0.0), 0.0, 1.0), 5.0);
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

void main() {
    vec3 albedo = texture(baseColourTexture, texCoords).rgb;
    albedo *= baseColourFactor.rgb;
    float roughness = texture(pbrMetallicRoughness, texCoords).g;
    float metallic = texture(pbrMetallicRoughness, texCoords).b;
    vec3 fragNormal = normalize(texture(normalTexture, texCoords).rgb * 2.0 - 1.0);
    vec3 occlusion = texture(occlusionTexture, texCoords).rgb;

    vec3 geomNormal = normalize(TBN * normal);
    vec3 viewDir = normalize(cameraPosition - position);

    vec3 normal = fragNormal;
    vec3 R = reflect(-viewDir, normal);

    vec3 fresnelIncidence = mix(vec3(0.04), albedo, metallic);

    uint spotLightSize = 16;
    uint directionalLightSize = 12;
    uint pointLightSize = 8;

    vec3 lightOutputted = vec3(0.0);

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

    vec3 F = FresnelSchlickRoughness(normal, viewDir, fresnelIncidence, roughness);
    vec3 kD = 1.0 - F;
    kD *= 1.0 - metallic;

    vec3 irradiance = texture(irradianceMap, normal).rgb;
    vec3 diffuse = irradiance * albedo;

    const float MAX_REFLECTION_LOD = 4.0;
    vec3 prefilteredColor = textureLod(prefilterMap, R, roughness * MAX_REFLECTION_LOD).rgb;
    vec2 brdf = texture(brdfLUT, vec2(max(dot(normal, viewDir), 0.0), roughness)).rg;
    vec3 specular = prefilteredColor * (F * brdf.r + brdf.g);

    vec3 ambient = (kD * diffuse + specular) * occlusion;
    // vec3 ambient = (kD * diffuse);

    vec3 colour = ambient + lightOutputted;
    // vec3 colour = lightOutputted;

    // HDR
    colour = colour / (colour + vec3(1.0));
    colour = pow(colour, vec3(1.0 / 2.2));
    Colour = vec4(colour, 1.0);
}
