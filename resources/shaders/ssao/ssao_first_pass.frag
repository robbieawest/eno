#version 440

in vec2 texCoords;

uniform sampler2D gbDepth;
uniform sampler2D gbNormal;

out float Colour;

void main() {
    vec3 normal = texture(gbNormal, texCoords).rgb;
    Colour = (normal.r + normal.g + normal.b) / 3.0;
}
