#version 440

out vec4 Colour;
in vec3 texCoords;

uniform samplerCube environmentMap;

void main() {
    vec3 envColour = textureLod(environmentMap, texCoords, 0.0).rgb;
    envColour /= envColour + vec3(1.0);
    envColour = pow(envColour, vec3(1.0 / 2.2));
    Colour = vec4(envColour, 1.0);
    // Colour = vec4(texCoords, 1.0);
    // Colour = vec4(1.0);
}