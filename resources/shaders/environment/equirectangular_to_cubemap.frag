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
    vec3 env = textureLod(environmentTex, uv, 0.0).rgb;

    const float MAXIMUM_RADIANCE = 500.0;
    env = clamp(env, vec3(0.0), vec3(MAXIMUM_RADIANCE));
    Colour = vec4(env, 1.0);
}