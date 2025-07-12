#version 440

layout(std430, binding = 1) buffer Lights {
    uint numSpotLights;
    uint numDirectionalLights;
    uint numPointLights;
    uint _pad;
    float lightData[];  // Raw buffer of light data
};

struct LightSourceInformation {
    vec4 colour;
    vec3 position;
    float intensity;
};

struct SpotLight {
    LightSourceInformation lightInformation;
    vec3 direction;
    float innerConeAngle;
    float outerConeAngle;
};

struct DirectionalLight {
    LightSourceInformation lightInformation;
    vec3 direction;
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


in vec3 position;
in vec3 normal;
in vec2 texCoords;
out vec4 Colour;

uniform sampler2D baseColourTexture;
uniform vec4 baseColourFactor;
uniform sampler2D pbrMetallicRoughness;
uniform float metallicFactor;
uniform float roughnessFactor;
uniform sampler2D occlusionTexture;
uniform sampler2D normalTexture;
uniform sampler2D emissiveTexture;

void main() {
    vec3 albedo = texture(baseColourTexture, texCoords).rgb;
    float roughness = texture(pbrMetallicRoughness, texCoords).g;
    float metallic = texture(pbrMetallicRoughness, texCoords).b;
    vec3 fragNormal = texture(normalTexture, texCoords).rgb;
    vec3 occlusion = texture(occlusionTexture, texCoords).rgb;
    vec4 factor = baseColourFactor;
    float mfactor = metallicFactor;
    Colour = vec4(albedo, 1.0);
}
