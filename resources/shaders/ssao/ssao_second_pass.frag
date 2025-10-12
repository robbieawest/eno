#version 440

in vec2 texCoords;

uniform sampler2D SSAOColour;

out vec3 Colour;

void main() {
    vec2 texelSize = 1.0 / vec2(textureSize(SSAOColour, 0));
    vec3 result = vec3(0.0);
    for (int x = -2; x < 2; ++x)
    {
        for (int y = -2; y < 2; ++y)
        {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            result += texture(SSAOColour, texCoords + offset).rgb;
        }
    }
    Colour = result / (4.0 * 4.0);
}
