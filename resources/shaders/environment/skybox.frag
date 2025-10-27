#version 440

out vec4 Colour;
in vec3 texCoords;

uniform samplerCube environmentMap;

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

void main() {
    vec3 envColour = textureLod(environmentMap, texCoords, 0).rgb;
    envColour = KhronosNeutralTonemapping(envColour);
    envColour = pow(envColour, vec3(1.0 / 2.2));
    Colour = vec4(envColour, 1.0);
    // Colour = vec4(texCoords, 1.0);
    // Colour = vec4(1.0);
}