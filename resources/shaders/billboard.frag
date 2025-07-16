#version 440

uniform sampler2D baseColourTexture;

in vec2 texCoords;
out vec4 Colour;

void main() {
    vec4 colour = texture(baseColourTexture, texCoords);
    if (colour.a < 0.05) {
        discard;
    }

    Colour = colour;
}