package linalg_utils

import glm "core:math/linalg/glsl"

vec4 :: proc(vec3: glm.vec3, w: f32) -> (glm.vec4) {
    return { vec3.x, vec3.y, vec3.z, w }
}