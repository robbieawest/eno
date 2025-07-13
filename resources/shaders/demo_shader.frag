#version 440

layout(std430, binding = 1) buffer LightBuf {
    uint numSpotLights;
    uint numDirectionalLights;
    uint numPointLights;
    uint _pad;
    float lightData[];  // Raw buffer of light data
} Lights;

struct LightSourceInformation {
    vec3 colour;
    float _pad;
    vec3 position;
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
    lightInformation.colour.r = lightData[index];
    lightInformation.colour.g = lightData[index + 1];
    lightInformation.colour.b = lightData[index + 2];
    lightInformation.colour.a = lightData[index + 3];
    lightInformation.position.x = lightData[index + 4];
    lightInformation.position.y = lightData[index + 5];
    lightInformation.position.z = lightData[index + 6];
    lightInformation.intensity = lightData[index + 7];
    return lightInformation;
}

SpotLight getSpotLight(uint index) {
    SpotLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.direction.x = lightData[index + 8];
    light.direction.y = lightData[index + 9];
    light.direction.z = lightData[index + 10];
    light.innerConeAngle = lightData[index + 11];
    light.outerConeAngle = lightData[index + 12];
    return light;
}

DirectionalLight getDirectionalLight(uint index) {
    DirectionalLight light;
    light.lightInformation = getLightSourceInformation(index);
    light.direction.x = lightData[index + 8];
    light.direction.y = lightData[index + 9];
    light.direction.z = lightData[index + 10];
    return light;
}

PointLight getPointLight(uint index) {
    PointLight light;
    light.lightInformation = getLightSourceInformation(index);
    return light;
}


in vec3 position;  // World
in vec3 normal;  // World
in vec2 texCoords;
in vec3 cameraPosition;  // World
out vec4 Colour;

uniform sampler2D baseColourTexture;
uniform vec4 baseColourFactor;
uniform sampler2D pbrMetallicRoughness;
uniform float metallicFactor;
uniform float roughnessFactor;
uniform sampler2D occlusionTexture;
uniform sampler2D normalTexture;
uniform sampler2D emissiveTexture;


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
    float k = ( r* r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeomSmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeomSchlickGGX(NdotV, roughness);
    float ggx1  = GeomSchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 FresnelShlick(vec3 V, vec3 H, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - max(dot(H, V), 0.0), 0.0, 1.0), 5.0);
}

vec3 calculateBRDF(vec3 N, vec3 V, vec3 L, vec3 H, vec3 albedo, float roughness, float metallic) {
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeomSmith(N, V, L, roughness);
    vec3 fresnelIncidence = mix(vec3(0.04), albedo, metallic);
    vec3 fresnel = FresnelSchlick(max(dot(H, V), 0.0), fresnelIncidence);

    vec3 num = NDF * G * fresnel;
    float denom = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = num / denom;

    vec3 diffuseShare = (vec3(1.0) - fresnel) * (1 - metallic);
    vec3 lambertian = albedo / 3.1415926323;
    return diffuseShare * lambertian + specular;
}

vec3 calculateReflectance(vec3 BRDF, vec3 N, vec3 L, float radiance) {
    return BRDF * radiance * max(dot(N, L), 0.0);
}

void main() {
    vec3 albedo = texture(baseColourTexture, texCoords).rgb;
    float roughness = texture(pbrMetallicRoughness, texCoords).g;
    float metallic = texture(pbrMetallicRoughness, texCoords).b;
    vec3 fragNormal = normalize(texture(normalTexture, texCoords).rgb);
    vec3 occlusion = texture(occlusionTexture, texCoords).rgb;

    vec3 geomNormal = normalize(normal);
    vec3 viewDir = normalize(cameraPosition - position);

    uint spotLightSize = 64;
    uint directionalLightSize = 48;
    uint pointLightSize = 32;

    vec3 lightOutputted = vec3(0.0);

    uint bufIndex = Lights.numSpotLights * spotLightSize + Lights.numDirectionalLights * directionalLightSize;
    for (uint i = 0; i < Lights.numPointLights; i++) {
        PointLight light = getPointLight(bufIndex);
        vec3 lightDir = normalize(light.lightInformation.position - position);
        vec3 half = normalize(lightDir + viewDir);

        float lightDist = length(lightDir);
        vec3 radiance = light.lightInformation.colour / (lightDist * lightDist);

        vec3 BRDF = calculateBRDF(geomNormal, viewDir, lightDir, half, albedo, roughness * roughnessFactor, metallic * metallicFactor);
        vec3 reflectance = calculateReflectance(BRDF, geomNormal, lightDir, radiance);
        lightOutputted += reflectance;

        bufIndex += pointLightSize;
    }

    // Ambient - arbitrary
    vec3 ambient = vec3(0.03) * albedo * occlusion;
    Colour = ambient + lightOutputted;

    // HDR
    Colour = Colour / (Colour + vec3(1.0));
    Colour = pow(Colour, vec3(1.0 / 2.2));
}
