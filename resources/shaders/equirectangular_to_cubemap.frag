#version 440

out vec4 Colour;
in vec3 position;

uniform sampler2D environmentTex;

vec2 UVFromSpherical(vec3 v) {
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    uv *= 0.5 * vec2(0.1591, 0.3183);
    return uv;
}

void main() {
    vec2 uv = UVFromSpherical(normalize(position));
    Colour = vec4(texture(environmentTex, uv).rgb, 1.0);
}