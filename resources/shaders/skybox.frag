#version 440

out vec4 Colour;
in vec3 texCoords;

uniform samplerCube environmentMap;

void main() {
    Colour = texture(environmentMap, texCoords);
    // Colour = vec4(texCoords, 1.0);
    // Colour = vec4(1.0);
}