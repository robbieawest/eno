#version 440

in vec2 texCoords;

uniform sampler2D SSAOColour;

out float Colour;

void main() {
    float SSAOCol = texture(SSAOColour, texCoords).r;
    Colour = SSAOCol * 0.5;
}
