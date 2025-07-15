#version 440

uniform sampler2D baseColourTexture;

in vec2 texCoords;
out vec4 Colour;

void main() {
    Colour = texture(baseColourTexture, texCoords);
}