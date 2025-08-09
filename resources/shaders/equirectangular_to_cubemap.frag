#version 440

out vec4 Colour;
in vec3 position;

// https://learnopengl.com

uniform sampler2D environmentTex;
const vec2 invAtan = vec2(0.1591, 0.3183);
vec2 UVFromSpherical(vec3 v) {
    vec2 uv = vec2(atan(v.z, v.x), asin(v.y));
    uv *= invAtan;
    uv *= 0.5;
    return uv;
}

void main() {
    vec2 uv = UVFromSpherical(normalize(position));
    Colour = vec4(texture(environmentTex, uv).rgb, 1.0);
}