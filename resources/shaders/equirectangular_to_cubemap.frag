#version 440

out vec4 Colour;
in vec3 position;

const float PI = 3.14159265358979323;

uniform sampler2D environmentTex;
vec2 UVFromSpherical(vec3 v) {
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    return vec2(uv.x / (2.0 * PI) + 0.5, 0.5 - uv.y / PI);
}

void main() {
    vec2 uv = UVFromSpherical(normalize(position));
    Colour = vec4(textureLod(environmentTex, uv, 0.0).rgb, 1.0);
}