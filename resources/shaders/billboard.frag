#version 440

uniform sampler2D baseColourTexture;

in vec2 texCoords;
out vec4 Colour;

void main() {
    vec4 colour = texture(baseColourTexture, texCoords);
    if (colour.a < 0.05) {
        discard;
    }
    colour = vec4(0.0, 0.9, 0.0, 1.0);
    Colour = colour;
}