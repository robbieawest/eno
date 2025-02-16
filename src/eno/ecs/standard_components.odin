package ecs

import glm "core:math/linalg/glsl"


MODEL_COMPONENT :: "model"  // Of type model.Model
WORLD_COMPONENT :: "world"  // Of type WorldComponent
LIGHT_SOURCE_COMPONENT :: "light_source"  // Of type render.LightSource

WorldComponent :: struct {
    position: glm.vec3,
    scale: glm.vec3,
    rotation: glm.quat
}